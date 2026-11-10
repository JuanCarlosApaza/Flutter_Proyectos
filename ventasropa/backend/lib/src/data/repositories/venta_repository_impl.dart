import '../../core/errors/app_exception.dart';
import '../../domain/entities/venta.dart';
import '../../domain/repositories/venta_repository.dart';
import '../../domain/rules/estados.dart';
import '../database/database.dart';
import '../models/row_utils.dart';
import '../models/venta_model.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [VentaRepository].
///
/// Las operaciones multi-sentencia (crear orden con líneas, recalcular totales,
/// descontar stock) se ejecutan con `runInTransaction`: o se aplican todas o
/// ninguna.
final class VentaRepositoryImpl implements VentaRepository {
  VentaRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _ordenColumns =
      'orden_id, fecha_orden, cliente_id, nombre_cliente, empleado_id, '
      'total, rebaja, factura, estado::text AS estado, fecha_creacion, '
      'fecha_actualizacion';

  static const String _pagoColumns =
      'pago_id, orden_id, metodo_pago, monto, referencia, '
      'estado::text AS estado, fecha_creacion, fecha_actualizacion';

  /// Líneas con su variante y los nombres de talla/color/marca ya
  /// resueltos (`LEFT JOIN` para que una línea siga apareciendo aunque la
  /// variante haya cambiado de nombre; la marca es opcional).
  static const String _detalleSelect =
      'SELECT d.variante_id, d.producto_id, d.orden_id, d.nombre_producto, '
      't.nombre AS talla, c.nombre AS color, m.nombre_marca AS marca, '
      'd.unidad, d.cantidad, '
      'd.precio_venta, d.costo_unitario, d.monto_total '
      'FROM detalles_ordenes_pedidos d '
      'LEFT JOIN producto_variantes v ON v.variante_id = d.variante_id '
      'LEFT JOIN tallas t ON t.talla_id = v.talla_id '
      'LEFT JOIN colores c ON c.color_id = v.color_id '
      'LEFT JOIN productos p ON p.producto_id = d.producto_id '
      'LEFT JOIN marcas m ON m.marca_id = p.marca_id ';

  static const String _facturaColumns =
      'factura_numero, fecha_factura, empleado_id, cliente_id, orden_id, '
      'subtotal, rebaja, iva, estado::text AS estado, fecha_creacion, '
      'fecha_actualizacion';

  /// Recalcula `total` como la suma de sus **líneas visibles** (las ocultas
  /// por borrado lógico no cuentan).
  static const String _recalcularTotal =
      'UPDATE ordenes_pedidos SET total = COALESCE((SELECT SUM(monto_total) '
      'FROM detalles_ordenes_pedidos WHERE orden_id = \$1 AND $estadoVisible), '
      '0), fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE orden_id = \$1 RETURNING ';

  // --- Órdenes -------------------------------------------------------------

