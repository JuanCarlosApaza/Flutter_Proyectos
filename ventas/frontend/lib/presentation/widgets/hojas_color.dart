import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/carrito_controller.dart';
import '../controllers/recurso_controller.dart';

/// Chip circular con la muestra `#RRGGBB` del color.
///
/// Sin muestra (o inválida) se pinta la inicial del color sobre gris: el
/// hex es solo decoración de UI y nunca aparece impreso.
Widget chipColor(String? codigoHex, {String? nombre, double tamano = 26}) {
  Color? relleno;
  final hex = codigoHex ?? '';
  if (hex.length == 7 && hex.startsWith('#')) {
    final valor = int.tryParse(hex.substring(1), radix: 16);
    if (valor != null) relleno = Color(0xFF000000 | valor);
  }
  return CircleAvatar(
    radius: tamano / 2,
    backgroundColor: relleno ?? AppColors.trackGrey,
    child: relleno == null
        ? Text(
            (nombre ?? '?').isEmpty ? '?' : (nombre ?? '?')[0].toUpperCase(),
            style: TextStyle(
              fontSize: tamano * 0.45,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          )
        : null,
  );
}

/// Hoja «Elige el color»: variantes del producto para agregarla al carrito.
///
/// Cada fila es `chip · nombre · Stock N · Bs X`; una variante sin stock se
/// muestra «Agotado» en rojo y **no se puede elegir**. Si el producto tiene
/// una sola variante esta hoja no hace falta: el carrito la auto-selecciona.
Future<VarianteVenta?> elegirVariante(
  BuildContext context, {
  required Recurso producto,
  double? precio,
}) {
  final variantes = variantesDe(producto);
  return showModalBottomSheet<VarianteVenta>(
    context: context,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HojaElegirVariante(
      nombreProducto: producto.texto('nombre', vacio: 'Producto'),
      variantes: variantes,
      precio: precio ?? producto.numero('precioVenta') ?? 0,
    ),
  );
}

class _HojaElegirVariante extends StatelessWidget {
  const _HojaElegirVariante({
    required this.nombreProducto,
    required this.variantes,
    required this.precio,
  });

  final String nombreProducto;
  final List<VarianteVenta> variantes;
  final double precio;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elige el color',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              nombreProducto,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            for (final variante in variantes) ...[
              _fila(context, variante),
              const Divider(height: 1, color: AppColors.cardBorder),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, VarianteVenta variante) {
    final agotada = variante.agotada || !variante.vendible;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: chipColor(
        variante.codigoHex,
        nombre: variante.nombre,
        tamano: 32,
      ),
      title: Text(
        variante.nombre,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: agotada
          ? const Text(
              'Agotado',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.negativeRed,
                fontWeight: FontWeight.w600,
              ),
            )
          : Text(
              'Stock ${_cantidad(variante.stock)} · Bs '
              '${precio.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
      trailing: agotada
          ? const Icon(Icons.block, size: 18, color: AppColors.negativeRed)
          : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      // Sin stock no se elige: la fila queda inerte.
      onTap: agotada ? null : () => Navigator.pop(context, variante),
    );
  }

  /// `5`, `12.750`: los ceros de relleno no ensucian el rótulo.
  static String _cantidad(double valor) => valor == valor.roundToDouble()
      ? valor.toInt().toString()
      : valor.toString();
}

/// Hoja para elegir un color **del catálogo** (formulario de producto).
///
/// Lista solo los colores `ACTIVO` que no estén ya asignados en [excluidos]
/// (los `INACTIVO`/`BLOQUEADO` no aparecen en asignaciones nuevas) y ofrece
/// «+ Nuevo color» al final: mismo patrón que «Nueva categoría».
///
/// Devuelve `null` si se cancela; si no, `(id, nombre, hex)`.
Future<(int, String, String?)?> elegirColorDeCatalogo(
  BuildContext context, {
  required ColoresController colores,
  Set<int> excluidos = const {},
}) {
  return showModalBottomSheet<(int, String, String?)>(
    context: context,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HojaElegirColor(colores: colores, excluidos: excluidos),
  );
}

class _HojaElegirColor extends StatelessWidget {
  const _HojaElegirColor({required this.colores, required this.excluidos});

  final ColoresController colores;
  final Set<int> excluidos;

  @override
  Widget build(BuildContext context) {
    // Solo vivos y activos para asignaciones nuevas.
    final vivos = [
      for (final color in colores.items)
        if (color.texto('estado', vacio: 'ACTIVO') == 'ACTIVO' &&
            !excluidos.contains(color.id))
          color,
    ];
    vivos.sort(
      (a, b) =>
          a.texto('nombre', vacio: '').compareTo(b.texto('nombre', vacio: '')),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Elige el color',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (vivos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Aún no hay colores en el catálogo.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              ConstrainedBox(
                // Altura de ~6 filas: más colores → scroll.
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final color in vivos)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: chipColor(
                          color.texto('codigoHex', vacio: ''),
                          nombre: color.texto('nombre', vacio: ''),
                          tamano: 32,
                        ),
                        title: Text(
                          color.texto('nombre', vacio: 'Sin nombre'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onTap: () => Navigator.pop(context, (
                          color.id,
                          color.texto('nombre', vacio: ''),
                          color.datos['codigoHex'] as String?,
                        )),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => _nuevoColor(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo color'),
            ),
          ],
        ),
      ),
    );
  }

  /// Diálogo «Nuevo color» desde dentro de la hoja: al crearse, cierra la
  /// hoja con el color elegido.
  Future<void> _nuevoColor(BuildContext context) async {
    final resultado = await pedirNuevoColor(context, colores: colores);
    if (resultado == null || !context.mounted) return;
    Navigator.pop(context, resultado);
  }
}

