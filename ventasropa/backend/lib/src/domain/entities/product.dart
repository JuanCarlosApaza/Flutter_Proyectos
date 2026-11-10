/// Producto de la tienda (modelo puro de dominio).
///
/// Refleja la tabla `productos` sin exponer el SQL: los nombres en
/// camelCase son propios de la BD, la traducción snake_case -> camelCase
/// ocurre en `data/`.
library;

import 'variante.dart';

final class Product {
  const Product({
    required this.id,
    required this.nombre,
    this.codigo,
    this.imagen,
    this.descripcion,
    this.unidad = 'UN',
    required this.precioVenta,
    this.precioCompra,
    this.precioRebaja,
    required this.stock,
    this.stockMinimo,
    this.categoriaId,
    this.marcaId,
    this.proveedorId,
    required this.estado,
    this.version = 0,
    this.variantes = const [],
  });

  final int id;
  final String nombre;

  /// Código interno o de barras (columna `codigo`).
  ///
  /// `null` = producto antiguo sin código; la BD lo deja repetir en `NULL`
  /// porque un `UNIQUE` no cubre los nulos.
  final String? codigo;

  /// URL o ruta de la imagen del producto (columna `imagen`).
  ///
  /// Se guarda la referencia, no los binarios: si se suben archivos, estos
  /// viven en un almacenamiento (disco, S3, CDN...) y aquí solo va la URL.
  final String? imagen;

  /// Descripción libre de la ficha (columna `descripcion`, migración 023):
  /// notas, materiales, cuidados, temporada... Opcional; `null` = sin
  /// descripción.
  final String? descripcion;

  /// Unidad de venta (columna `unidad`): en una tienda de ropa siempre `UN`.
  final String unidad;

  final double precioVenta;
  final double? precioCompra;

  /// Máximo en Bs que se puede rebajar **por unidad** (columna
  /// `precio_rebaja`): `null` = sin límite, `0` = no se puede rebajar.
  /// Nunca puede superar [precioVenta].
  final double? precioRebaja;

  /// Existencias totales (columna `stock`): **agregado** de las variantes
  /// visibles de [variantes]; el stock real vive en cada variante
  /// (prenda + talla + color).
  final double stock;

  /// Mínimo propio antes de marcar «stock bajo» (columna `stock_minimo`).
  /// `null` = usar el ajuste global `stockMinimo` del dashboard.
  final double? stockMinimo;

  /// Relaciones con categorías, marcas y proveedores (`null` = sin clasificar;
  /// la marca es opcional: una prenda puede no tenerla).
  final int? categoriaId;
  final int? marcaId;
  final int? proveedorId;

  /// Valor del enum `estado_producto`
  /// (`DISPONIBLE`, `AGOTADO`, `DESCONTINUADO`, `ELIMINADO`).
  final String estado;

  /// Guarda optimista (columna `version`): se incrementa en cada `UPDATE` y
  /// el cliente lo devuelve como `versionLeida` para que dos ediciones
  /// simultáneas no se pisen en silencio.
  final int version;

  /// Variantes con stock propio (talla + color). Se rellenan al leer
  /// (`findAll`/`findById`); vacío en un producto recién construido.
  final List<ProductoVariante> variantes;

  bool get agotado => stock <= 0 || estado == 'AGOTADO';

  /// Copia con las variantes adjuntas (se rellenan al leer).
  Product conVariantes(List<ProductoVariante> valor) => Product(
    id: id,
    nombre: nombre,
    codigo: codigo,
    imagen: imagen,
    descripcion: descripcion,
    unidad: unidad,
    precioVenta: precioVenta,
    precioCompra: precioCompra,
    precioRebaja: precioRebaja,
    stock: stock,
    stockMinimo: stockMinimo,
    categoriaId: categoriaId,
    marcaId: marcaId,
    proveedorId: proveedorId,
    estado: estado,
    version: version,
    variantes: valor,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'codigo': codigo,
    'imagen': imagen,
    'descripcion': descripcion,
    'unidad': unidad,
    'precioVenta': precioVenta,
    'precioCompra': precioCompra,
    'precioRebaja': precioRebaja,
    'stock': stock,
    'stockMinimo': stockMinimo,
    'categoriaId': categoriaId,
    'marcaId': marcaId,
    'proveedorId': proveedorId,
    'estado': estado,
    'agotado': agotado,
    'version': version,
    'variantes': variantes.map((v) => v.toJson()).toList(),
  };
}
