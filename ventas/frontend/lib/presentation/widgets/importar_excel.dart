import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/guardar_fichero.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../controllers/recurso_controller.dart';
import '../importar/lector_excel.dart';
import '../importar/plantilla_excel.dart';
import '../importar/validador_producto.dart';
import 'recurso_form.dart';

/// Fichero elegido por el usuario (nombre + bytes).
typedef FicheroElegido = ({String nombre, Uint8List bytes});

/// Abre la importación masiva de productos en sus **3 pasos**:
/// archivo → vista previa → resultado.
///
/// El .xlsx se lee y se genera **en el navegador/escritorio**: el backend
/// solo recibe JSON. Devuelve `true` si se importó algo (el llamador debe
/// recargar la lista).
///
/// [elegirArchivo] y [guardarPlantilla] son para los tests: por defecto
/// abren el selector de ficheros y el diálogo de guardado del sistema.
Future<bool?> mostrarImportarExcel(
  BuildContext context, {
  required List<CampoFormulario> campos,
  required CategoriasController categorias,
  required PresentacionesController presentaciones,
  required MarcasController marcas,
  required ProveedoresController proveedores,
  ApiClient? api,
  Future<FicheroElegido?> Function()? elegirArchivo,
  Future<bool> Function(Uint8List bytes, String nombre)? guardarPlantilla,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _DialogoImportar(
    campos: campos,
    categorias: categorias,
    presentaciones: presentaciones,
    marcas: marcas,
    proveedores: proveedores,
    api: api,
    elegirArchivo: elegirArchivo,
    guardarPlantilla: guardarPlantilla,
  ),
);

Future<bool> _guardarEnDisco(Uint8List bytes, String nombre) => guardarFichero(
  bytes,
  nombre,
  etiqueta: 'Plantilla de productos',
  extensiones: const ['xlsx'],
);

Future<FicheroElegido?> _elegirDeDisco() async {
  final fichero = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Excel', extensions: ['xlsx']),
    ],
  );
  if (fichero == null) return null;
  return (nombre: fichero.name, bytes: await fichero.readAsBytes());
}

class _DialogoImportar extends StatefulWidget {
  const _DialogoImportar({
    required this.campos,
    required this.categorias,
    required this.presentaciones,
    required this.marcas,
    required this.proveedores,
    this.api,
    this.elegirArchivo,
    this.guardarPlantilla,
  });

  final List<CampoFormulario> campos;
  final CategoriasController categorias;
  final PresentacionesController presentaciones;
  final MarcasController marcas;
  final ProveedoresController proveedores;
  final ApiClient? api;
  final Future<FicheroElegido?> Function()? elegirArchivo;
  final Future<bool> Function(Uint8List bytes, String nombre)? guardarPlantilla;

  @override
  State<_DialogoImportar> createState() => _DialogoImportarState();
}

class _DialogoImportarState extends State<_DialogoImportar> {
  static const _porPagina = 8;

  int _paso = 1;
  int _pagina = 0;
  String? _archivo;
  List<FilaValidada> _filas = const [];
  bool _enviando = false;
  Map<String, Object?>? _resultado;

  List<FilaValidada> get _importables =>
      _filas.where((f) => f.debeImportar).toList();

  Future<void> _descargarPlantilla() async {
    final bytes = plantillaProductos(campos: widget.campos);
    await (widget.guardarPlantilla ?? _guardarEnDisco)(
      bytes,
      'productos_plantilla.xlsx',
    );
  }

  Future<void> _elegirArchivo() async {
    final fichero = await (widget.elegirArchivo ?? _elegirDeDisco)();
    if (fichero == null || !mounted) return;
    final lectura = leerFilasExcel(fichero.bytes, campos: widget.campos);
    if (lectura.hayError) {
      await alertaError(context, mensaje: lectura.error!);
      return;
    }
    final filas = validarFilas(filas: lectura.filas, campos: widget.campos);
    if (filas.isEmpty) {
      await alertaError(
        context,
        mensaje: 'El archivo no tiene ninguna fila de datos.',
      );
      return;
    }
    setState(() {
      _archivo = fichero.nombre;
      _filas = filas;
      _pagina = 0;
      _paso = 2;
    });
  }