/// Diálogo de nombre + paleta (patrón «Nueva categoría»): crea el color en
/// el catálogo con la muestra elegida y devuelve `(id, nombre, hex)` — o
/// `null` si se cancela, el nombre no sirve o la API rechaza el alta
/// (p. ej. `color_duplicado`).
///
/// Sirve tanto desde la hoja de colores como desde el botón «Nuevo color»
/// del formulario de producto. **No hace falta teclear ningún hexadecimal**:
/// el color se elige de la paleta.
Future<(int, String, String?)?> pedirNuevoColor(
  BuildContext context, {
  required ColoresController colores,
}) async {
  final resultado = await showDialog<({String nombre, String hex})>(
    context: context,
    builder: (_) => const _DialogoNuevoColor(),
  );
  if (resultado == null || !context.mounted) return null;
  final nombre = resultado.nombre;
  if (nombre.length < 2) return null;

  try {
    final creado = await colores.crear({
      'nombre': nombre,
      'codigoHex': resultado.hex.isEmpty ? null : resultado.hex,
    });
    return (
      creado.id,
      creado.texto('nombre', vacio: nombre),
      creado.datos['codigoHex'] as String?,
    );
  } on Failure catch (failure) {
    if (context.mounted) {
      await alertaError(context, mensaje: failure.message);
    }
    return null;
  }
}

class _DialogoNuevoColor extends StatefulWidget {
  const _DialogoNuevoColor();

  @override
  State<_DialogoNuevoColor> createState() => _DialogoNuevoColorState();
}

class _DialogoNuevoColorState extends State<_DialogoNuevoColor> {
  final TextEditingController _nombre = TextEditingController();

  /// Muestra elegida (`#RRGGBB`); vacío = sin muestra.
  String _muestra = '';

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Nuevo color'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombre,
              autofocus: true,
              maxLength: 50,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'p. ej. Verde botella',
              ),
              onSubmitted: (_) => _crear(context),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                chipColor(_muestra.isEmpty ? null : _muestra, tamano: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _elegirMuestra,
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    label: Text(
                      _muestra.isEmpty ? 'Elegir color' : 'Cambiar color',
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.cardBorder),
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => _crear(context),
          child: const Text('Crear'),
        ),
      ],
    );
  }

  Future<void> _elegirMuestra() async {
    final elegida = await elegirMuestraDeColor(context, actual: _muestra);
    if (elegida == null || !mounted) return;
    setState(() => _muestra = elegida);
  }

  void _crear(BuildContext context) =>
      Navigator.pop(context, (nombre: _nombre.text.trim(), hex: _muestra));
}

/// Paleta para elegir la **muestra** de un color (el chip que se ve en
/// pantalla), sin teclear ningún hexadecimal.
///
/// Devuelve `#RRGGBB`, `''` (sin muestra) o `null` si se cancela.
Future<String?> elegirMuestraDeColor(BuildContext context, {String? actual}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _DialogoMuestra(actual: actual),
    );

/// Colores de la paleta: (nombre, RRGGBB) en el orden del arcoíris.
const List<(String, String)> _paleta = [
  ('Rojo', 'F44336'),
  ('Rojo fuerte', 'D32F2F'),
  ('Rosado', 'E91E63'),
  ('Violeta', '9C27B0'),
  ('Morado', '673AB7'),
  ('Índigo', '3F51B5'),
  ('Azul', '2196F3'),
  ('Cian', '00BCD4'),
  ('Verde azulado', '009688'),
  ('Verde', '4CAF50'),
  ('Verde claro', '8BC34A'),
  ('Lima', 'CDDC39'),
  ('Amarillo', 'FFEB3B'),
  ('Ámbar', 'FFC107'),
  ('Naranja', 'FF9800'),
  ('Naranja fuerte', 'FF5722'),
  ('Marrón', '795548'),
  ('Gris', '9E9E9E'),
  ('Gris azulado', '607D8B'),
  ('Negro', '212121'),
];

class _DialogoMuestra extends StatefulWidget {
  const _DialogoMuestra({this.actual});

  /// Muestra actual (`#RRGGBB` o vacío); con ella se preselecciona.
  final String? actual;

  @override
  State<_DialogoMuestra> createState() => _DialogoMuestraState();
}

class _DialogoMuestraState extends State<_DialogoMuestra> {
  late String _elegido = (widget.actual ?? '').toUpperCase();

  @override
  Widget build(BuildContext context) {
    final elegido = _elegido.startsWith('#') ? _elegido : '#$_elegido';
    final soloDigitos = elegido.substring(1);

    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Elige el color'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                chipColor(soloDigitos.length == 6 ? elegido : null, tamano: 28),
                const SizedBox(width: 10),
                Text(
                  soloDigitos.length == 6 ? elegido : 'Sin muestra',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (nombre, hex) in _paleta)
                  Tooltip(
                    message: nombre,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _elegido = '#$hex'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(int.parse('FF$hex', radix: 16)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: soloDigitos == hex
                                ? AppColors.textPrimary
                                : AppColors.cardBorder,
                            width: soloDigitos == hex ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Sin muestra'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(context, soloDigitos.length == 6 ? elegido : ''),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
