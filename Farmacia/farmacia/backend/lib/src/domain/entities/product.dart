/// Producto de la farmacia (modelo puro de dominio).
///
/// Refleja la tabla `productos` sin exponer el SQL: los nombres en
/// camelCase son propios del dominio, la traducción snake_case -> camelCase
/// ocurre en `data/`.
final class Product {
  const Product({
    required this.id,
    required this.nombre,
    this.imagen,
    required this.precioVenta,
    this.precioCompra,
    this.precioRebaja,
    this.fechaVencimiento,
    required this.stock,
    this.categoriaId,
    this.proveedorId,
    this.presentacionId,
    required this.estado,
    this.version = 0,
  });

  final int id;
  final String nombre;

  /// URL o ruta de la imagen del producto (columna `imagen`).
  ///
  /// Se guarda la referencia, no los binarios: si se suben archivos, estos
  /// viven en un almacenamiento (disco, S3, CDN...) y aquí solo va la URL.
  final String? imagen;
  final double precioVenta;
  final double? precioCompra;

  /// Máximo en Bs que se puede rebajar **por unidad** (columna
  /// `precio_rebaja`): `null` = sin límite, `0` = no se puede rebajar.
  /// Nunca puede superar [precioVenta].
  final double? precioRebaja;

  /// Fecha de vencimiento del lote (columna `fecha_vencimiento`).
  final DateTime? fechaVencimiento;
  final int stock;

  /// Relaciones con categorías y presentaciones (`null` = sin clasificar).
  final int? categoriaId;
  final int? proveedorId;
  final int? presentacionId;

  /// Valor del enum `estado_producto`
  /// (`DISPONIBLE`, `AGOTADO`, `POR_VENCER`, `DESCONTINUADO`).
  final String estado;

  /// Guarda optimista (columna `version`): se incrementa en cada `UPDATE` y
  /// el cliente la devuelve como `versionLeida` para que dos ediciones
  /// simultáneas no se pisen en silencio.
  final int version;

  bool get agotado => stock <= 0 || estado == 'AGOTADO';

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'imagen': imagen,
    'precioVenta': precioVenta,
    'precioCompra': precioCompra,
    'precioRebaja': precioRebaja,
    'fechaVencimiento': fechaVencimiento?.toIso8601String().split('T').first,
    'stock': stock,
    'categoriaId': categoriaId,
    'proveedorId': proveedorId,
    'presentacionId': presentacionId,
    'estado': estado,
    'agotado': agotado,
    'version': version,
  };
}
