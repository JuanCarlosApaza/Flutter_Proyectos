/// Resolución de variantes al vender o cotizar (reglas de la 022).
///
/// Dominio puro: decide **qué** variante vende un ítem; la carga de las
/// variantes del producto la hace el repositorio de productos.
library;

import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
import '../entities/venta.dart';

/// Variantes del producto que siguen vivas (no `ELIMINADO`).
List<VarianteProducto> variantesVivas(Product producto) => [
  for (final v in producto.variantes)
    if (v.estado != 'ELIMINADO') v,
];

/// Resuelve la variante concreta de un ítem entre las variantes vivas del
/// producto, en este orden:
///
/// 1. `varianteId` explícito → esa variante si sigue viva;
/// 2. `colorId` o `color` (nombre, sin distinguir mayúsculas) → la variante
///    viva de ese color. **No se autocrea**: en una venta o cotización solo
///    se vende lo que ya existe (`variante_no_encontrada`);
/// 3. sin pista → si hay una única variante viva, esa; si hay varias o
///    ninguna, hay que elegirla (`variante_requerida`).
VarianteProducto resolverVarianteViva(Product producto, ItemOrden item) {
  final vivas = variantesVivas(producto);

  if (item.varianteId != null) {
    for (final v in vivas) {
      if (v.varianteId == item.varianteId) return v;
    }
    throw BadRequestException(
      'El producto "${producto.nombre}" no tiene la variante '
      '${item.varianteId}.',
      code: 'variante_no_encontrada',
    );
  }

  if (item.colorId != null) {
    for (final v in vivas) {
      if (v.colorId == item.colorId) return v;
    }
    throw BadRequestException(
      'El producto "${producto.nombre}" no se vende en el color ${item.colorId}.',
      code: 'variante_no_encontrada',
    );
  }

  final nombre = item.color?.trim() ?? '';
  if (nombre.isNotEmpty) {
    final minus = nombre.toLowerCase();
    for (final v in vivas) {
      if (v.nombreColor.toLowerCase() == minus) return v;
    }
    throw BadRequestException(
      'El producto "${producto.nombre}" no se vende en color "$nombre".',
      code: 'variante_no_encontrada',
    );
  }

  if (vivas.length == 1) return vivas.first;
  throw BadRequestException(
    vivas.isEmpty
        ? 'El producto "${producto.nombre}" no tiene variantes disponibles.'
        : 'El producto "${producto.nombre}" tiene ${vivas.length} variantes: '
              'indica cuál (varianteId o color).',
    code: 'variante_requerida',
  );
}
