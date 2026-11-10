import '../../domain/entities/product.dart';
import '../../domain/entities/variante.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de PostgreSQL a las entidades [Product] y
/// [ProductoVariante].
///
/// Capa `data/`: es el único sitio donde se conoce la forma de las columnas
/// (`snake_case`, tipos `NUMERIC`, `DATE` y enums propios de PostgreSQL).
final class ProductModel {
  const ProductModel._(this.entity);

  final Product entity;

  factory ProductModel.fromRow(Map<String, Object?> row) => ProductModel._(
    Product(
      id: RowUtils.intValue(row['producto_id']),
      nombre: RowUtils.text(row['nombre_producto']),
      codigo: RowUtils.textOrNull(row['codigo']),
      imagen: RowUtils.textOrNull(row['imagen']),
      descripcion: RowUtils.textOrNull(row['descripcion']),
      unidad: RowUtils.text(row['unidad'], fallback: 'UN'),
      precioVenta: RowUtils.doubleValue(row['precio_venta']),
      precioCompra: RowUtils.doubleOrNull(row['precio_compra']),
      precioRebaja: RowUtils.doubleOrNull(row['precio_rebaja']),
      stock: RowUtils.doubleValue(row['stock']),
      stockMinimo: RowUtils.doubleOrNull(row['stock_minimo']),
      categoriaId: RowUtils.intOrNull(row['categoria_id']),
      marcaId: RowUtils.intOrNull(row['marca_id']),
      proveedorId: RowUtils.intOrNull(row['proveedor_id']),
      // Los enums propios de PostgreSQL se seleccionan con `::text` para que
      // lleguen como String (el driver no converte estos tipos).
      estado: RowUtils.text(row['estado'], fallback: 'DISPONIBLE'),
      version: RowUtils.intOrNull(row['version']) ?? 0,
    ),
  );
}

/// Fila de `producto_variantes` con los nombres de talla y color ya unidos
/// (`t.nombre AS talla`, `c.nombre AS color`, `c.codigo_hex`).
final class VarianteModel {
  const VarianteModel._();

  static ProductoVariante variante(Map<String, Object?> row) =>
      ProductoVariante(
        id: RowUtils.intValue(row['variante_id']),
        productoId: RowUtils.intValue(row['producto_id']),
        tallaId: RowUtils.intValue(row['talla_id']),
        colorId: RowUtils.intValue(row['color_id']),
        nombreTalla: RowUtils.text(row['talla']),
        nombreColor: RowUtils.text(row['color']),
        codigoHex: RowUtils.textOrNull(row['codigo_hex']),
        stock: RowUtils.doubleValue(row['stock']),
        codigo: RowUtils.textOrNull(row['codigo']),
        estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
      );
}
