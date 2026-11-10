/// Resolución de la variante (talla + color) de una línea de venta o
/// cotización: reglas compartidas por `Ordenes` y `Cotizaciones` para que
/// ambos flujos decidan lo mismo.
library;

import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
import '../entities/variante.dart';
import '../repositories/product_repository.dart';
import 'estados.dart';

/// Devuelve la variante concreta sobre la que operar para [varianteId].
///
/// * `varianteId != null` → se carga y se comprueba que pertenece a
///   [producto] y que no está oculta;
/// * `varianteId == null` → si el producto tiene **una sola** variante
///   visible se usa esa (los productos simples siguen funcionando sin
///   mandar talla); si tiene varias se pide `varianteId` con `400`.
Future<ProductoVariante> resolverVariante({
  required ProductRepository productos,
  required Product producto,
  required int? varianteId,
}) async {
  if (varianteId != null) {
    final variante = await productos.findVarianteById(varianteId);
    if (variante == null || variante.estado == estadoEliminado) {
      throw NotFoundException(
        'La variante $varianteId no existe.',
        code: 'variante_no_encontrada',
      );
    }
    if (variante.productoId != producto.id) {
      throw BadRequestException(
        'La variante $varianteId no pertenece al producto ${producto.id}.',
        code: 'variante_de_otro_producto',
      );
    }
    return variante;
  }

  final variantes = await productos.findVariantes(producto.id);
  final visibles = variantes.where((v) => v.estado != estadoEliminado);
  if (visibles.length == 1) return visibles.first;
  if (visibles.isEmpty) {
    throw ConflictException(
      'El producto "${producto.nombre}" no tiene variantes: añade al menos '
      'una talla y color antes de venderlo.',
      code: 'producto_sin_variantes',
    );
  }
  throw BadRequestException(
    'El producto "${producto.nombre}" tiene ${visibles.length} variantes: '
    'indica varianteId (talla + color) en el item.',
    code: 'variante_requerida',
  );
}
