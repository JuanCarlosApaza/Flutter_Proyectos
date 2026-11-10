/// Filas «talla · color · cantidad» del formulario de producto: aquí es
/// donde quien crea la prenda escribe **sus** tallas (S, M, XXL, 4...) y
/// **sus** colores (Negro, Azul marino...), en vez de elegir de una lista
/// de fábrica.
///
/// Los catálogos arrancan vacíos (las migraciones dejaron de sembrar datos
/// de ejemplo), así que cada selector trae el botón «Nueva talla» /
/// «Nuevo color»: se escribe el nombre y se da de alta sin salir del
/// formulario, el mismo patrón que «Nueva categoría» del propio alta de
/// producto. Lo que viaja a la API es el **nombre**; el backend lo busca en
/// `tallas`/`colores` y lo crea si no existía, todo en la transacción del
/// alta.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import 'buscador_tabla.dart';
import 'desplegable_buscable.dart';
import 'recurso_form.dart';

/// Fila del editor: los campos de una combinación concreta.
///
/// Los controladores viven en la fila (y no en el widget) para que el texto
/// sobreviva a los repintados y para poder leerlo entero al guardar.
final class FilaVarianteAlta {
  FilaVarianteAlta({
    String talla = '',
    String color = '',
    String cantidad = '1',
  }) : id = ++_ids,
       talla = TextEditingController(text: talla),
       color = TextEditingController(text: color),
       cantidad = TextEditingController(text: cantidad);

  /// Contador para dar identidad estable a cada fila (clave de sus campos).
  static int _ids = 0;

  /// Identidad de la fila: al quitar una, las demás no se reescriben.
  final int id;

  /// Reinicia el contador de filas (solo en tests: el contador es estático y
  /// sin esto las claves de las filas cambiarían de una prueba a otra).
  @visibleForTesting
  static void reiniciarIds() => _ids = 0;

  final TextEditingController talla;
  final TextEditingController color;
  final TextEditingController cantidad;

  /// La fila tal como la espera el backend: `[{talla, color, stock}, ...]`.
  Map<String, Object?> aJson() => {
    'talla': talla.text.trim(),
    'color': color.text.trim(),
    'stock': int.tryParse(cantidad.text.trim()) ?? 0,
  };

  void dispose() {
    talla.dispose();
    color.dispose();
    cantidad.dispose();
  }
}

/// Da de alta un nombre nuevo en el catálogo del controlador (tallas o
/// colores) y devuelve el registro: el que ya existía —comparando sin
/// distinguir mayúsculas ni acentos, y reactivando uno oculto— o el
/// recién creado.
///
/// Es la misma idea que «Nueva categoría» del formulario de producto: se
/// escribe el nombre y queda en su tabla, sin depender de datos de fábrica.
Future<Recurso> altaEnCatalogo(
  RecursoController controller,
  String nombre,
) async {
  final buscado = normalizarTexto(nombre);
  for (final item in controller.items) {
    final propio = item.texto('nombre', vacio: '');
    if (propio.isEmpty || normalizarTexto(propio) != buscado) continue;
    if (item.texto('estado') == 'ELIMINADO') {
      // Un nombre oculto vuelve a estar disponible: si el rol no puede
      // editarlo, el backend lo reactivará igualmente al guardar.
      try {
        await controller.actualizar(item.id, {'estado': 'ACTIVO'});
      } catch (_) {
        // Se ignora: el registro existe y su nombre es el bueno.
      }
    }
    return item;
  }
  return controller.crear({'nombre': nombre});
}

/// Fuentes de los dos desplegables del editor.
///
/// Las opciones se leen en cada pintado (otra pantalla puede haber creado
/// una talla mientras este formulario estaba abierto) y las altas en línea
/// devuelven el nombre que queda seleccionado.
final class ConfigVariantesAlta {
  const ConfigVariantesAlta({
    required this.tallas,
    required this.colores,
    required this.crearTalla,
    required this.crearColor,
  });

  /// Tallas ya dadas de alta (valor y etiqueta = el nombre).
  final List<Opccion> Function() tallas;

  /// Colores ya dados de alta.
  final List<Opccion> Function() colores;

  /// Da de alta un nombre nuevo y devuelve el que queda seleccionado. Si ya
  /// existía (sin distinguir mayúsculas) devuelve el registrado, para no
  /// duplicarlo.
  final Future<String> Function(String nombre) crearTalla;
  final Future<String> Function(String nombre) crearColor;
}