  @override
  Future<List<OrdenPedido>> findOrdenes({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_orden');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('ordenes_pedidos', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_ordenColumns FROM ordenes_pedidos$where${busqueda.sql} '
      'ORDER BY orden_id DESC LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    final ordenes = rows.map(VentaModel.orden).toList();
    return _conPagos(ordenes);
  }

  @override
  Future<int> countOrdenes({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_orden');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('ordenes_pedidos', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM ordenes_pedidos'
      '$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<OrdenPedido?> findOrdenById(int id) async {
    final rows = await _db.query(
      'SELECT $_ordenColumns FROM ordenes_pedidos WHERE orden_id = \$1',
      [id],
    );
    if (rows.isEmpty) return null;
    final pagos = await findPagosByOrden(id);
    return VentaModel.orden(rows.first, pagos: pagos);
  }

  @override
  Future<List<Pago>> findPagosByOrden(int ordenId) async {
    final rows = await _db.query(
      'SELECT $_pagoColumns FROM pagos WHERE orden_id = \$1 AND $estadoVisible '
      'ORDER BY pago_id',
      [ordenId],
    );
    return rows.map(VentaModel.pago).toList();
  }

  /// Adjunta los pagos (una sola query para toda la página) a las órdenes.
  Future<List<OrdenPedido>> _conPagos(List<OrdenPedido> ordenes) async {
    if (ordenes.isEmpty) return ordenes;
    final ids = ordenes.map((o) => o.id).toList();
    final rows = await _db.query(
      'SELECT $_pagoColumns FROM pagos WHERE orden_id = ANY(\$1) AND '
      '$estadoVisible ORDER BY orden_id, pago_id',
      [ids],
    );
    final porOrden = <int, List<Pago>>{};
    for (final row in rows) {
      final ordenId = RowUtils.intValue(row['orden_id']);
      (porOrden[ordenId] ??= []).add(VentaModel.pago(row));
    }
    return [
      for (final orden in ordenes)
        orden.conPagos(porOrden[orden.id] ?? const []),
    ];
  }

  @override
  Future<OrdenPedido> insertOrden(
    OrdenPedido datos,
    List<DetalleOrden> detalles,
    List<Pago> pagos,
  ) async {
    OrdenPedido? creada;

    await _db.runInTransaction((session) async {
      final rows = await session.query(
        'INSERT INTO ordenes_pedidos (cliente_id, nombre_cliente, empleado_id, '
        'total, rebaja, factura, estado) '
        'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7::estado_orden) '
        'RETURNING $_ordenColumns',
        [
          datos.clienteId,
          datos.nombreCliente,
          datos.empleadoId,
          datos.total,
          datos.rebaja,
          datos.factura,
          datos.estado,
        ],
      );
      final orden = VentaModel.orden(rows.first);

      for (final linea in detalles) {
        await session.query(
          'INSERT INTO detalles_ordenes_pedidos (producto_id, variante_id, '
          'orden_id, nombre_producto, unidad, cantidad, precio_venta, '
          'costo_unitario, monto_total) '
          'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)',
          [
            linea.productoId,
            linea.varianteId,
            orden.id,
            linea.nombreProducto,
            linea.unidad,
            linea.cantidad,
            linea.precioVenta,
            linea.costoUnitario,
            linea.montoTotal,
          ],
        );
      }

      for (final pago in pagos) {
        await session.query(
          'INSERT INTO pagos (orden_id, metodo_pago, monto, referencia) '
          'VALUES (\$1, \$2, \$3, \$4)',
          [orden.id, pago.metodoPago, pago.monto, pago.referencia],
        );
      }
      creada = orden.conPagos(pagos);
    });

    return creada!;
  }

  @override
  Future<OrdenPedido> cambiarEstadoAtomico(
    int ordenId, {
    required String estadoActualEsperado,
    required String nuevoEstado,
    required bool descontarStock,
    required bool reponerStock,
  }) async {
    OrdenPedido? resultado;

    await _db.runInTransaction((session) async {
      final actual = await _bloquearOrden(session, ordenId);
      if (actual == null) {
        throw const NotFoundException(
          'La orden no existe.',
          code: 'orden_no_encontrada',
        );
      }

      // Otra petición ya hizo este mismo cambio (doble clic o doble clic
      // concurrente): no se repite el descuento ni la reposición de stock.
      if (actual == nuevoEstado) {
        final rows = await session.query(
          'SELECT $_ordenColumns FROM ordenes_pedidos WHERE orden_id = \$1',
          [ordenId],
        );
        resultado = VentaModel.orden(rows.first);
        return;
      }

      // La fila cambió entre la lectura del caso de uso y el bloqueo: nadie
      // debe adivinar qué gana, se avisa y la persona reintenta.
      if (actual != estadoActualEsperado) {
        throw ConflictException(
          'La orden $ordenId está $actual: otro usuario la cambió mientras '
          'tanto. Recarga e inténtalo de nuevo.',
          code: 'estado_cambiado',
        );
      }

      if (descontarStock) {
        await _aplicarCobro(session, ordenId);
      } else if (reponerStock) {
        await _revertirCobro(session, ordenId);
      }

      final rows = await session.query(
        'UPDATE ordenes_pedidos SET estado = \$1::estado_orden, '
        'fecha_actualizacion = CURRENT_TIMESTAMP '
        'WHERE orden_id = \$2 RETURNING $_ordenColumns',
        [nuevoEstado, ordenId],
      );
      resultado = VentaModel.orden(rows.first);
    });

    return resultado!;
  }

  @override
  Future<bool> deleteOrden(int ordenId) async {
    var ocultada = false;
    await _db.runInTransaction((session) async {
      // Con la orden bloqueada: ocultarla no puede cruzarse con un cobro ni
      // con la emisión de su factura (ambos bloquean la misma fila).
      final estado = await _bloquearOrden(session, ordenId);
      if (estado == null) return;
      if (estado == 'PAGADO') {
        throw ConflictException(
          'No se puede eliminar una orden PAGADA: anúlala o devuélvela antes.',
          code: 'orden_pagada',
        );
      }
      final factura = await session.query(
        'SELECT 1 FROM facturas WHERE orden_id = \$1 AND $estadoVisible',
        [ordenId],
      );
      if (factura.isNotEmpty) {
        throw const ConflictException(
          'La orden ya tiene una factura emitida.',
          code: 'orden_con_factura',
        );
      }
      final sentencia = sentenciaOcultar(
        tabla: 'ordenes_pedidos',
        pk: 'orden_id',
        enumTipo: 'estado_orden',
        id: ordenId,
      );
      final rows = await session.query(sentencia.sql, sentencia.params);
      ocultada = rows.isNotEmpty;
    });
    return ocultada;
  }

  // --- Detalles ------------------------------------------------------------

  @override
  Future<List<DetalleOrden>> findDetallesByOrden(int ordenId) async {
    final rows = await _db.query(
      '$_detalleSelect WHERE d.orden_id = \$1 AND d.$estadoVisible '
      'ORDER BY d.producto_id, d.variante_id',
      [ordenId],
    );
    return rows.map(VentaModel.detalle).toList();
  }

  @override
  Future<DetalleOrden?> findDetalle(int ordenId, int varianteId) async {
    final rows = await _db.query(
      '$_detalleSelect WHERE d.orden_id = \$1 AND d.variante_id = \$2 '
      'AND d.$estadoVisible',
      [ordenId, varianteId],
    );
    return rows.isEmpty ? null : VentaModel.detalle(rows.first);
  }

  @override
  Future<DetalleOrden> upsertDetalle(DetalleOrden detalle) async {
    await _db.runInTransaction((session) async {
      // La orden se bloquea primero: la línea no se cruza con un cobro y el
      // recálculo del total ve las líneas ya confirmadas.
      await _asegurarOrdenEditable(session, detalle.ordenId);
      await session.query(
        'INSERT INTO detalles_ordenes_pedidos (producto_id, variante_id, '
        'orden_id, nombre_producto, unidad, cantidad, precio_venta, '
        'costo_unitario, monto_total) '
        'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9) '
        'ON CONFLICT (variante_id, orden_id) DO UPDATE SET '
        'nombre_producto = EXCLUDED.nombre_producto, '
        'unidad = EXCLUDED.unidad, '
        'cantidad = EXCLUDED.cantidad, '
        'precio_venta = EXCLUDED.precio_venta, '
        'costo_unitario = EXCLUDED.costo_unitario, '
        // Reagregar una línea que se había ocultado la **revive**: como la
        // clave primaria sigue ocupada, no se inserta una fila nueva.
        'monto_total = EXCLUDED.monto_total, '
        "estado = 'ACTIVO'",
        [
          detalle.productoId,
          detalle.varianteId,
          detalle.ordenId,
          detalle.nombreProducto,
          detalle.unidad,
          detalle.cantidad,
          detalle.precioVenta,
          detalle.costoUnitario,
          detalle.montoTotal,
        ],
      );
      await session.query('$_recalcularTotal$_ordenColumns', [detalle.ordenId]);
    });

    final guardado = await findDetalle(detalle.ordenId, detalle.varianteId);
    return guardado ?? detalle;
  }

  @override
  Future<bool> deleteDetalle(int ordenId, int varianteId) async {
    var borrado = false;
    await _db.runInTransaction((session) async {
      // Mismo bloqueo que `upsertDetalle`: editar mientras se cobra no puede
      // dejar una línea cobrada sin descontar o el total desfasado.
      await _asegurarOrdenEditable(session, ordenId);
      // Ocultamiento lógico: la línea se conserva en la BD y simplemente deja
      // de contar para el total y para la venta.
      final rows = await session.query(
        'UPDATE detalles_ordenes_pedidos SET estado = \$1::estado_general '
        'WHERE orden_id = \$2 AND variante_id = \$3 '
        'AND estado IS DISTINCT FROM \$1::estado_general '
        'RETURNING variante_id',
        [estadoEliminado, ordenId, varianteId],
      );
      borrado = rows.isNotEmpty;
      if (borrado) {
        await session.query('$_recalcularTotal$_ordenColumns', [ordenId]);
      }
    });
    return borrado;
  }

  // --- Locks de órdenes y stock --------------------------------------------
  //
  // Jerarquía de bloqueos (la respetan todas las transacciones de este
  // repositorio para no morir en deadlock): orden → detalles → productos →
  // facturas. El `ORDER BY producto_id` del `FOR UPDATE` de líneas fija el
  // orden en que dos cobros distintos toman los productos.

  /// Bloquea la fila de la orden (`FOR UPDATE`) y devuelve su estado bajo el
  /// bloqueo; `null` si la orden no existe.
  Future<String?> _bloquearOrden(DatabaseSession session, int ordenId) async {
    final rows = await session.query(
      'SELECT estado::text AS estado FROM ordenes_pedidos '
      'WHERE orden_id = \$1 FOR UPDATE',
      [ordenId],
    );
    return rows.isEmpty ? null : rows.first['estado'] as String?;
  }

  /// Bloquea la orden y exige que sus líneas sean editables; el mismo
  /// predicado que el dominio ([esOrdenEditable]), pero leído **bajo** el
  /// bloqueo para que un cobro concurrente no se cuelque.
  Future<void> _asegurarOrdenEditable(
    DatabaseSession session,
    int ordenId,
  ) async {
    final estado = await _bloquearOrden(session, ordenId);
    if (estado == null) {
      throw const NotFoundException(
        'La orden no existe.',
        code: 'orden_no_encontrada',
      );
    }
    if (!esOrdenEditable(estado)) {
      throw ConflictException(
        'La orden $ordenId está $estado: solo se pueden modificar '
        'órdenes PENDIENTE o DEVUELTO.',
        code: 'orden_no_editable',
      );
    }
  }

  /// Descuenta el stock de la **variante** de cada línea de la orden (con
  /// las líneas bloqueadas y en orden fijo) y recalcula el agregado del
  /// producto en la misma transacción.
  ///
  /// Lanza `ConflictException` si alguna línea no tiene stock suficiente
  /// (también se comprueba en SQL para que sea atómico).
  Future<void> _aplicarCobro(DatabaseSession session, int ordenId) async {
    final lineas = await session.query(
      'SELECT d.variante_id, d.producto_id, d.cantidad, d.nombre_producto, '
      't.nombre AS talla, c.nombre AS color '
      'FROM detalles_ordenes_pedidos d '
      'LEFT JOIN producto_variantes v ON v.variante_id = d.variante_id '
      'LEFT JOIN tallas t ON t.talla_id = v.talla_id '
      'LEFT JOIN colores c ON c.color_id = v.color_id '
      'WHERE d.orden_id = \$1 AND d.$estadoVisible '
      'ORDER BY d.producto_id, d.variante_id FOR UPDATE OF d',
      [ordenId],
    );

    final productosAfectados = <int>{};
    for (final linea in lineas) {
      final cantidad = RowUtils.doubleValue(linea['cantidad']);
      final varianteId = RowUtils.intValue(linea['variante_id']);
      final productoId = RowUtils.intValue(linea['producto_id']);
      final etiqueta = _etiquetaVariante(linea);

      final descontado = await session.query(
        // El stock real vive en la variante: sin unidades suficientes la
        // sentencia no actualiza ninguna fila y se devuelve 409.
        'UPDATE producto_variantes SET stock = stock - \$1 '
        'WHERE variante_id = \$2 AND stock >= \$1 '
        'RETURNING variante_id, stock',
        [cantidad, varianteId],
      );
      if (descontado.isEmpty) {
        final actual = await session.query(
          'SELECT stock FROM producto_variantes WHERE variante_id = \$1',
          [varianteId],
        );
        throw ConflictException(
          'Stock insuficiente para "${linea['nombre_producto']}"$etiqueta: '
          'no quedan ${actual.isEmpty ? 0 : RowUtils.doubleValue(actual.first['stock'])} '
          'unidades (solicitado $cantidad).',
          code: 'stock_insuficiente',
        );
      }
      await _registrarMovimiento(
        session,
        productoId: productoId,
        varianteId: varianteId,
        cantidad: -cantidad,
        motivo: 'VENTA',
        stockResultante: RowUtils.doubleValue(descontado.first['stock']),
        ordenId: ordenId,
      );
      productosAfectados.add(productoId);
    }
    for (final productoId in productosAfectados) {
      await session.query(recalcularStockProducto, [productoId]);
    }
  }

  /// Devuelve al stock la variante de cada línea de una orden cobrada
  /// (mismos bloqueos y orden que [_aplicarCobro]).
  Future<void> _revertirCobro(DatabaseSession session, int ordenId) async {
    final lineas = await session.query(
      'SELECT variante_id, producto_id, cantidad FROM detalles_ordenes_pedidos '
      'WHERE orden_id = \$1 AND $estadoVisible '
      'ORDER BY producto_id, variante_id FOR UPDATE',
      [ordenId],
    );

    final productosAfectados = <int>{};
    for (final linea in lineas) {
      final cantidad = RowUtils.doubleValue(linea['cantidad']);
      final varianteId = RowUtils.intValue(linea['variante_id']);
      final productoId = RowUtils.intValue(linea['producto_id']);
      final revertido = await session.query(
        'UPDATE producto_variantes SET stock = stock + \$1 '
        'WHERE variante_id = \$2 RETURNING variante_id, stock',
        [cantidad, varianteId],
      );
      if (revertido.isEmpty) continue;
      await _registrarMovimiento(
        session,
        productoId: productoId,
        varianteId: varianteId,
        cantidad: cantidad,
        motivo: 'DEVOLUCION',
        stockResultante: RowUtils.doubleValue(revertido.first['stock']),
        ordenId: ordenId,
      );
      productosAfectados.add(productoId);
    }
    for (final productoId in productosAfectados) {
      await session.query(recalcularStockProducto, [productoId]);
    }
  }

  /// Sufijo de mensaje «(talla M, color Negro)» para errores de stock.
  String _etiquetaVariante(Map<String, Object?> linea) {
    final talla = RowUtils.textOrNull(linea['talla']);
    final color = RowUtils.textOrNull(linea['color']);
    if (talla == null && color == null) return '';
    return ' (talla ${talla ?? '—'}, color ${color ?? '—'})';
  }

  /// Escribe una fila del kardex dentro de la transacción que mueve el stock:
  /// o quedan las dos cosas hechas o ninguna.
  Future<void> _registrarMovimiento(
    DatabaseSession session, {
    required int productoId,
    int? varianteId,
    required double cantidad,
    required String motivo,
    required double stockResultante,
    int? ordenId,
    String? notas,
  }) => session.query(
    'INSERT INTO movimientos_stock '
    '(producto_id, variante_id, cantidad, motivo, stock_resultante, orden_id, '
    'notas) VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7)',
    [productoId, varianteId, cantidad, motivo, stockResultante, ordenId, notas],
  );

  // --- Facturas -------------------------------------------------------------

  @override
  Future<List<Factura>> findFacturas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_factura');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('facturas', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_facturaColumns FROM facturas$where${busqueda.sql} '
      'ORDER BY factura_numero DESC LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(VentaModel.factura).toList();
  }

  @override
  Future<int> countFacturas({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_factura');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('facturas', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM facturas$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Factura?> findFacturaById(int id) async {
    final rows = await _db.query(
      'SELECT $_facturaColumns FROM facturas WHERE factura_numero = \$1',
      [id],
    );
    return rows.isEmpty ? null : VentaModel.factura(rows.first);
  }

  @override
  Future<Factura?> findFacturaByOrden(
    int ordenId, {
    bool incluirOcultas = false,
  }) async {
    final rows = await _db.query(
      'SELECT $_facturaColumns FROM facturas WHERE orden_id = \$1'
      '${incluirOcultas ? '' : ' AND $estadoVisible'}',
      [ordenId],
    );
    return rows.isEmpty ? null : VentaModel.factura(rows.first);
  }

  @override
  Future<Factura> insertFactura(Factura datos) async {
    Factura? creada;

    await _db.runInTransaction((session) async {
      // La orden se bloquea primero (jerarquía de bloqueos) para que la
      // emisión no se cruce con una cancelación concurrente: debajo se
      // repiten las condiciones del caso de uso sobre el estado real.
      final ordenId = datos.ordenId;
      if (ordenId == null) {
        throw const BadRequestException(
          'La factura debe estar asociada a una orden.',
          code: 'orden_invalida',
        );
      }
      final estado = await _bloquearOrden(session, ordenId);
      if (estado == null) {
        throw const NotFoundException(
          'La orden no existe.',
          code: 'orden_no_encontrada',
        );
      }
      if (estado != 'PAGADO') {
        throw ConflictException(
          'La orden $ordenId está $estado: para emitir la factura '
          'debe estar PAGADA.',
          code: 'orden_no_pagada',
        );
      }
      // La fila oculta sigue ocupando el UNIQUE de `orden_id`.
      final existente = await session.query(
        'SELECT 1 FROM facturas WHERE orden_id = \$1',
        [ordenId],
      );
      if (existente.isNotEmpty) {
        throw ConflictException(
          'La orden $ordenId ya tiene una factura.',
          code: 'factura_duplicada',
        );
      }

      final rows = await session.query(
        'INSERT INTO facturas (empleado_id, cliente_id, orden_id, subtotal, '
        'rebaja, iva, estado) '
        'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7::estado_factura) '
        'RETURNING $_facturaColumns',
        [
          datos.empleadoId,
          datos.clienteId,
          ordenId,
          datos.subtotal,
          datos.rebaja,
          datos.iva,
          datos.estado,
        ],
      );
      creada = VentaModel.factura(rows.first);
    });

    return creada!;
  }

  @override
  Future<Factura> updateEstadoFactura(int id, String estado) async {
    final rows = await _db.query(
      'UPDATE facturas SET estado = \$1::estado_factura, '
      'fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE factura_numero = \$2 RETURNING $_facturaColumns',
      [estado, id],
    );
    if (rows.isEmpty) {
      throw const NotFoundException(
        'La factura no existe.',
        code: 'factura_no_encontrada',
      );
    }
    return VentaModel.factura(rows.first);
  }

  @override
  Future<bool> deleteFactura(int id) => ocultarRegistro(
    _db,
    tabla: 'facturas',
    pk: 'factura_numero',
    enumTipo: 'estado_factura',
    id: id,
  );
}
