import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
import '../entities/venta.dart';
import '../repositories/product_repository.dart';
import '../repositories/venta_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';
import '../rules/variantes.dart';

/// Casos de uso de las órdenes de pedido (y sus líneas).
///
/// Reglas de negocio que aquí se aplican:
///
/// * solo se puede editar una orden `PENDIENTE` o `DEVUELTO`;
/// * crear/agregar líneas exige stock suficiente y producto no descontinuado;
/// * al pasar a `PAGADO` se descuenta el stock; al salir de `PAGADO`
///   (`CANCELADO`/`DEVUELTO`/`PENDIENTE`) se repone;
/// * la **rebaja** se aplica al cobrar y el **IVA** (14.94 %) solo si la
///   venta es factura: los pagos cuadran contra `totalPagar`;
/// * no se borra una orden `PAGADO` ni una que ya tiene factura.
final class Ordenes {
  const Ordenes({required this.repository, required this.productos});

  final VentaRepository repository;
  final ProductRepository productos;

  Future<List<OrdenPedido>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findOrdenes(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosOrdenes, 'estado'),
    q: q,
  );

  /// Total de órdenes con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countOrdenes(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosOrdenes, 'estado'),
    q: q,
  );

  Future<OrdenPedido> obtener(int id) async {
    final orden = await repository.findOrdenById(id);
    if (orden == null) {
      throw NotFoundException(
        'La orden $id no existe.',
        code: 'orden_no_encontrada',
      );
    }
    return orden;
  }

  Future<List<DetalleOrden>> detallesDe(int ordenId) async {
    await obtener(ordenId);
    return repository.findDetallesByOrden(ordenId);
  }

  /// Crea la orden con sus líneas y su desglose de pagos en una transacción.
  ///
  /// [rebaja] es el descuento hecho al cobrar y [factura] activa el IVA
  /// boliviano: los pagos deben cuadrar contra `totalPagar`
  /// (`(total − rebaja) × 1.1494` si es factura).
  Future<OrdenPedido> crear({
    int? clienteId,
    String? nombreCliente,
    int? empleadoId,
    double rebaja = 0,
    bool factura = false,
    required List<Pago> pagos,
    required List<ItemOrden> items,
  }) async {
    if (items.isEmpty) {
      throw const BadRequestException(
        'La orden debe incluir al menos un item.',
        code: 'items_vacios',
      );
    }

    // Se resuelven los productos aquí (dominio) para poder devolver mensajes
    // claros antes de tocar la BD.
    final lineas = <DetalleOrden>[];
    var total = 0.0;
    // Tope total de rebaja: por línea, `cantidad × (precioRebaja del
    // producto ?? precio de venta)` — sin tope declarado, todo el precio.
    var maxRebaja = 0.0;
    final vistos = <String>{};

    for (final item in items) {
      ensurePositivo(item.cantidad, 'cantidad');

      final producto = vendible(
        await productos.findById(item.productoId),
        item.productoId,
      );
      asegurarComprable(producto);
      // La variante concreta que se vende (por id, por color o la única
      // viva del producto) y su stock propio.
      final variante = resolverVarianteViva(producto, item);
      if (!vistos.add('${producto.id}:${variante.varianteId}')) {
        throw BadRequestException(
          'El producto ${item.productoId} (${variante.nombreColor}) aparece '
          'más de una vez en la orden.',
          code: 'item_duplicado',
        );
      }
      _asegurarStock(variante, producto, item.cantidad);

      final monto = dinero(item.cantidad * producto.precioVenta);
      total += monto;
      final tope = producto.precioRebaja;
      maxRebaja +=
          (tope == null
              ? producto.precioVenta
              : (tope > producto.precioVenta ? producto.precioVenta : tope)) *
          item.cantidad;
      lineas.add(
        DetalleOrden(
          productoId: producto.id,
          ordenId: 0,
          nombreProducto: producto.nombre,
          cantidad: item.cantidad,
          precioVenta: producto.precioVenta,
          montoTotal: monto,
          unidad: producto.unidad,
          costoUnitario: producto.precioCompra,
          varianteId: variante.varianteId,
          nombreColor: variante.nombreColor,
        ),
      );
    }

    total = dinero(total);
    maxRebaja = dinero(maxRebaja);
    ensureImporteNoNegativo(rebaja, 'rebaja');
    if (rebaja > total) {
      throw BadRequestException(
        'La rebaja ($rebaja) no puede superar el total de la orden ($total).',
        code: 'rebaja_excesiva',
      );
    }
    if (rebaja > maxRebaja) {
      throw BadRequestException(
        'La rebaja ($rebaja) no puede superar el máximo permitido por los '
        'productos (Bs $maxRebaja).',
        code: 'rebaja_excesiva',
      );
    }
    final orden = OrdenPedido(
      id: 0,
      fechaOrden: DateTime.now().toUtc(),
      clienteId: clienteId,
      nombreCliente: nombreCliente,
      empleadoId: empleadoId,
      total: total,
      rebaja: dinero(rebaja),
      factura: factura,
      estado: 'PENDIENTE',
      fechaCreacion: DateTime.now().toUtc(),
      fechaActualizacion: DateTime.now().toUtc(),
    );
    final pagosValidados = _asegurarPagos(pagos, orden.totalPagar);

    return repository.insertOrden(orden, lineas, pagosValidados);
  }

  /// Valida el desglose de pagos: al menos uno, montos positivos, métodos y
  /// referencias válidos, y que la suma cuadre (con tolerancia de redondeo)
  /// con el total a pagar (ya con rebaja e IVA aplicados).
  List<Pago> _asegurarPagos(List<Pago> crudos, double total) {
    if (crudos.isEmpty) {
      throw const BadRequestException(
        'La orden debe indicar al menos un método de pago.',
        code: 'pagos_vacios',
      );
    }
    final ahora = DateTime.now().toUtc();
    final validados = <Pago>[];
    var suma = 0.0;
    for (final crudo in crudos) {
      final monto = ensureImportePositivo(crudo.monto, 'monto');
      validados.add(
        Pago(
          metodoPago: ensureMetodoPago(crudo.metodoPago),
          monto: monto,
          referencia: ensureReferencia(crudo.referencia),
          estado: 'ACTIVO',
          fechaCreacion: ahora,
          fechaActualizacion: ahora,
        ),
      );
      suma += monto;
    }
    if ((suma - total).abs() > 0.009) {
      throw BadRequestException(
        'Los pagos suman Bs ${suma.toStringAsFixed(2)} pero el total a '
        'pagar es Bs ${total.toStringAsFixed(2)}.',
        code: 'pago_no_cuadra',
      );
    }
    return validados;
  }

  /// Agrega (o reemplaza) una línea de la orden y recalcula su total.
  ///
  /// La variante se identifica con [varianteId], [colorId] o [color] (o es
  /// la única viva del producto): dos colores distintos del mismo producto
  /// son dos líneas independientes; repetir la misma variante reemplaza la
  /// cantidad de esa línea.
  Future<DetalleOrden> agregarItem(
    int ordenId, {
    required int productoId,
    required double cantidad,
    int? varianteId,
    int? colorId,
    String? color,
  }) async {
    final orden = await obtener(ordenId);
    _asegurarEditable(orden);
    ensurePositivo(cantidad, 'cantidad');

    final producto = vendible(await productos.findById(productoId), productoId);
    asegurarComprable(producto);
    final variante = resolverVarianteViva(
      producto,
      ItemOrden(
        productoId: productoId,
        cantidad: cantidad,
        varianteId: varianteId,
        colorId: colorId,
        color: color,
      ),
    );
    _asegurarStock(variante, producto, cantidad);

    return repository.upsertDetalle(
      DetalleOrden(
        productoId: productoId,
        ordenId: ordenId,
        nombreProducto: producto.nombre,
        cantidad: cantidad,
        precioVenta: producto.precioVenta,
        montoTotal: dinero(cantidad * producto.precioVenta),
        unidad: producto.unidad,
        costoUnitario: producto.precioCompra,
        varianteId: variante.varianteId,
        nombreColor: variante.nombreColor,
      ),
    );
  }

  /// Elimina una línea y recalcula el total de la orden.
  ///
  /// Con [varianteId] se elimina solo esa variante; sin él, todas las
  /// líneas de ese producto en la orden.
  Future<void> quitarItem(int ordenId, int productoId, {int? varianteId}) async {
    final orden = await obtener(ordenId);
    _asegurarEditable(orden);

    final detalle = await repository.findDetalle(
      ordenId,
      productoId,
      varianteId: varianteId,
    );
    if (detalle == null) {
      throw NotFoundException(
        'El producto $productoId no está en la orden $ordenId.',
        code: 'detalle_no_encontrado',
      );
    }
    await repository.deleteDetalle(ordenId, productoId, varianteId: varianteId);
  }

  /// Cambia el estado de la orden aplicando la regla de stock:
  /// entrar en `PAGADO` descuenta; salir de `PAGADO` repone.
  ///
  /// El salto completo (bloqueo de la fila, validación del estado previo,
  /// stock y `UPDATE`) ocurre en **una sola transacción** en el repositorio,
  /// así que dos cobros simultáneos no descuentan dos veces.
  Future<OrdenPedido> cambiarEstado(int id, String estado) async {
    final actual = await obtener(id);
    final nuevo = ensureEstado(estado, estadosOrdenes, 'estado');
    if (nuevo == actual.estado) return actual;

    return repository.cambiarEstadoAtomico(
      id,
      estadoActualEsperado: actual.estado,
      nuevoEstado: nuevo,
      descontarStock: nuevo == 'PAGADO',
      reponerStock: actual.estado == 'PAGADO',
    );
  }

  Future<void> eliminar(int id) async {
    final orden = await obtener(id);
    if (orden.estado == 'PAGADO') {
      throw const ConflictException(
        'No se puede eliminar una orden PAGADA: anúlala o devuélvela antes.',
        code: 'orden_pagada',
      );
    }
    if (await repository.findFacturaByOrden(id) != null) {
      throw const ConflictException(
        'La orden ya tiene una factura emitida.',
        code: 'orden_con_factura',
      );
    }
    final removed = await repository.deleteOrden(id);
    if (!removed) {
      throw NotFoundException(
        'La orden $id no existe.',
        code: 'orden_no_encontrada',
      );
    }
  }

  // --- Reglas auxiliares -----------------------------------------------------

  void _asegurarEditable(OrdenPedido orden) {
    if (!orden.editable) {
      throw ConflictException(
        'La orden ${orden.id} está ${orden.estado}: solo se pueden modificar '
        'órdenes PENDIENTE o DEVUELTO.',
        code: 'orden_no_editable',
      );
    }
  }

  /// El stock se comprueba en la **variante** que se vende (la suma de las
  /// variantes es el stock del producto, así que cubre la venta).
  void _asegurarStock(
    VarianteProducto variante,
    Product producto,
    double cantidadVendida,
  ) {
    // Con cantidades fraccionadas la resta puede quedar en -1e-15 por coma
    // flotante; se tolera una milésima para no rechazar un 12.750 exacto.
    if (variante.stock - cantidadVendida < -0.0005) {
      final donde = variante.colorId == null
          ? ''
          : ' (color ${variante.nombreColor})';
      throw ConflictException(
        'Stock insuficiente para "${producto.nombre}"$donde: disponibles '
        '${variante.stock} ${producto.unidad}, solicitados $cantidadVendida.',
        code: 'stock_insuficiente',
      );
    }
  }
}