/// Editor de las variantes del producto: lista de filas + botón de alta.
///
/// No valida nada por sí mismo (la validación es del formulario, ver
/// `RecursoForm`), solo pinta [error] cuando se la pasan.
final class EditorVariantesAlta extends StatefulWidget {
  const EditorVariantesAlta({
    super.key,
    required this.filas,
    required this.config,
    required this.onAgregar,
    required this.onQuitar,
    this.error,
    this.habilitado = true,
    this.etiqueta = 'Tallas y colores *',
  });

  final List<FilaVarianteAlta> filas;
  final ConfigVariantesAlta config;
  final VoidCallback onAgregar;
  final ValueChanged<FilaVarianteAlta> onQuitar;
  final String? error;
  final bool habilitado;
  final String etiqueta;

  @override
  State<EditorVariantesAlta> createState() => _EditorVariantesAltaState();
}

final class _EditorVariantesAltaState extends State<EditorVariantesAlta> {
  /// Alta en línea y refresco: el registro nuevo ya vive en el catálogo,
  /// así que las opciones se vuelven a leer para poder elegirlo otra vez.
  Future<String> _crear(
    Future<String> Function(String nombre) crear,
    String nombre,
  ) async {
    final valor = await crear(nombre);
    if (mounted) setState(() {});
    return valor;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final filas = widget.filas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.etiqueta, style: tema.bodyMedium),
        const SizedBox(height: 4),
        Text(
          'Cada fila es una talla y un color con su cantidad. Si el que '
          'buscas no existe, créalo ahí mismo con «Nueva talla» o '
          '«Nuevo color».',
          style: tema.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        if (filas.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Text(
              'Sin filas todavía: si la prenda no tiene tallas (medias, '
              'gorros...), déjalo así y se guardará como «Única». ¿Sí '
              'tiene? Añade la primera combinación.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else
          for (final fila in filas) _fila(context, fila),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: widget.habilitado ? widget.onAgregar : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Añadir talla y color'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandGreen,
            side: const BorderSide(color: AppColors.brandGreen),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.error!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  /// Una fila: en pantallas estrechas (celular) los campos se apilan y en
  /// escritorio van en línea con el botón de quitar al final.
  Widget _fila(BuildContext context, FilaVarianteAlta fila) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, restriccion) {
          if (restriccion.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _selectorTalla(fila),
                const SizedBox(height: 8),
                _selectorColor(fila),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _campoCantidad(fila)),
                    const SizedBox(width: 8),
                    _botonQuitar(fila),
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _selectorTalla(fila)),
              const SizedBox(width: 8),
              Expanded(child: _selectorColor(fila)),
              const SizedBox(width: 8),
              SizedBox(width: 92, child: _campoCantidad(fila)),
              _botonQuitar(fila),
            ],
          );
        },
      ),
    );
  }

  Widget _selectorTalla(FilaVarianteAlta fila) => DesplegableBuscable(
    key: ValueKey('talla-${fila.id}'),
    initialValue: fila.talla.text.isEmpty ? null : fila.talla.text,
    opciones: widget.config.tallas(),
    habilitado: widget.habilitado,
    onChanged: (valor) => fila.talla.text = (valor ?? '').trim(),
    decoracion: const InputDecoration(
      labelText: 'Talla *',
      helperText: 'S, M, XXL, 4…',
    ),
    onCrear: widget.habilitado
        ? (nombre) => _crear(widget.config.crearTalla, nombre)
        : null,
    etiquetaCrear: 'Nueva talla',
  );

  Widget _selectorColor(FilaVarianteAlta fila) => DesplegableBuscable(
    key: ValueKey('color-${fila.id}'),
    initialValue: fila.color.text.isEmpty ? null : fila.color.text,
    opciones: widget.config.colores(),
    habilitado: widget.habilitado,
    onChanged: (valor) => fila.color.text = (valor ?? '').trim(),
    decoracion: const InputDecoration(
      labelText: 'Color *',
      helperText: 'Negro, Azul marino…',
    ),
    onCrear: widget.habilitado
        ? (nombre) => _crear(widget.config.crearColor, nombre)
        : null,
    etiquetaCrear: 'Nuevo color',
  );

  Widget _campoCantidad(FilaVarianteAlta fila) => TextFormField(
    key: ValueKey('cantidad-${fila.id}'),
    controller: fila.cantidad,
    enabled: widget.habilitado,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: const InputDecoration(labelText: 'Cantidad *'),
  );

  Widget _botonQuitar(FilaVarianteAlta fila) => IconButton(
    tooltip: 'Quitar fila',
    icon: Icon(
      Icons.delete_outline,
      size: 20,
      color: widget.habilitado ? AppColors.textSecondary : AppColors.cardBorder,
    ),
    onPressed: widget.habilitado ? () => widget.onQuitar(fila) : null,
  );
}
