import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/variante.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/rules/estados.dart';
import '../../domain/rules/validaciones.dart';
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
///
/// El stock real vive en `producto_variantes` (prenda + talla + color);
/// `productos.stock` es su **agregado** y se recalcula en la misma
/// transacción que cualquier cambio de variante.
final class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columns =
      'producto_id, nombre_producto, codigo, imagen, descripcion, unidad, '
      'precio_venta, precio_compra, '
      'precio_rebaja, stock, stock_minimo, '
      'categoria_id, marca_id, proveedor_id, estado::text AS estado, version, '
      'fecha_creacion, fecha_actualizacion';

  static const String _variantesSelect =
      'SELECT v.variante_id, v.producto_id, v.talla_id, v.color_id, '
      't.nombre AS talla, c.nombre AS color, c.codigo_hex, '
      'v.stock, v.codigo, v.estado::text AS estado '
      'FROM producto_variantes v '
      'JOIN tallas t ON t.talla_id = v.talla_id '
      'JOIN colores c ON c.color_id = v.color_id';

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
    final productos = rows
        .map((row) => ProductModel.fromRow(row).entity)
        .toList();
    return _conVariantes(productos);
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
    if (rows.isEmpty) return null;
    final producto = ProductModel.fromRow(rows.first).entity;
    final variantes = await findVariantes(id);
    return producto.conVariantes(variantes);
  }

  @override
  Future<Product> insert(
    Product datos, {
    List<DatoVariante> variantes = const [],
  }) async {
    // El stock escrito es el agregado de las variantes que se crean.
    final agregado = variantes.isEmpty
        ? datos.stock
        : variantes.fold<double>(0, (suma, v) => suma + v.stock);

    var productoId = 0;
    await _db.runInTransaction((session) async {
      final rows = await session.query(
        'INSERT INTO productos (nombre_producto, codigo, imagen, descripcion, '
        'unidad, precio_venta, precio_compra, precio_rebaja, stock, '
        'stock_minimo, categoria_id, marca_id, proveedor_id, estado) '
        'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, '
        '\$11, \$12, \$13, \$14::estado_producto) RETURNING $_columns',
        [
          datos.nombre,
          datos.codigo,
          datos.imagen,
          datos.descripcion,
          datos.unidad,
          datos.precioVenta,
          datos.precioCompra,
          datos.precioRebaja,
          agregado,
          datos.stockMinimo,
          datos.categoriaId,
          datos.marcaId,
          datos.proveedorId,
          datos.estado,
        ],
      );
      productoId = ProductModel.fromRow(rows.first).entity.id;

      if (variantes.isEmpty) {
        // Producto «sin talla»: variante única para que sea vendible ya.
        await _insertarVariante(
          session,
          productoId: productoId,
          tallaId: await _asegurarCatalogo(
            session,
            'tallas',
            'talla_id',
            'nombre',
            'Única',
          ),
          colorId: await _asegurarCatalogo(
            session,
            'colores',
            'color_id',
            'nombre',
            'Único',
          ),
          stock: datos.stock,
          codigo: null,
        );
      } else {
        for (final v in variantes) {
          final resuelto = await _idsDeVariante(session, v);
          await _insertarVariante(
            session,
            productoId: productoId,
            tallaId: resuelto.tallaId,
            colorId: resuelto.colorId,
            stock: v.stock,
            codigo: v.codigo,
          );
        }
      }
    });

    final creado = await findById(productoId);
    if (creado == null) {
      throw const NotFoundException(
        'El producto no existe.',
        code: 'producto_no_encontrado',
      );
    }
    return creado;
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
      if (campos.contains('codigo')) 'codigo': datos.codigo,
      if (campos.contains('imagen')) 'imagen': datos.imagen,
      if (campos.contains('descripcion')) 'descripcion': datos.descripcion,
      if (campos.contains('unidad')) 'unidad': datos.unidad,
      if (campos.contains('precioVenta')) 'precio_venta': datos.precioVenta,
      if (campos.contains('precioCompra')) 'precio_compra': datos.precioCompra,
      if (campos.contains('precioRebaja')) 'precio_rebaja': datos.precioRebaja,
      if (campos.contains('stockMinimo')) 'stock_minimo': datos.stockMinimo,
      if (campos.contains('categoriaId')) 'categoria_id': datos.categoriaId,
      if (campos.contains('marcaId')) 'marca_id': datos.marcaId,
      if (campos.contains('proveedorId')) 'proveedor_id': datos.proveedorId,
      if (campos.contains('estado')) 'estado': datos.estado,
    };
    final upd = updateSet(cambios, casts: const {'estado': 'estado_producto'});
    // `version` crece en cada escritura; con `versionEsperado` el `WHERE`
    // falla si otra persona editó primero (guarda optimista).
    final idParam = upd.params.length + 1;
    final sql =
        'UPDATE productos SET ${upd.set}, version = version + 1 '
        'WHERE producto_id = \$$idParam'
        '${versionEsperado == null ? '' : ' AND version = \$${idParam + 1}'} '
        'RETURNING $_columns';
    final params = [...upd.params, id, ?versionEsperado];

    final resultado = await _db.query(sql, params);
    if (resultado.isEmpty) {
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
    final producto = ProductModel.fromRow(resultado.first).entity;
    return producto.conVariantes(await findVariantes(id));
  }

  @override
  Future<bool> delete(int id) => ocultarRegistro(
    _db,
    tabla: 'productos',
    pk: 'producto_id',
    enumTipo: 'estado_producto',
    id: id,
  );

  // --- Variantes (talla + color: el stock real) -----------------------------

  @override
  Future<List<ProductoVariante>> findVariantes(int productoId) async {
    final rows = await _db.query(
      '$_variantesSelect WHERE v.producto_id = \$1 '
      'ORDER BY t.orden, t.nombre, c.nombre',
      [productoId],
    );
    return rows.map(VarianteModel.variante).toList();
  }

  @override
  Future<ProductoVariante?> findVarianteById(int id) async {
    final rows = await _db.query(
      '$_variantesSelect WHERE v.variante_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : VarianteModel.variante(rows.first);
  }

  @override
  Future<ProductoVariante> insertVariante(
    int productoId,
    DatoVariante datos,
  ) async {
    // Ids resueltos **dentro** de la transacción: una talla escrita a mano
    // se busca en el catálogo y se crea si no existe, todo atómico.
    late final int tallaId;
    late final int colorId;
    await _db.runInTransaction((session) async {
      await _asegurarProducto(session, productoId);
      final resuelto = await _idsDeVariante(session, datos);
      tallaId = resuelto.tallaId;
      colorId = resuelto.colorId;
      await _insertarVariante(
        session,
        productoId: productoId,
        tallaId: tallaId,
        colorId: colorId,
        stock: datos.stock,
        codigo: datos.codigo,
      );
      await _recalcularStockProducto(session, productoId);
    });
    return _buscarRecienCreada(productoId, tallaId, colorId);
  }

  @override
  Future<ProductoVariante> updateVariante(
    int id,
    DatoVariante datos,
    Set<String> campos,
  ) async {
    await _db.runInTransaction((session) async {
      final previo = await session.query(
        'SELECT producto_id, stock FROM producto_variantes '
        'WHERE variante_id = \$1',
        [id],
      );
      if (previo.isEmpty) {
        throw const NotFoundException(
          'La variante no existe.',
          code: 'variante_no_encontrada',
        );
      }
      final productoId = RowUtils.intValue(previo.first['producto_id']);
      final stockAntes = RowUtils.doubleValue(previo.first['stock']);

      final cambios = <String, Object?>{
        if (campos.contains('tallaId')) 'talla_id': datos.tallaId,
        if (campos.contains('colorId')) 'color_id': datos.colorId,
        if (campos.contains('stock')) 'stock': datos.stock,
        if (campos.contains('codigo')) 'codigo': datos.codigo,
      };
      final upd = updateSet(cambios);
      await session.query(
        'UPDATE producto_variantes SET ${upd.set} WHERE variante_id = '
        '\$${upd.params.length + 1}',
        [...upd.params, id],
      );

      if (campos.contains('stock')) {
        final stockDespues = datos.stock;
        final delta = stockDespues - stockAntes;
        if (delta.abs() > 0.0005) {
          await session.query(
            'INSERT INTO movimientos_stock '
            '(producto_id, variante_id, cantidad, motivo, stock_resultante, '
            'notas) VALUES (\$1, \$2, \$3, \'AJUSTE\', \$4, \$5)',
            [
              productoId,
              id,
              delta,
              stockDespues,
              'Ajuste manual de existencias (variante)',
            ],
          );
        }
      }
      await _recalcularStockProducto(session, productoId);
    });

    final variante = await findVarianteById(id);
    if (variante == null) {
      throw const NotFoundException(
        'La variante no existe.',
        code: 'variante_no_encontrada',
      );
    }
    return variante;
  }

  @override
  Future<bool> deleteVariante(int id) async {
    var encontrada = false;
    await _db.runInTransaction((session) async {
      final previo = await session.query(
        'SELECT producto_id, stock, estado FROM producto_variantes '
        'WHERE variante_id = \$1',
        [id],
      );
      if (previo.isEmpty) return;
      encontrada = true;
      final productoId = RowUtils.intValue(previo.first['producto_id']);
      final stock = RowUtils.doubleValue(previo.first['stock']);
      if (stock > 0.0005) {
        throw const ConflictException(
          'La variante todavía tiene stock: pon su stock a 0 antes de '
          'eliminarla.',
          code: 'variante_con_stock',
        );
      }
      await session.query(
        'UPDATE producto_variantes SET estado = \'ELIMINADO\' '
        'WHERE variante_id = \$1',
        [id],
      );
      await _recalcularStockProducto(session, productoId);
    });
    return encontrada;
  }

  // --- Auxiliares -------------------------------------------------------------

  /// Adjunta las variantes de todos los productos de la página (una sola
  /// consulta `IN`, sin N+1).
  Future<List<Product>> _conVariantes(List<Product> productos) async {
    if (productos.isEmpty) return productos;
    final ids = productos.map((p) => p.id).toList();
    final placeholders = [for (var i = 1; i <= ids.length; i++) '\$$i']
        .join(', ');
    final rows = await _db.query(
      '$_variantesSelect WHERE v.producto_id IN ($placeholders) '
      'ORDER BY t.orden, t.nombre, c.nombre',
      ids,
    );
    final porProducto = <int, List<ProductoVariante>>{};
    for (final row in rows) {
      final variante = VarianteModel.variante(row);
      (porProducto[variante.productoId] ??= []).add(variante);
    }
    return [
      for (final p in productos) p.conVariantes(porProducto[p.id] ?? const []),
    ];
  }

  /// Crea una variante dentro de la transacción abierta, validando que la
  /// talla y el color existan y no estén ocultos, que no se repita la
  /// combinación y registrando el stock inicial en el kardex.
  Future<void> _insertarVariante(
    DatabaseSession session, {
    required int productoId,
    required int tallaId,
    required int colorId,
    required double stock,
    String? codigo,
  }) async {
    final talla = await session.query(
      'SELECT 1 FROM tallas WHERE talla_id = \$1 AND estado <> \'ELIMINADO\'',
      [tallaId],
    );
    final color = await session.query(
      'SELECT 1 FROM colores WHERE color_id = \$1 AND estado <> \'ELIMINADO\'',
      [colorId],
    );
    if (talla.isEmpty || color.isEmpty) {
      throw BadRequestException(
        'La talla $tallaId o el color $colorId no existe (o está oculto).',
        code: 'variante_invalida',
      );
    }
    final filas = await session.query(
      'INSERT INTO producto_variantes '
      '(producto_id, talla_id, color_id, stock, codigo) '
      'VALUES (\$1, \$2, \$3, \$4, \$5) '
      'ON CONFLICT (producto_id, talla_id, color_id) DO NOTHING '
      'RETURNING variante_id',
      [productoId, tallaId, colorId, stock, codigo],
    );
    if (filas.isEmpty) {
      throw const ConflictException(
        'Esa combinación de talla y color ya existe en el producto.',
        code: 'variante_duplicada',
      );
    }
    final varianteId = RowUtils.intValue(filas.first['variante_id']);
    if (stock.abs() > 0.0005) {
      await session.query(
        'INSERT INTO movimientos_stock '
        '(producto_id, variante_id, cantidad, motivo, stock_resultante, '
        'notas) VALUES (\$1, \$2, \$3, \'INICIAL\', \$4, \$5)',
        [productoId, varianteId, stock, stock, 'Stock inicial de la variante'],
      );
    }
  }

  /// Recalcula `productos.stock` como suma de sus variantes visibles y
  /// ajusta el estado. Definición única en [recalcularStockProducto].
  Future<void> _recalcularStockProducto(
    DatabaseSession session,
    int productoId,
  ) => session.query(recalcularStockProducto, [productoId]);

  Future<void> _asegurarProducto(
    DatabaseSession session,
    int productoId,
  ) async {
    final filas = await session.query(
      'SELECT 1 FROM productos WHERE producto_id = \$1',
      [productoId],
    );
    if (filas.isEmpty) {
      throw const NotFoundException(
        'El producto no existe.',
        code: 'producto_no_encontrado',
      );
    }
  }

  /// Devuelve el id de la variante recién creada (búsqueda por combinación).
  Future<ProductoVariante> _buscarRecienCreada(
    int productoId,
    int tallaId,
    int colorId,
  ) async {
    final rows = await _db.query(
      '$_variantesSelect WHERE v.producto_id = \$1 AND v.talla_id = \$2 '
      'AND v.color_id = \$3',
      [productoId, tallaId, colorId],
    );
    if (rows.isEmpty) {
      throw const NotFoundException(
        'La variante no existe.',
        code: 'variante_no_encontrada',
      );
    }
    return VarianteModel.variante(rows.first);
  }

  /// Ids de talla y color de una variante: los propios cuando vienen, y los
  /// que resuelve (buscando y creando el nombre) cuando llegan escritos a
  /// mano. Todo dentro de la transacción que lo llama.
  Future<({int tallaId, int colorId})> _idsDeVariante(
    DatabaseSession session,
    DatoVariante datos,
  ) async => (
    tallaId: await _idDeCatalogo(
      session,
      id: datos.tallaId,
      nombre: datos.talla,
      tabla: 'tallas',
      pk: 'talla_id',
      etiqueta: 'talla',
    ),
    colorId: await _idDeCatalogo(
      session,
      id: datos.colorId,
      nombre: datos.color,
      tabla: 'colores',
      pk: 'color_id',
      etiqueta: 'color',
    ),
  );

  /// Id de un catálogo para una variante: `id` si trae uno válido, o el del
  /// registro con ese `nombre` (creándolo si no existía).
  Future<int> _idDeCatalogo(
    DatabaseSession session, {
    required int id,
    required String? nombre,
    required String tabla,
    required String pk,
    required String etiqueta,
  }) async {
    if (id > 0) return id;
    final texto = nombre?.trim() ?? '';
    if (texto.isEmpty) {
      throw BadRequestException(
        'Cada variante necesita su $etiqueta: indica el id o el nombre.',
        code: 'fields_required',
      );
    }
    // Las tallas escritas a mano en las variantes pasan por la misma regla
    // que el catálogo: solo formatos de talla (S, M, 38, Única...).
    return _asegurarCatalogo(
      session,
      tabla,
      pk,
      'nombre',
      tabla == 'tallas' ? ensureNombreTalla(texto) : texto,
    );
  }

  /// Busca por nombre una fila de catálogo (`tallas`/`colores`) y la crea si
  /// no existe (así el nombre que escribe el usuario al crear un producto
  /// acaba en el catálogo, sin semillas previas).
  ///
  /// La comparación primero es exacta y luego sin distinguir mayúsculas:
  /// quien escriba «s» reutiliza la «S» en vez de duplicarla.
  Future<int> _asegurarCatalogo(
    DatabaseSession session,
    String tabla,
    String pk,
    String columnaNombre,
    String nombre,
  ) async {
    var previo = await session.query(
      'SELECT $pk, estado FROM $tabla WHERE $columnaNombre = \$1',
      [nombre],
    );
    if (previo.isEmpty) {
      previo = await session.query(
        'SELECT $pk, estado FROM $tabla '
        'WHERE LOWER($columnaNombre) = LOWER(\$1)',
        [nombre],
      );
    }
    if (previo.isEmpty) {
      final filas = await session.query(
        'INSERT INTO $tabla ($columnaNombre) VALUES (\$1) '
        'ON CONFLICT ($columnaNombre) DO NOTHING '
        'RETURNING $pk',
        [nombre],
      );
      if (filas.isNotEmpty) return RowUtils.intValue(filas.first[pk]);
      final otra = await session.query(
        'SELECT $pk FROM $tabla WHERE $columnaNombre = \$1',
        [nombre],
      );
      return RowUtils.intValue(otra.first[pk]);
    }
    final id = RowUtils.intValue(previo.first[pk]);
    if (RowUtils.text(previo.first['estado']) == estadoEliminado) {
      await session.query(
        'UPDATE $tabla SET estado = \'ACTIVO\' WHERE $pk = \$1',
        [id],
      );
    }
    return id;
  }
}