  /// Crea primero las relaciones que faltaban (como el botón «+» del
  /// formulario, una sola vez por nombre) y luego manda las filas.
  Future<void> _importar() async {
    // El cliente HTTP se toma ANTES del primer `await`: después de una
    // espera no puede usarse el contexto.
    final api = widget.api ?? context.read<ApiClient>();
    setState(() => _enviando = true);
    try {
      final ids = <String, String>{};
      for (final fila in _importables) {
        for (final pendiente in fila.pendientes) {
          final clave = '${pendiente.clave}:${pendiente.nombre}';
          if (ids.containsKey(clave)) continue;
          final creado = switch (pendiente.clave) {
            'categoriaId' => await widget.categorias.crear({
              'nombre': pendiente.nombre,
            }),
            'presentacionId' => await widget.presentaciones.crear({
              'nombre': pendiente.nombre,
            }),
            'marcaId' => await widget.marcas.crear({
              'nombre': pendiente.nombre,
            }),
            'proveedorId' => await widget.proveedores.crear({
              'nombre': pendiente.nombre,
            }),
            _ => null,
          };
          if (creado != null) ids[clave] = '${creado.id}';
        }
      }

      final filas = <Map<String, Object?>>[
        for (final fila in _importables)
          {
            ...fila.cuerpo,
            for (final pendiente in fila.pendientes)
              if (ids.containsKey('${pendiente.clave}:${pendiente.nombre}'))
                pendiente.clave: ids['${pendiente.clave}:${pendiente.nombre}'],
            'fila': fila.fila,
          },
      ];

      final respuesta = await api.post(
        '/api/v1/products/importar',
        body: {'archivo': _archivo, 'filas': filas},
        timeout: const Duration(seconds: 120),
      );
      if (!mounted) return;
      setState(() {
        _resultado = Map<String, Object?>.from(respuesta as Map);
        _paso = 3;
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      await alertaError(
        context,
        mensaje: e is Failure ? e.message : 'No se pudo importar el archivo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(switch (_paso) {
        2 => 'Vista previa de la importación',
        3 => 'Importación terminada',
        _ => 'Importar productos desde Excel',
      }),
      content: SizedBox(
        width: 780,
        height: 440,
        child: switch (_paso) {
          2 => _vistaPrevia(),
          3 => _resultadoWidget(),
          _ => _elegirFichero(),
        },
      ),
      actions: [
        switch (_paso) {
          2 => TextButton(
            onPressed: _enviando ? null : () => setState(() => _paso = 1),
            child: const Text('Atrás'),
          ),
          3 => ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar'),
          ),
          _ => const SizedBox.shrink(),
        },
        if (_paso == 2)
          ElevatedButton.icon(
            onPressed: _enviando || _importables.isEmpty ? null : _importar,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file, size: 18),
            label: Text(
              'Importar ${_importables.length} '
              '${_importables.length == 1 ? 'válida' : 'válidas'}',
            ),
          )
        else if (_paso == 1)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
      ],
    );
  }

  // ── Paso 1: archivo ──────────────────────────────────────────────────

  Widget _elegirFichero() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Descarga la plantilla, rellena tus productos en la hoja «datos» '
        'y elígela aquí. El archivo se lee en tu equipo: no se sube a '
        'ningún servidor.',
        style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: _descargarPlantilla,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Descargar plantilla (.xlsx)'),
          ),
          FilledButton.icon(
            onPressed: _elegirArchivo,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: const Text('Elegir archivo'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Text(
        'Obligatorios: nombre, precios, stock, unidad, estado, categoría, '
        'presentación y marca. Máximo 1000 filas.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    ],
  );

  // ── Paso 2: vista previa ─────────────────────────────────────────────

  Widget _vistaPrevia() {
    final resumen = resumenImportacion(_filas);
    final inicio = _pagina * _porPagina;
    final trozo = _filas.skip(inicio).take(_porPagina).toList();
    final totalPaginas = (_filas.length / _porPagina).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '✓ ${resumen.validas} ${resumen.validas == 1 ? 'válida' : 'válidas'}'
          ' · ✖ ${resumen.conError} con error'
          ' · ${resumen.repetidas} repetidas · ${_archivo ?? ''}',
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [for (final fila in trozo) _filaVista(fila)],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Filas ${inicio + 1}–${inicio + trozo.length} de '
              '${_filas.length}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: _pagina > 0
                      ? () => setState(() => _pagina--)
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 20),
                ),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: _pagina + 1 < totalPaginas
                      ? () => setState(() => _pagina++)
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _filaVista(FilaValidada fila) {
    final (color, icono, texto) = fila.duplicada
        ? (
            AppColors.warningOrange,
            Icons.copy_all_outlined,
            fila.motivo ?? 'Repetida',
          )
        : fila.valida
        ? (
            AppColors.positiveGreen,
            Icons.check_circle_outline,
            'Lista para importar',
          )
        : (AppColors.negativeRed, Icons.error_outline, fila.motivo ?? 'Error');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            'Fila ${fila.fila}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Paso 3: resultado ────────────────────────────────────────────────

  Widget _resultadoWidget() {
    final creados = _resultado?['creados'] ?? 0;
    final omitidos = (_resultado?['omitidos'] as List?) ?? const [];
    final errores = (_resultado?['errores'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Se crearon $creados.'
          '${omitidos.isEmpty ? '' : ' ${omitidos.length} omitidas.'}'
          '${errores.isEmpty ? '' : ' ${errores.length} con error.'}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              for (final fila in omitidos) _resultadoFila(fila, omitido: true),
              for (final fila in errores) _resultadoFila(fila, omitido: false),
              if (omitidos.isEmpty && errores.isEmpty)
                const Text(
                  'Todo el archivo se importó sin incidencias.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultadoFila(Object? fila, {required bool omitido}) {
    final datos = fila is Map ? fila : const {};
    final numero = datos['fila'] ?? 0;
    final mensaje = datos['mensaje']?.toString() ?? '';
    final color = omitido ? AppColors.warningOrange : AppColors.negativeRed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            omitido ? Icons.copy_all_outlined : Icons.error_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fila $numero – $mensaje',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
