import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
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
/// Las variantes de stock (migración 022) se leen y se escriben aquí, dentro
/// de la misma transacción que el producto: el `stock` agregado del producto
/// es siempre la suma de sus variantes vivas.
final class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columns =
      'producto_id, nombre_producto, codigo, imagen, descripcion, unidad, '
      'precio_venta, precio_compra, '
      'precio_rebaja, fecha_vencimiento, stock, stock_minimo, '
      'categoria_id, proveedor_id, '
      'presentacion_id, marca_id, garantia_meses, '
      'estado::text AS estado, version, fecha_creacion, '
      'fecha_actualizacion';

  static const String _variantesColumns =
      'v.producto_id, v.variante_id, v.color_id, v.nombre_color, '
      'c.codigo_hex, v.stock, v.estado::text AS estado';

  @override
  Future<List<Product>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
    int? marcaId,
  }) async {
    final where = whereEstado(estado, 'estado_producto');
    final params = <Object?>[?estado];
    final busqueda = _busquedaProductos(q, params.length + 1);
    params.addAll(busqueda.params);
    final filtroMarca = _filtroMarca(marcaId, params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_columns FROM productos$where${busqueda.sql}$filtroMarca '
      'ORDER BY nombre_producto LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return _conVariantes(
      rows.map((row) => ProductModel.fromRow(row).entity).toList(),
    );
  }

  @override
  Future<int> count({String? estado, String? q, int? marcaId}) async {
    final where = whereEstado(estado, 'estado_producto');
    final params = <Object?>[?estado];
    final busqueda = _busquedaProductos(q, params.length + 1);
    params.addAll(busqueda.params);
    final filtroMarca = _filtroMarca(marcaId, params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM productos'
      '$where${busqueda.sql}$filtroMarca',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  /// `?q=` sobre la fila del producto **y** el nombre de su marca: la marca
  /// no vive en `productos`, así que entra por subconsulta (una marca
  /// encuentra a sus productos en la búsqueda libre).
  static ({String sql, List<Object?> params}) _busquedaProductos(
    String? q,
    int param,
  ) => andBusquedaConRelacion(
    'productos',
    q,
    param,
    'SELECT m.nombre FROM marcas m WHERE m.marca_id = productos.marca_id',
  );

  /// Filtro `?marcaId=` del desplegable «Marca» de la tabla de productos:
  /// añade el parámetro a [params] (su posición = el `$n` devuelto) y la
  /// cláusula `AND`, o SQL vacío si no se filtra.
  static String _filtroMarca(int? marcaId, List<Object?> params) {
    if (marcaId == null) return '';
    params.add(marcaId);
    return ' AND marca_id = \$${params.length}';
  }

  @override
  Future<Product?> findById(int id) async {
    final rows = await _db.query(
      'SELECT $_columns FROM productos WHERE producto_id = \$1',
      [id],
    );
    if (rows.isEmpty) return null;
    final productos = await _conVariantes([
      ProductModel.fromRow(rows.first).entity,
    ]);
    return productos.first;
  }

  /// Duplicados de la importación masiva: `codigo` si trae uno (índice
  /// único), si no el nombre **exacto** con su categoría y presentación.
  /// `lower()` existe en PostgreSQL y en SQLite (el `ilike` del helper es
  /// solo para PostgreSQL).
  @override
  Future<bool> existe({
    String? codigo,
    String? nombre,
    int? categoriaId,
    int? presentacionId,
  }) async {
    final limpioCodigo = (codigo ?? '').trim();
    if (limpioCodigo.isNotEmpty) {
      final rows = await _db.query(
        'SELECT 1 FROM productos WHERE codigo = \$1 '
        "AND estado <> 'ELIMINADO' LIMIT 1",
        [limpioCodigo],
      );
      return rows.isNotEmpty;
    }
    final nombreLimpio = (nombre ?? '').trim();
    if (nombreLimpio.isEmpty) return false;
    final rows = await _db.query(
      'SELECT 1 FROM productos '
      'WHERE lower(nombre_producto) = lower(\$1) '
      'AND COALESCE(categoria_id, -1) = COALESCE(\$2, -1) '
      'AND COALESCE(presentacion_id, -1) = COALESCE(\$3, -1) '
      "AND estado <> 'ELIMINADO' LIMIT 1",
      [nombreLimpio, categoriaId, presentacionId],
    );
    return rows.isNotEmpty;
  }

  /// Adjunta las variantes **vivas** (una sola query para toda la página) a
  /// los productos: una fila `ELIMINADO` es una variante retirada y no se
  /// muestra ni se puede vender (la historia de ventas conserva su nombre
  /// congelado vía JOIN). La muestra `codigo_hex` viene del catálogo actual:
  /// solo el nombre del color está congelado en la fila de la variante.
  Future<List<Product>> _conVariantes(List<Product> productos) async {
    if (productos.isEmpty) return productos;
    final ids = productos.map((p) => p.id).toList();
    final rows = await _db.query(
      'SELECT $_variantesColumns FROM producto_variantes v '
      'LEFT JOIN colores c ON c.color_id = v.color_id '
      'WHERE v.producto_id = ANY(\$1) AND v.estado <> \'ELIMINADO\' '
      'ORDER BY v.producto_id, v.variante_id',
      [ids],
    );
    final porProducto = <int, List<VarianteProducto>>{};
    for (final row in rows) {
      final productoId = RowUtils.intValue(row['producto_id']);
      (porProducto[productoId] ??= []).add(_varianteDesdeRow(row));
    }
    return [
      for (final producto in productos)
        producto.conVariantes(porProducto[producto.id] ?? const []),
    ];
  }

  static VarianteProducto _varianteDesdeRow(Map<String, Object?> row) =>
      VarianteProducto(
        varianteId: RowUtils.intValue(row['variante_id']),
        nombreColor: RowUtils.text(row['nombre_color'], fallback: 'Único'),
        colorId: RowUtils.intOrNull(row['color_id']),
        codigoHex: RowUtils.textOrNull(row['codigo_hex']),
        stock: RowUtils.doubleValue(row['stock']),
        estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
      );

  @override
  Future<Product> insert(
    Product datos, {
    List<VarianteEntrada> variantes = const [],
  }) async {
    int? creadoId;
    await _db.runInTransaction((session) async {
      final colores = await _resolverColores(session, variantes);

      // Con filas de variantes, el stock agregado es su suma (el stock del
      // cuerpo se ignora); sin filas, nace la variante «Único» con el stock
      // del cuerpo.
      final stockFinal = colores.isEmpty
          ? datos.stock
          : cantidad(_sumaCantidades(variantes));

      final rows = await session.query(
        'INSERT INTO productos (nombre_producto, codigo, imagen, descripcion, '
        'unidad, precio_venta, '
        'precio_compra, precio_rebaja, fecha_vencimiento, stock, stock_minimo, '
        'categoria_id, proveedor_id, presentacion_id, marca_id, '
        'garantia_meses, estado) '
        'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, '
        '\$11, \$12, \$13, \$14, \$15, \$16, \$17::estado_producto) '
        'RETURNING $_columns',
        [
          datos.nombre,
          datos.codigo,
          datos.imagen,
          datos.descripcion,
          datos.unidad,
          datos.precioVenta,
          datos.precioCompra,
          datos.precioRebaja,
          datos.fechaVencimiento,
          stockFinal,
          datos.stockMinimo,
          datos.categoriaId,
          datos.proveedorId,
          datos.presentacionId,
          datos.marcaId,
          datos.garantiaMeses,
          datos.estado,
        ],
      );
      final productoId = RowUtils.intValue(rows.first['producto_id']);

      if (colores.isEmpty) {
        await session.query(
          'INSERT INTO producto_variantes (producto_id, color_id, '
          'nombre_color, stock) VALUES (\$1, NULL, \'Único\', \$2)',
          [productoId, stockFinal],
        );
      } else {
        for (var i = 0; i < variantes.length; i++) {
          await session.query(
            'INSERT INTO producto_variantes (producto_id, color_id, '
            'nombre_color, stock) VALUES (\$1, \$2, \$3, \$4)',
            [
              productoId,
              colores[i].colorId,
              colores[i].nombre,
              variantes[i].cantidad,
            ],
          );
        }
      }
      creadoId = productoId;
    });

    final guardado = await findById(creadoId!);
    return guardado!;
  }

  @override
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
    List<VarianteEntrada>? variantes,
  }) async {
    final filas = <Map<String, Object?>>[];
    await _db.runInTransaction((session) async {
      // Stock anterior: es la base del movimiento de kardex y del caso
      // «lista vacía sin stock en el cuerpo» (se conserva el vigente).
      final previo = await session.query(
        'SELECT stock FROM productos WHERE producto_id = \$1',
        [id],
      );
      final antes = previo.isEmpty
          ? null
          : RowUtils.doubleOrNull(previo.first['stock']);

      // Colores resueltos (autocreando los que falten) antes de escribir:
      // cualquier error se tira para atrás con la transacción.
      List<({int colorId, String nombre})> colores = const [];
      if (variantes != null && variantes.isNotEmpty) {
        colores = await _resolverColores(session, variantes);
      }

      if (variantes == null && campos.contains('stock')) {
        await _asegurarStockPorVarianteValido(session, id);
      }

      final cambios = <String, Object?>{
        if (campos.contains('nombre')) 'nombre_producto': datos.nombre,
        if (campos.contains('codigo')) 'codigo': datos.codigo,
        if (campos.contains('imagen')) 'imagen': datos.imagen,
        if (campos.contains('descripcion')) 'descripcion': datos.descripcion,
        if (campos.contains('unidad')) 'unidad': datos.unidad,
        if (campos.contains('precioVenta')) 'precio_venta': datos.precioVenta,
        if (campos.contains('precioCompra')) 'precio_compra': datos.precioCompra,
        if (campos.contains('precioRebaja')) 'precio_rebaja': datos.precioRebaja,
        if (campos.contains('fechaVencimiento'))
          'fecha_vencimiento': datos.fechaVencimiento,
        if (campos.contains('stock')) 'stock': datos.stock,
        if (campos.contains('stockMinimo')) 'stock_minimo': datos.stockMinimo,
        if (campos.contains('categoriaId')) 'categoria_id': datos.categoriaId,
        if (campos.contains('proveedorId')) 'proveedor_id': datos.proveedorId,
        if (campos.contains('presentacionId'))
          'presentacion_id': datos.presentacionId,
        if (campos.contains('marcaId')) 'marca_id': datos.marcaId,
        if (campos.contains('garantiaMeses'))
          'garantia_meses': datos.garantiaMeses,
        if (campos.contains('estado')) 'estado': datos.estado,
      };

      // Con variantes el stock agregado siempre se reescribe: es la suma
      // de las filas (lista no vacía) o el stock del cuerpo para el
      // «Único» (lista vacía; si el cuerpo no trae stock, se conserva).
      double? stockObjetivo;
      if (variantes != null) {
        stockObjetivo = variantes.isEmpty
            ? (campos.contains('stock') ? datos.stock : (antes ?? datos.stock))
            : cantidad(_sumaCantidades(variantes));
        cambios['stock'] = stockObjetivo;
      }

      final upd = updateSet(
        cambios,
        casts: const {'estado': 'estado_producto'},
      );
      // `version` crece en cada escritura; con `versionEsperado` el `WHERE`
      // falla si otra persona editó primero (guarda optimista).
      final idParam = upd.params.length + 1;
      final sql =
          'UPDATE productos SET ${upd.set}, version = version + 1 '
          'WHERE producto_id = \$$idParam'
          '${versionEsperado == null ? '' : ' AND version = \$${idParam + 1}'} '
          'RETURNING $_columns';
      final params = [...upd.params, id, ?versionEsperado];

      final resultado = await session.query(sql, params);
      filas.addAll(resultado);
      if (resultado.isEmpty) return;

      // Las variantes solo se tocan con el producto ya escrito: si el
      // `UPDATE` no aplicó (versión vieja), no se sincroniza nada.
      if (variantes != null) {
        if (variantes.isEmpty) {
          await _reEscribirVariantes(session, id, const [], const []);
          await _asegurarUnico(session, id, stockObjetivo!);
        } else {
          await _reEscribirVariantes(session, id, variantes, colores);
        }
      } else if (campos.contains('stock')) {
        await _sincronizarUnicaVariante(session, id, datos.stock);
      }

      // Un cambio de stock es un movimiento de kardex: se registra la
      // diferencia en la misma transacción, de modo que el kardex nunca se
      // queda corto.
      if (antes != null) {
        final despues = RowUtils.doubleValue(resultado.first['stock']);
        final delta = despues - antes;
        if (delta.abs() > 0.0005) {
          await session.query(
            'INSERT INTO movimientos_stock '
            '(producto_id, cantidad, motivo, stock_resultante, notas) '
            'VALUES (\$1, \$2, \'AJUSTE\', \$3, \$4)',
            [id, delta, despues, 'Ajuste manual de existencias'],
          );
        }
      }
    });

    if (filas.isEmpty) {
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
    // Devuelvo con las variantes ya sincronizadas (misma lectura que
    // `findById`), no la fila cruda del `UPDATE`.
    final guardado = await findById(id);
    return guardado!;
  }

  @override
  Future<bool> delete(int id) => ocultarRegistro(
    _db,
    tabla: 'productos',
    pk: 'producto_id',
    enumTipo: 'estado_producto',
    id: id,
  );

  // --- Variantes ----------------------------------------------------------

  static double _sumaCantidades(List<VarianteEntrada> entradas) =>
      entradas.fold(0.0, (suma, fila) => suma + fila.cantidad);

  /// Resuelve los colores de las filas de entrada **dentro de la
  /// transacción**: busca por id o por nombre sin distinguir mayúsculas y
  /// autocría el que no exista (ACTIVO, sin muestra). El índice único
  /// parcial de la 022 (`LOWER(nombre)` entre vivos) es el respaldo final
  /// para que nunca se duplique.
  Future<List<({int colorId, String nombre})>> _resolverColores(
    DatabaseSession session,
    List<VarianteEntrada> entradas,
  ) async {
    final resueltos = <({int colorId, String nombre})>[];
    final vistos = <int>{};
    for (final fila in entradas) {
      final int colorId;
      final String nombre;
      if (fila.colorId != null) {
        final rows = await session.query(
          'SELECT color_id, nombre FROM colores WHERE color_id = \$1',
          [fila.colorId],
        );
        if (rows.isEmpty) {
          throw BadRequestException(
            'El color ${fila.colorId} no existe.',
            code: 'color_no_encontrada',
          );
        }
        colorId = RowUtils.intValue(rows.first['color_id']);
        nombre = RowUtils.text(rows.first['nombre']);
      } else {
        final texto = fila.color?.trim() ?? '';
        if (texto.isEmpty) {
          throw const BadRequestException(
            'Cada variante necesita un color ("colorId" o "color").',
            code: 'variante_invalida',
          );
        }
        final rows = await session.query(
          'SELECT color_id, nombre FROM colores '
          'WHERE LOWER(nombre) = \$1 AND estado <> \'ELIMINADO\' LIMIT 1',
          [texto.toLowerCase()],
        );
        if (rows.isEmpty) {
          final creado = await session.query(
            'INSERT INTO colores (nombre, estado) '
            'VALUES (\$1, \'ACTIVO\'::estado_general) '
            'RETURNING color_id, nombre',
            [texto],
          );
          colorId = RowUtils.intValue(creado.first['color_id']);
          nombre = RowUtils.text(creado.first['nombre']);
        } else {
          colorId = RowUtils.intValue(rows.first['color_id']);
          nombre = RowUtils.text(rows.first['nombre']);
        }
      }
      if (!vistos.add(colorId)) {
        throw BadRequestException(
          'El color "$nombre" aparece más de una vez en las variantes del '
          'producto.',
          code: 'variante_duplicada',
        );
      }
      resueltos.add((colorId: colorId, nombre: nombre));
    }
    return resueltos;
  }

  /// Un `stock` en el cuerpo solo puede escribirse cuando el producto tiene
  /// **una** sola variante viva; con varias, el stock se edita por variante.
  Future<void> _asegurarStockPorVarianteValido(
    DatabaseSession session,
    int productoId,
  ) async {
    final rows = await session.query(
      'SELECT count(*) AS total FROM producto_variantes '
      'WHERE producto_id = \$1 AND estado <> \'ELIMINADO\'',
      [productoId],
    );
    final total = RowUtils.intValue(rows.first['total']);
    if (total <= 1) return;
    throw BadRequestException(
      'El producto tiene $total variantes con stock propio: edita el stock '
      'enviando el campo "variantes" (color · cantidad) en lugar de "stock".',
      code: 'stock_por_variante',
    );
  }

  /// Reescribe las variantes del producto según las filas pedidas: las vivas
  /// que no siguen en la lista se retiran (borrado lógico) y cada fila se
  /// inserta o actualiza. El `nombre_color` **solo se escribe al crear**:
  /// es inmutable porque las líneas de venta viejas lo leen por JOIN
  /// (renombrar un color no reescribe el histórico).
  Future<void> _reEscribirVariantes(
    DatabaseSession session,
    int productoId,
    List<VarianteEntrada> entradas,
    List<({int colorId, String nombre})> colores,
  ) async {
    final vivas = await session.query(
      'SELECT variante_id, color_id FROM producto_variantes '
      'WHERE producto_id = \$1 AND estado <> \'ELIMINADO\'',
      [productoId],
    );
    final pedidos = <int>{for (final c in colores) c.colorId};
    for (final row in vivas) {
      final colorId = RowUtils.intOrNull(row['color_id']);
      if (colorId != null && pedidos.contains(colorId)) continue;
      await session.query(
        'UPDATE producto_variantes SET estado = \'ELIMINADO\'::estado_general, '
        'fecha_actualizacion = CURRENT_TIMESTAMP '
        'WHERE variante_id = \$1 AND estado <> \'ELIMINADO\'',
        [RowUtils.intValue(row['variante_id'])],
      );
    }

    for (var i = 0; i < entradas.length; i++) {
      final stock = entradas[i].cantidad;
      final existente = await session.query(
        'SELECT variante_id FROM producto_variantes '
        'WHERE producto_id = \$1 AND color_id = \$2 '
        'ORDER BY (estado = \'ELIMINADO\'), variante_id LIMIT 1',
        [productoId, colores[i].colorId],
      );
      if (existente.isEmpty) {
        await session.query(
          'INSERT INTO producto_variantes (producto_id, color_id, '
          'nombre_color, stock) VALUES (\$1, \$2, \$3, \$4)',
          [productoId, colores[i].colorId, colores[i].nombre, stock],
        );
      } else {
        // Reaparecer una variante retirada la revive con su stock nuevo
        // (la fila y su `nombre_color` original se conservan).
        await session.query(
          'UPDATE producto_variantes SET stock = \$2, '
          'estado = \'ACTIVO\'::estado_general, '
          'fecha_actualizacion = CURRENT_TIMESTAMP '
          'WHERE variante_id = \$1',
          [RowUtils.intValue(existente.first['variante_id']), stock],
        );
      }
    }
  }

  /// Garantiza la variante «Único» viva con el stock indicado (el producto
  /// sin filas de color vuelve a vender como unidad simple).
  Future<void> _asegurarUnico(
    DatabaseSession session,
    int productoId,
    double stock,
  ) async {
    final existente = await session.query(
      'SELECT variante_id FROM producto_variantes '
      'WHERE producto_id = \$1 AND color_id IS NULL '
      'ORDER BY (estado = \'ELIMINADO\'), variante_id LIMIT 1',
      [productoId],
    );
    if (existente.isEmpty) {
      await session.query(
        'INSERT INTO producto_variantes (producto_id, color_id, '
        'nombre_color, stock) VALUES (\$1, NULL, \'Único\', \$2)',
        [productoId, stock],
      );
    } else {
      await session.query(
        'UPDATE producto_variantes SET stock = \$2, '
        'estado = \'ACTIVO\'::estado_general, '
        'fecha_actualizacion = CURRENT_TIMESTAMP '
        'WHERE variante_id = \$1',
        [RowUtils.intValue(existente.first['variante_id']), stock],
      );
    }
  }

  /// Al escribir `stock` directamente (producto de **una** sola variante),
  /// la variante sigue al agregado: la suma vuelve a cuadrar.
  Future<void> _sincronizarUnicaVariante(
    DatabaseSession session,
    int productoId,
    double stock,
  ) => session.query(
    'UPDATE producto_variantes SET stock = \$2, '
    'fecha_actualizacion = CURRENT_TIMESTAMP '
    'WHERE producto_id = \$1 AND estado <> \'ELIMINADO\'',
    [productoId, stock],
  );
}
