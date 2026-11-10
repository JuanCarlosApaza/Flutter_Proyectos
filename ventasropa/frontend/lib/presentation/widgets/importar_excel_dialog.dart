import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/excel/importar_productos.dart';
import '../../core/excel/leer_excel.dart';
import '../../core/excel/plantilla_excel.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/normalizacion.dart';
import '../controllers/recurso_controller.dart';

/// Abre el diálogo de **importación de productos desde Excel**.
///
/// Tres pasos: elegir archivo (y descargar la plantilla) → vista previa
/// con las filas válidas y sus errores → resultado del envío.
/// [elegirFichero] se inyecta en los tests (por defecto, el selector del
/// sistema) y [onImportado] se invoca tras importar para que la pantalla
/// recargue su listado.
Future<void> mostrarImportadorExcel(
  BuildContext context, {
  Future<Uint8List?> Function()? elegirFichero,
  Future<void> Function()? onImportado,
}) => showDialog(
  context: context,
  builder: (_) => ImportarExcelDialog(
    elegirFichero: elegirFichero,
    onImportado: onImportado,
  ),
);

/// Pasos del diálogo.
enum _Fase { archivo, previa, resultado }

/// Límite de productos por archivo (espejo del backend).
const int _limiteFilas = 1000;

class ImportarExcelDialog extends StatefulWidget {
  const ImportarExcelDialog({super.key, this.elegirFichero, this.onImportado});

  /// Lectura del fichero elegido. Por defecto, el selector del sistema;
  /// se inyecta en los tests para no depender del diálogo de archivos.
  final Future<Uint8List?> Function()? elegirFichero;

  /// Se invoca al terminar la importación (recargar el listado).
  final Future<void> Function()? onImportado;

  @override
  State<ImportarExcelDialog> createState() => _ImportarExcelDialogState();
}

class _ImportarExcelDialogState extends State<ImportarExcelDialog> {
  _Fase _fase = _Fase.archivo;
  List<FilaImportacion> _filas = const [];
  String? _aviso;
  bool _ocupado = false;

  // Resultado del envío (fase 3).
  int _creados = 0;
  int _enviados = 0;
  List<Map<String, dynamic>> _erroresFinales = const [];
  List<Map<String, dynamic>> _omitidosFinales = const [];

  Iterable<FilaImportacion> get _importables =>
      _filas.where((f) => f.importable);
  int get _conErrores => _filas.where((f) => f.errores.isNotEmpty).length;
  int get _repetidas => _filas.where((f) => f.duplicada).length;
  int get _variantesTotales => _importables.fold(
    0,
    (total, fila) => total + fila.producto!.variantes.length,
  );

