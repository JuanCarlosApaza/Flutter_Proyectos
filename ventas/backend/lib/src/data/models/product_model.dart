import '../../domain/entities/product.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta una fila de PostgreSQL a la entidad [Product].
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
      fechaVencimiento: RowUtils.dateOrNull(row['fecha_vencimiento']),
      stock: RowUtils.doubleValue(row['stock']),
      stockMinimo: RowUtils.doubleOrNull(row['stock_minimo']),
      categoriaId: RowUtils.intOrNull(row['categoria_id']),
      proveedorId: RowUtils.intOrNull(row['proveedor_id']),
      presentacionId: RowUtils.intOrNull(row['presentacion_id']),
      marcaId: RowUtils.intOrNull(row['marca_id']),
      garantiaMeses: RowUtils.intOrNull(row['garantia_meses']),
      // Los enums propios de PostgreSQL se seleccionan con `::text` para que
      // lleguen como String (el driver no conoce estos tipos).
      estado: RowUtils.text(row['estado'], fallback: 'DISPONIBLE'),
      version: RowUtils.intOrNull(row['version']) ?? 0,
    ),
  );
}
