/// Selector de variante (talla + color) de una prenda.
///
/// El stock real vive en cada variante: antes de agregar (catálogo) o de
/// anotarla en una orden (ventas) hay que elegir talla y color. Si la
/// prenda tiene una sola variante se elige sola.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/carrito_controller.dart';

/// Abre el selector de talla/color de [producto] y devuelve la variante
/// elegida (`null` si no hay variantes visibles o se cancela).
///
/// La hoja es la misma del catálogo (círculo de color, talla · color,
/// stock y precio); [alCarrito] solo cambia el atajo de cada fila. Quien
/// llama decide qué hacer con la variante: agregarla al carrito o
/// anotarla en una línea de orden.
Future<Recurso?> elegirVariante(
  BuildContext context,
  Recurso producto, {
  bool alCarrito = false,
}) async {
  final visibles = variantesDe(producto)
      .where((v) => v.texto('estado') != 'ELIMINADO')
      .toList();

  if (visibles.isEmpty) return null;

  // Prenda de una sola variante (gorro, cinturón, «Única»): sin preguntar.
  if (visibles.length == 1) return visibles.first;

  if (!context.mounted) return null;
  return showModalBottomSheet<Recurso>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SelectorVariante(
      producto: producto,
      variantes: visibles,
      alCarrito: alCarrito,
    ),
  );
}

/// Agrega [producto] al carrito eligiendo variante.
///
/// Devuelve `true` si se agregó algo (para que la vitrina recargue si hace
/// falta).
Future<bool> agregarAlCarrito(BuildContext context, Recurso producto) async {
  final variante = await elegirVariante(context, producto, alCarrito: true);
  // Cancelado, sin variantes o única variante agotada: no se agrega.
  if (variante == null || (variante.numero('stock') ?? 0) < 1) return false;
  if (!context.mounted) return false;
  context.read<CarritoController>().agregar(producto, variante);
  return true;
}

/// Variantes de un producto del catálogo, ya como [Recurso] (vienen
/// embebidas en el JSON del listado de productos).
List<Recurso> variantesDe(Recurso producto) {
  final crudo = producto.datos['variantes'];
  if (crudo is! List) return const [];
  return [
    for (final item in crudo)
      if (item is Map)
        Recurso(
          id: (item['id'] as num?)?.toInt() ?? 0,
          datos: Map<String, Object?>.from(item),
        ),
  ];
}

/// Etiqueta de una variante en los desplegables: «Talla · Color (stock)».
///
/// El precio no va aquí: es único para el producto (Bs X del propio
/// producto) y ya se pinta en su tarjeta y en el selector.
String etiquetaVariante(Recurso variante) {
  final stock = (variante.numero('stock') ?? 0).toInt();
  return '${variante.texto('talla', vacio: '—')} · '
      '${variante.texto('color', vacio: '—')} ($stock)';
}

/// Hoja con una fila por variante; al elegir una, la devuelve.
///
/// No toca el carrito: lo decide quien la abrió (vitrina o caja). Las
/// variantes agotadas quedan visibles pero sin acción, como en la
/// tarjeta del catálogo.
class _SelectorVariante extends StatelessWidget {
  const _SelectorVariante({
    required this.producto,
    required this.variantes,
    required this.alCarrito,
  });

  final Recurso producto;
  final List<Recurso> variantes;

  /// `true` = la fila agrega al carrito (vitrina); `false` = solo se
  /// elige (caja). Cambia el icono y el texto flotante del atajo.
  final bool alCarrito;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              producto.texto('nombre', vacio: 'Prenda'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Elige la talla y el color',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: variantes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final variante = variantes[index];
                  final stock = (variante.numero('stock') ?? 0).floor();
                  final sinStock = stock < 1;
                  final hex = variante.texto('codigoHex', vacio: '');

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: hex.isEmpty
                          ? AppColors.trackGrey
                          : Color(
                              int.parse('FF${hex.substring(1)}', radix: 16),
                            ),
                      child: hex.isEmpty
                          ? const Icon(Icons.style_outlined, size: 14)
                          : null,
                    ),
                    title: Text(
                      '${variante.texto('talla', vacio: '—')} · '
                      '${variante.texto('color', vacio: '—')}',
                    ),
                    subtitle: Text(
                      sinStock
                          ? 'Agotado'
                          : 'Stock $stock · Bs '
                                '${(producto.numero('precioVenta') ?? 0).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: sinStock
                            ? AppColors.negativeRed
                            : AppColors.textSecondary,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: alCarrito
                          ? 'Agregar al carrito'
                          : 'Elegir esta talla y color',
                      icon: Icon(
                        alCarrito
                            ? Icons.add_shopping_cart_rounded
                            : Icons.check_rounded,
                        size: 20,
                        color: sinStock
                            ? AppColors.textSecondary
                            : AppColors.brandGreen,
                      ),
                      onPressed: sinStock
                          ? null
                          : () => Navigator.of(context).pop(variante),
                    ),
                    onTap: sinStock
                        ? null
                        : () => Navigator.of(context).pop(variante),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