  @override
  Widget build(BuildContext context) {
    final titulo = switch (_fase) {
      _Fase.archivo => 'Importar productos con Excel',
      _Fase.previa => 'Vista previa de la importación',
      _Fase.resultado => 'Importación terminada',
    };

    return AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 720,
        child: switch (_fase) {
          _Fase.archivo => _pantallaArchivo(),
          _Fase.previa => _pantallaPrevia(),
          _Fase.resultado => _pantallaResultado(),
        },
      ),
      actions: switch (_fase) {
        _Fase.archivo => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
        _Fase.previa => [
          TextButton(
            onPressed: _ocupado
                ? null
                : () => setState(() {
                    _fase = _Fase.archivo;
                    _aviso = null;
                  }),
            child: const Text('Elegir otro archivo'),
          ),
          ElevatedButton.icon(
            onPressed: _ocupado || _importables.isEmpty ? null : _importar,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: Text('Importar ${_importables.length} productos'),
          ),
        ],
        _Fase.resultado => [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      },
    );
  }

  // ── Paso 1: archivo ───────────────────────────────────────────────────

  Widget _pantallaArchivo() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carga decenas de productos de una sola vez: descarga la '
            'plantilla, rellénala en Excel y súbela aquí.\n\n'
            '· Una fila = un producto con sus variantes «talla|color|'
            'unidades».\n'
            '· ¿No tiene tallas (medias, gorros...)? Deja «Variantes» '
            'vacía y pon el «Stock inicial»: se guardará como «Única».\n'
            '· Las categorías, proveedores, tallas y colores nuevos se '
            'crean solos.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _ocupado ? null : _descargarPlantilla,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Descargar plantilla'),
              ),
              ElevatedButton.icon(
                onPressed: _ocupado ? null : _elegirArchivo,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Elegir archivo .xlsx'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_ocupado) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Leyendo el archivo...',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else if (_aviso != null) ...[
            _mensajeError(_aviso!),
          ] else
            const Text(
              'Máximo 1000 productos por archivo. Guarda el archivo como '
              '.xlsx (no .csv).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Future<void> _descargarPlantilla() async {
    try {
      await descargarPlantilla();
    } catch (e) {
      if (!mounted) return;
      setState(() => _aviso = 'No se pudo generar la plantilla: $e');
    }
  }

  Future<void> _elegirArchivo() async {
    // El cliente se toma antes del primer `await` (regla de `mounted`).
    final api = context.read<ApiClient>();

    Uint8List? contenido;
    try {
      contenido = await (widget.elegirFichero ?? _elegirPorDefecto)();
    } catch (_) {
      if (!mounted) return;
      setState(() => _aviso = 'No se pudo leer el fichero elegido.');
      return;
    }
    if (contenido == null || !mounted) return; // cancelado

    setState(() {
      _ocupado = true;
      _aviso = null;
    });

    final leido = leerExcel(contenido);
    if (leido.fallo != null) {
      setState(() {
        _ocupado = false;
        _aviso = leido.fallo;
      });
      return;
    }
    if (leido.filas.length > _limiteFilas) {
      setState(() {
        _ocupado = false;
        _aviso =
            'Máximo $_limiteFilas productos por archivo: el tuyo tiene '
            '${leido.filas.length}.';
      });
      return;
    }

    // Nombres ya en la BD, para avisar de repetidos ANTES de importar
    // (mejor esfuerzo: si falla, el backend sigue saltándolos igual).
    final existentes = await _nombresExistentes(api);
    if (!mounted) return;

    setState(() {
      _filas = validarFilasExcel(leido.filas, existentes: existentes);
      _fase = _Fase.previa;
      _ocupado = false;
    });
  }

  Future<Uint8List?> _elegirPorDefecto() async {
    final fichero = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    return fichero?.readAsBytes();
  }

  /// Nombres (normalizados) de los productos del inventario, recorriendo
  /// la API por páginas de 200.
  Future<Set<String>> _nombresExistentes(ApiClient api) async {
    final nombres = <String>{};
    try {
      var offset = 0;
      while (true) {
        final respuesta = await api.get(
          '/api/v1/productos',
          query: {'limit': '200', 'offset': '$offset'},
        );
        if (respuesta is! Map) break;
        final items = respuesta['items'];
        if (items is! List) break;
        for (final item in items.whereType<Map>()) {
          final nombre = item['nombre']?.toString();
          if (nombre != null && nombre.isNotEmpty) {
            nombres.add(normalizarTexto(nombre));
          }
        }
        final total = (respuesta['total'] as num?)?.toInt() ?? 0;
        offset += items.length;
        if (items.isEmpty || offset >= total) break;
      }
    } catch (_) {
      // Mejor esfuerzo: sin la lista, el backend sigue evitando duplicados.
    }
    return nombres;
  }

  // ── Paso 2: vista previa ──────────────────────────────────────────────

  Widget _pantallaPrevia() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _resumenChip('✓ ${_importables.length} productos', Colors.green),
            if (_variantesTotales > 0)
              _resumenChip('$_variantesTotales variantes', AppColors.infoBlue),
            if (_conErrores > 0)
              _resumenChip('✖ $_conErrores con error', AppColors.negativeRed),
            if (_repetidas > 0)
              _resumenChip(
                '⚠ $_repetidas repetidas (se saltan)',
                AppColors.warningOrange,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 340,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _filas.isEmpty
              ? const Center(
                  child: Text(
                    'No hay filas de datos en el archivo.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _filas.length,
                  itemBuilder: (context, indice) => _filaVista(_filas[indice]),
                ),
        ),
        if (_aviso != null) ...[
          const SizedBox(height: 10),
          _mensajeError(_aviso!),
        ],
      ],
    );
  }

  Widget _resumenChip(String texto, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      texto,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );

  Widget _filaVista(FilaImportacion fila) {
    final conError = fila.errores.isNotEmpty;
    final color = conError
        ? AppColors.negativeRed
        : fila.duplicada
        ? AppColors.warningOrange
        : Colors.green;
    final icono = conError
        ? Icons.close
        : fila.duplicada
        ? Icons.repeat
        : Icons.check;

    final detalle = conError
        ? fila.errores.join(' · ')
        : fila.avisos.isNotEmpty
        ? fila.avisos.join(' · ')
        : _resumenProducto(fila.producto!);

    final nombre = fila.celdas['nombre'] ?? '';
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fila ${fila.fila} · ${nombre.isEmpty ? "(sin nombre)" : nombre}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    detalle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: conError
                          ? AppColors.negativeRed
                          : fila.duplicada
                          ? AppColors.warningOrange
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resumenProducto(ProductoExcel producto) {
    final precios =
        'Bs ${producto.precioVenta.toStringAsFixed(2)} · '
        '${producto.categoria} · ${producto.proveedor}';
    if (producto.variantes.isEmpty) {
      final stock = producto.stock ?? 0;
      return '$precios · sin tallas → «Única» con stock '
          '${_sinCeros(stock)}';
    }
    return '$precios · ${producto.variantes.length} variantes';
  }

  String _sinCeros(double valor) {
    final texto = valor.toString();
    return texto.endsWith('.0') ? texto.substring(0, texto.length - 2) : texto;
  }

  // ── Paso 3: importar y resultado ──────────────────────────────────────

  Future<void> _importar() async {
    final importables = _importables.toList();
    if (importables.isEmpty) return;

    // Contextos capturados antes del primer `await`.
    final api = context.read<ApiClient>();
    final categorias = context.read<CategoriasController>();
    final marcas = context.read<MarcasController>();
    final proveedores = context.read<ProveedoresController>();

    setState(() {
      _ocupado = true;
      _aviso = null;
    });

    try {
      // Categorías, marcas y proveedores del archivo que falten se dan de
      // alta (mismo camino que «Nueva categoría» del formulario).
      final idsCategorias = await _asegurarCatalogos(categorias, [
        for (final fila in importables) fila.producto!.categoria,
      ]);
      final idsMarcas = await _asegurarCatalogos(marcas, [
        for (final fila in importables)
          if (fila.producto!.marca != null) fila.producto!.marca!,
      ]);
      final idsProveedores = await _asegurarCatalogos(proveedores, [
        for (final fila in importables) fila.producto!.proveedor,
      ]);

      final respuesta = await api.post(
        '/api/v1/productos/importar',
        body: {
          'productos': [
            for (final fila in importables)
              _cuerpoDe(fila, idsCategorias, idsMarcas, idsProveedores),
          ],
        },
      );
      if (!mounted) return;

      final mapa = respuesta is Map ? respuesta : const <String, Object?>{};
      setState(() {
        _creados = (mapa['creados'] as num?)?.toInt() ?? 0;
        _enviados = importables.length;
        _erroresFinales = _listaMapas(mapa['errores']);
        _omitidosFinales = _listaMapas(mapa['omitidos']);
        _fase = _Fase.resultado;
        _ocupado = false;
      });

      // Recarga del listado de productos (y catálogos recién creados).
      try {
        await widget.onImportado?.call();
      } catch (_) {
        // El listado ya se recarga con el gesto de actualizar si algo falla.
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _aviso = e is Failure ? e.message : 'No se pudo importar: $e';
      });
    }
  }

  /// Ids de cada nombre (normalizado) del catálogo, creando los que falten
  /// y reactivando los ocultos — misma idea que `altaEnCatalogo`.
  Future<Map<String, String>> _asegurarCatalogos(
    RecursoController controller,
    List<String> nombres,
  ) async {
    // Si el catálogo todavía no se ha cargado (la página lo hace tras el
    // primer frame), se carga ahora: el diálogo no depende de ello.
    if (controller.items.isEmpty) {
      try {
        await controller.cargar();
      } catch (_) {
        // Mejor esfuerzo: los nombres que falten se darán de alta igual.
      }
    }

    final unicos = <String, String>{};
    for (final nombre in nombres) {
      unicos.putIfAbsent(normalizarTexto(nombre), () => nombre);
    }

    final ids = <String, String>{};
    for (final entrada in unicos.entries) {
      String? id;
      for (final item in controller.items) {
        if (normalizarTexto(item.texto('nombre', vacio: '')) != entrada.key) {
          continue;
        }
        if (item.texto('estado') == 'ELIMINADO') {
          try {
            await controller.actualizar(item.id, {'estado': 'ACTIVO'});
          } catch (_) {
            // El registro existe y su nombre es el bueno.
          }
        }
        id = '${item.id}';
        break;
      }
      id ??= '${(await controller.crear({'nombre': entrada.value})).id}';
      ids[entrada.key] = id;
    }
    return ids;
  }

  Map<String, Object?> _cuerpoDe(
    FilaImportacion fila,
    Map<String, String> categorias,
    Map<String, String> marcas,
    Map<String, String> proveedores,
  ) {
    final producto = fila.producto!;
    return {
      // La fila real de Excel: los errores del backend apuntan a lo que
      // el usuario ve en su archivo (la cabecera es la 1).
      'fila': fila.fila,
      'nombre': producto.nombre,
      'categoriaId': categorias[normalizarTexto(producto.categoria)],
      'proveedorId': proveedores[normalizarTexto(producto.proveedor)],
      'precioCompra': producto.precioCompra,
      'precioVenta': producto.precioVenta,
      'variantes': [
        for (final v in producto.variantes)
          {'talla': v.talla, 'color': v.color, 'stock': v.stock},
      ],
      // Sin variantes va el stock de la variante «Única»; con variantes
      // lo ignora el backend (igual que el formulario).
      if (producto.variantes.isEmpty && producto.stock != null)
        'stock': producto.stock,
      if (producto.codigo != null) 'codigo': producto.codigo,
      // Marca opcional: ausente = prenda sin marca.
      if (producto.marca != null)
        'marcaId': marcas[normalizarTexto(producto.marca!)],
      'estado': producto.estado,
    };
  }

  List<Map<String, dynamic>> _listaMapas(Object? valor) => [
    if (valor is List)
      for (final item in valor)
        if (item is Map) Map<String, dynamic>.from(item),
  ];

  // ── Resultado ─────────────────────────────────────────────────────────

  Widget _pantallaResultado() {
    final todoLimpio = _erroresFinales.isEmpty && _omitidosFinales.isEmpty;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _creados == _enviados
                      ? 'Se crearon $_creados productos'
                      : 'Se crearon $_creados de $_enviados productos',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (todoLimpio) ...[
            const SizedBox(height: 10),
            const Text(
              'Todos los productos del archivo entraron sin incidencias.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
          if (_omitidosFinales.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Se saltaron ${_omitidosFinales.length} (ya existen):',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.warningOrange,
              ),
            ),
            const SizedBox(height: 6),
            _listaMensajes(
              _omitidosFinales
                  .map(
                    (o) =>
                        'Fila ${o['fila'] ?? '—'} · '
                        '${o['nombre'] ?? ''} — ${o['motivo'] ?? ''}',
                  )
                  .toList(),
              AppColors.warningOrange,
            ),
          ],
          if (_erroresFinales.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Quedaron ${_erroresFinales.length} filas con error:',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.negativeRed,
              ),
            ),
            const SizedBox(height: 6),
            _listaMensajes(
              _erroresFinales
                  .map(
                    (e) => 'Fila ${e['fila'] ?? '—'} — ${e['mensaje'] ?? ''}',
                  )
                  .toList(),
              AppColors.negativeRed,
            ),
            const SizedBox(height: 8),
            const Text(
              'Corrígelas en el archivo y vuelve a importar: las buenas no '
              'se repiten (se saltan por nombre).',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _listaMensajes(List<String> mensajes, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final mensaje in mensajes)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '· $mensaje',
            style: TextStyle(fontSize: 12, height: 1.35, color: color),
          ),
        ),
    ],
  );

  Widget _mensajeError(String texto) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.negativeRed.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.negativeRed.withValues(alpha: 0.4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: AppColors.negativeRed, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}