/// Casos de uso de las facturas (una por orden).
///
/// Reglas de negocio:
///
/// * solo se emite factura de una orden `PAGADO`;
/// * cada orden admite como mucho una factura (`UNIQUE` en la BD);
/// * la factura copia los importes ya cobrados de la orden (`subtotal`,
///   `rebaja` e `iva`): no se pide nada al emitir.
final class Facturas {
  const Facturas({required this.repository, required this.ordenes});

  final VentaRepository repository;
  final Ordenes ordenes;

  Future<List<Factura>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findFacturas(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosFacturas, 'estado'),
    q: q,
  );

  /// Total de facturas con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countFacturas(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosFacturas, 'estado'),
    q: q,
  );

  Future<Factura> obtener(int id) async {
    final factura = await repository.findFacturaById(id);
    if (factura == null) {
      throw NotFoundException(
        'La factura $id no existe.',
        code: 'factura_no_encontrada',
      );
    }
    return factura;
  }

  Future<Factura> emitir({
    required int ordenId,
    int? empleadoId,
    int? clienteId,
  }) async {
    final orden = await ordenes.obtener(ordenId);
    if (orden.estado != 'PAGADO') {
      throw ConflictException(
        'La orden $ordenId está ${orden.estado}: para emitir la factura debe '
        'estar PAGADA.',
        code: 'orden_no_pagada',
      );
    }
    // La fila oculta sigue ocupando el UNIQUE de `orden_id`: comprobar con
    // `incluirOcultas` evita una violación de integridad y da un 409 claro.
    if (await repository.findFacturaByOrden(ordenId, incluirOcultas: true) !=
        null) {
      throw ConflictException(
        'La orden $ordenId ya tiene una factura.',
        code: 'factura_duplicada',
      );
    }

    return repository.insertFactura(
      Factura(
        id: 0,
        fechaFactura: DateTime.now().toUtc(),
        empleadoId: empleadoId ?? orden.empleadoId,
        clienteId: clienteId ?? orden.clienteId,
        ordenId: ordenId,
        subtotal: orden.total,
        rebaja: orden.rebaja,
        iva: orden.iva,
        estado: 'EMITIDA',
        fechaCreacion: DateTime.now().toUtc(),
        fechaActualizacion: DateTime.now().toUtc(),
      ),
    );
  }

  /// Cambia el estado de la factura (`EMITIDA` <-> `ANULADA`).
  Future<Factura> cambiarEstado(int id, String estado) async {
    final actual = await obtener(id);
    final nuevo = ensureEstado(estado, estadosFacturas, 'estado');
    if (nuevo == actual.estado) return actual;
    return repository.updateEstadoFactura(id, nuevo);
  }

  /// Elimina la factura. En contabilidad lo correcto es anularla, por eso
  /// solo se permite borrar una factura ya `ANULADA`.
  Future<void> eliminar(int id) async {
    final factura = await obtener(id);
    if (factura.estado != 'ANULADA') {
      throw const ConflictException(
        'Solo se puede eliminar una factura ANULADA: anúlala primero con '
        'PUT /api/v1/facturas/{id}/estado.',
        code: 'factura_emitida',
      );
    }
    final removed = await repository.deleteFactura(id);
    if (!removed) {
      throw NotFoundException(
        'La factura $id no existe.',
        code: 'factura_no_encontrada',
      );
    }
  }
}
