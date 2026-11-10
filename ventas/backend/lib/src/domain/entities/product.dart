/// Producto de la tienda (modelo puro de dominio).
///
/// Refleja la tabla `productos` sin exponer el SQL: los nombres en
/// camelCase son propios del dominio, la traducción snake_case -> camelCase
/// ocurre en `data/`.
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
    this.fechaVencimiento,
    required this.stock,
    this.stockMinimo,
    this.categoriaId,
    this.proveedorId,
    this.presentacionId,
    this.marcaId,
    this.garantiaMeses,
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

  /// Texto libre para explicar qué es o para qué sirve (columna
  /// `descripcion`): opcional, hasta 255 caracteres (`ensureDescripcion`).
  /// `null` = sin descripción.
  final String? descripcion;

  /// Unidad de venta (columna `unidad`): `UN`, `KG`, `GR`, `LT`...
  ///
  /// Es la misma unidad de [stock] y de la cantidad vendida, de modo que
  /// «1.450 KG» se lee igual en la ficha y en la factura.
  final String unidad;

  final double precioVenta;
  final double? precioCompra;

  /// Máximo en Bs que se puede rebajar **por unidad** (columna
  /// `precio_rebaja`): `null` = sin límite, `0` = no se puede rebajar.
  /// Nunca puede superar [precioVenta].
  final double? precioRebaja;

  /// Fecha de vencimiento del lote (columna `fecha_vencimiento`).
  final DateTime? fechaVencimiento;

  /// Existencias en [unidad] (columna `stock`): fraccionadas, así un
  /// producto pesado admite `12.750`.
  final double stock;

  /// Mínimo propio antes de marcar «stock bajo» (columna `stock_minimo`).
  /// `null` = usar el ajuste global `stockMinimo` del dashboard.
  final double? stockMinimo;

  /// Relaciones con categorías y presentaciones (`null` = sin clasificar).
  final int? categoriaId;
  final int? proveedorId;
  final int? presentacionId;

  /// Marca del catálogo (`null` = producto sin marca): solo texto, visible
  /// como columna de la tabla de productos, en el filtro, en la búsqueda y
  /// — únicamente en el Recibo 1 — en el recibo de la orden.
  final int? marcaId;

  /// Meses de garantía (`null` = sin garantía; 1..120, validado por
  /// `ensureGarantiaMeses`). Solo se muestra en la ficha de detalle del
  /// producto: no hay tabla de garantías, series ni reclamos.
  final int? garantiaMeses;

  /// Valor del enum `estado_producto`
  /// (`DISPONIBLE`, `AGOTADO`, `POR_VENCER`, `DESCONTINUADO`).
  final String estado;

  /// Guarda optimista (columna `version`): se incrementa en cada `UPDATE` y
  /// el cliente lo devuelve como `versionLeida` para que dos ediciones
  /// simultáneas no se pisen en silencio.
  final int version;

  /// Variantes de stock por color (tabla `producto_variantes`): vacía hasta
  /// que el repositorio las carga (`_conVariantes`); con la 022 todo
  /// producto tiene al menos la variante «Único».
  final List<VarianteProducto> variantes;

  bool get agotado => stock <= 0 || estado == 'AGOTADO';

  /// Copia con las variantes ya cargadas (`_conVariantes` del repositorio).
  Product conVariantes(List<VarianteProducto> valor) => Product(
    id: id,
    nombre: nombre,
    codigo: codigo,
    imagen: imagen,
    descripcion: descripcion,
    unidad: unidad,
    precioVenta: precioVenta,
    precioCompra: precioCompra,
    precioRebaja: precioRebaja,
    fechaVencimiento: fechaVencimiento,
    stock: stock,
    stockMinimo: stockMinimo,
    categoriaId: categoriaId,
    proveedorId: proveedorId,
    presentacionId: presentacionId,
    marcaId: marcaId,
    garantiaMeses: garantiaMeses,
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
    'fechaVencimiento': fechaVencimiento?.toIso8601String().split('T').first,
    'stock': stock,
    'stockMinimo': stockMinimo,
    'categoriaId': categoriaId,
    'proveedorId': proveedorId,
    'presentacionId': presentacionId,
    'marcaId': marcaId,
    'garantiaMeses': garantiaMeses,
    'estado': estado,
    'agotado': agotado,
    'version': version,
    'variantes': [for (final v in variantes) v.toJson()],
  };
}

/// Variante de producto: una fila de `producto_variantes` (stock por color).
///
/// El nombre del color es el **congelado** en el alta de la variante: si el
/// catálogo renombra «Rojo» a «Rojo Fuego», el histórico de ventas sigue
/// mostrando «Rojo». En los recibos no se imprime.
final class VarianteProducto {
  const VarianteProducto({
    required this.varianteId,
    required this.nombreColor,
    this.colorId,
    this.codigoHex,
    required this.stock,
    this.estado = 'ACTIVO',
  });

  final int varianteId;

  /// Nombre del color en el momento del alta (columna `nombre_color`).
  final String nombreColor;

  /// `null` = variante «Único/Única» (producto sin colores).
  final int? colorId;

  /// Muestra `#RRGGBB` del catálogo actual (no congelada; solo el chip de
  /// la UI). `null` sin muestra o sin color.
  final String? codigoHex;

  /// Existencias de esta variante (columna `stock`); la suma de las
  /// variantes vivas es el `stock` agregado del producto.
  final double stock;

  /// Valor del enum `estado_general`; `ELIMINADO` = variante retirada.
  final String estado;

  /// Se puede vender: la variante sigue viva **y** tiene existencias.
  bool get vendible => estado != 'ELIMINADO' && stock > 0;

  /// La UI la muestra en rojo «Agotado» cuando no queda stock.
  bool get agotada => stock <= 0;

  Map<String, Object?> toJson() => {
    'varianteId': varianteId,
    'colorId': colorId,
    'nombreColor': nombreColor,
    'codigoHex': codigoHex,
    'stock': stock,
    'estado': estado,
    'vendible': vendible,
    'agotada': agotada,
  };
}

/// Fila de entrada de `variantes` en el cuerpo de un producto:
/// `{colorId? | color?, cantidad}`.
///
/// La resolución del color (buscarlo en el catálogo por id o nombre sin
/// distinguir mayúsculas y autocrearlo si no existe) la hace el repositorio
/// dentro de su transacción, para que dos altas simultáneas no dupliquen.
final class VarianteEntrada {
  const VarianteEntrada({this.colorId, this.color, required this.cantidad});

  /// Color del catálogo por id (el formulario lo manda tras elegirlo).
  final int? colorId;

  /// Nombre del color a secas (se acepta en minúsculas o con mezcla).
  final String? color;

  /// Existencias iniciales de esta variante (≥ 0).
  final double cantidad;
}
