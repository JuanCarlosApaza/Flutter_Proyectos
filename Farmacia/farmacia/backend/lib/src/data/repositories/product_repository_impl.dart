import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../database/database.dart';
import '../models/product_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [ProductRepository].
///
/// Todas las sentencias usan parámetros posicionales (`$1`, `$2`): nunca se
/// concatenan valores en el SQL (inyección SQL). Los nombres de tabla y
/// columna son constantes del código.
final class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columns =
      'producto_id, nombre_producto, imagen, precio_venta, precio_compra, '
      'precio_rebaja, fecha_vencimiento, stock, categoria_id, proveedor_id, '
      'presentacion_id, estado::text AS estado, version, fecha_creacion, '
      'fecha_actualizacion';

  @override
  Future<List<Product>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_producto');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('productos', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_columns FROM productos$where${busqueda.sql} '
      'ORDER BY nombre_producto LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map((row) => ProductModel.fromRow(row).entity).toList();
  }

  @override
  Future<int> count({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_producto');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('productos', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM productos$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Product?> findById(int id) async {
    final rows = await _db.query(
      'SELECT $_columns FROM productos WHERE producto_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : ProductModel.fromRow(rows.first).entity;
  }

  @override
  Future<Product> insert(Product datos) async {
    final rows = await _db.query(
      'INSERT INTO productos (nombre_producto, imagen, precio_venta, '
      'precio_compra, precio_rebaja, fecha_vencimiento, stock, categoria_id, '
      'proveedor_id, presentacion_id, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, '
      '\$11::estado_producto) RETURNING $_columns',
      [
        datos.nombre,
        datos.imagen,
        datos.precioVenta,
        datos.precioCompra,
        datos.precioRebaja,
        datos.fechaVencimiento,
        datos.stock,
        datos.categoriaId,
        datos.proveedorId,
        datos.presentacionId,
        datos.estado,
      ],
    );
    return ProductModel.fromRow(rows.first).entity;
  }

  @override
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
  }) async {
    final cambios = <String, Object?>{
      if (campos.contains('nombre')) 'nombre_producto': datos.nombre,
      if (campos.contains('imagen')) 'imagen': datos.imagen,
      if (campos.contains('precioVenta')) 'precio_venta': datos.precioVenta,
      if (campos.contains('precioCompra')) 'precio_compra': datos.precioCompra,
      if (campos.contains('precioRebaja')) 'precio_rebaja': datos.precioRebaja,
      if (campos.contains('fechaVencimiento'))
        'fecha_vencimiento': datos.fechaVencimiento,
      if (campos.contains('stock')) 'stock': datos.stock,
      if (campos.contains('categoriaId')) 'categoria_id': datos.categoriaId,
      if (campos.contains('proveedorId')) 'proveedor_id': datos.proveedorId,
      if (campos.contains('presentacionId'))
        'presentacion_id': datos.presentacionId,
      if (campos.contains('estado')) 'estado': datos.estado,
    };
    final upd = updateSet(cambios, casts: const {'estado': 'estado_producto'});
    // `version` crece en cada escritura; con `versionEsperado` el `WHERE`
    // falla si otra persona editó primero (guarda optimista).
    final idParam = upd.params.length + 1;
    final rows = await _db.query(
      'UPDATE productos SET ${upd.set}, version = version + 1 '
      'WHERE producto_id = \$$idParam'
      '${versionEsperado == null ? '' : ' AND version = \$${idParam + 1}'} '
      'RETURNING $_columns',
      [...upd.params, id, ?versionEsperado],
    );
    if (rows.isEmpty) {
      // ¿No existe o la versión quedó vieja? Un SELECT distingue los dos
      // casos para devolver el código correcto.
      final existe = await _db.query(
        'SELECT 1 FROM productos WHERE producto_id = \$1',
        [id],
      );
      if (existe.isEmpty) {
        throw const NotFoundException(
          'El producto no existe.',
          code: 'producto_no_encontrado',
        );
      }
      throw const ConflictException(
        'El producto fue modificado por otra persona mientras lo editabas: '
        'recarga y vuelve a intentarlo.',
        code: 'producto_desactualizado',
      );
    }
    return ProductModel.fromRow(rows.first).entity;
  }

  @override
  Future<bool> delete(int id) => ocultarRegistro(
    _db,
    tabla: 'productos',
    pk: 'producto_id',
    enumTipo: 'estado_producto',
    id: id,
  );
}
