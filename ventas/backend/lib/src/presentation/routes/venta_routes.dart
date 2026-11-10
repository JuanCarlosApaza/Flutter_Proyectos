import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/venta.dart';
import '../../domain/usecases/venta_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de ventas:
///
/// * `GET/POST         /api/v1/ordenes`
/// * `GET/DELETE       /api/v1/ordenes/{id}`
/// * `PUT              /api/v1/ordenes/{id}/estado`
/// * `GET/POST         /api/v1/ordenes/{id}/detalles`
/// * `DELETE           /api/v1/ordenes/{id}/detalles/{productoId}`
/// * `GET/POST         /api/v1/facturas`
/// * `GET              /api/v1/facturas/{id}`
/// * `PUT              /api/v1/facturas/{id}/estado`
/// * `DELETE           /api/v1/facturas/{id}`  (solo si está ANULADA)
///
/// El flujo completo de venta es:
/// `POST /ordenes` (con `rebaja` y `factura`, los pagos cuadran contra
/// `totalPagar`) -> `PUT /ordenes/{id}/estado {estado: PAGADO}` ->
/// `POST /facturas {ordenId}`.
///
/// Permisos del módulo `ventas`: leer exige `ver`; **todo el flujo de venta**
/// (crear orden, mover sus líneas, marcar el pago y emitir la factura) exige
/// `crear`, de modo que un rol con solo `ver`+`crear` puede vender completo;
/// anular o eliminar exige `eliminar`.
void addVentaRoutes(
  Router router, {
  required Ordenes ordenes,
  required Facturas facturas,
}) {
  // --- Órdenes -----------------------------------------------------------
  Future<Response> listarOrdenes(Request request) async {
    asegurarPermiso(request, 'ventas', 'ver');
    final page = paginationOf(request);
    final q = queryOrNull(request, 'q', maxLength: 100);
    final estado = queryOrNull(request, 'estado');
    final total = await ordenes.contar(estado: estado, q: q);
    final items = await ordenes.listar(
      limit: page.limit,
      offset: page.offset,
      estado: estado,
      q: q,
    );
    return listJsonResponse(
      items.map((e) => e.toJson()).toList(),
      total: total,
      limit: page.limit,
      offset: page.offset,
    );
  }

  Future<Response> obtenerOrden(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'ver');
    final orden = await ordenes.obtener(pathId(id));
    final detalles = await ordenes.detallesDe(orden.id);
    return jsonResponse(200, _ordenConDetalles(orden, detalles));
  }

  Future<Response> crearOrden(Request request) async {
    asegurarPermiso(request, 'ventas', 'crear');
    final body = await readJsonObject(request);
    final orden = await ordenes.crear(
      clienteId: intOrNull(body, 'clienteId'),
      nombreCliente: textOrNull(body, 'nombreCliente', maxLength: 150),
      empleadoId: intOrNull(body, 'empleadoId'),
      rebaja: doubleOrNull(body, 'rebaja') ?? 0,
      factura: body['factura'] == true,
      pagos: _pagosDesdeBody(body),
      items: itemsDesdeBody(body),
    );
    final detalles = await ordenes.detallesDe(orden.id);
    return jsonResponse(201, _ordenConDetalles(orden, detalles));
  }

  Future<Response> cambiarEstadoOrden(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'crear');
    final body = await readJsonObject(request);
    // Estado ANTES: el evento deja el cliente y la transición (p. ej. quién
    // marcó la orden como PAGADA).
    final previo = (await ordenes.obtener(pathId(id))).toJson();
    detalleAuditoria(request, {
      if (previo['nombreCliente'] != null) 'nombre': previo['nombreCliente'],
      'estadoAntes': previo['estado'],
    });
    final orden = await ordenes.cambiarEstado(
      pathId(id),
      requireText(body, 'estado', maxLength: 20),
    );
    detalleAuditoria(request, {'estadoDespues': orden.toJson()['estado']});
    return jsonResponse(200, orden.toJson());
  }

  Future<Response> eliminarOrden(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'eliminar');
    await ordenes.eliminar(pathId(id));
    return noContent();
  }

  // --- Detalles -----------------------------------------------------------
  Future<Response> listarDetalles(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'ver');
    final items = await ordenes.detallesDe(pathId(id));
    return listJsonResponse(items.map((e) => e.toJson()).toList());
  }

  Future<Response> agregarDetalle(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'crear');
    final body = await readJsonObject(request);
    final detalle = await ordenes.agregarItem(
      pathId(id),
      productoId:
          intOrNull(body, 'productoId') ??
          (throw const BadRequestException(
            'El campo "productoId" es obligatorio.',
            code: 'field_required',
          )),
      cantidad:
          doubleOrNull(body, 'cantidad') ??
          (throw const BadRequestException(
            'El campo "cantidad" es obligatorio.',
            code: 'field_required',
          )),
      // Pista de variante: por id de variante, por color del catálogo o por
      // nombre; sin ninguna y con una sola variante viva, se usa esa.
      varianteId: intOrNull(body, 'varianteId'),
      colorId: intOrNull(body, 'colorId'),
      color: textOrNull(body, 'color', maxLength: 50),
    );
    return jsonResponse(201, detalle.toJson());
  }

  Future<Response> quitarDetalle(
    Request request,
    String id,
    String productoId,
  ) async {
    asegurarPermiso(request, 'ventas', 'crear');
    // `?varianteId=` quita solo ese color; sin él, todas las líneas del
    // producto en la orden.
    await ordenes.quitarItem(
      pathId(id),
      pathId(productoId),
      varianteId: intOrNull(request.url.queryParameters, 'varianteId'),
    );
    return noContent();
  }

  // --- Facturas ------------------------------------------------------------
  Future<Response> listarFacturas(Request request) async {
    asegurarPermiso(request, 'ventas', 'ver');
    final page = paginationOf(request);
    final q = queryOrNull(request, 'q', maxLength: 100);
    final estado = queryOrNull(request, 'estado');
    final total = await facturas.contar(estado: estado, q: q);
    final items = await facturas.listar(
      limit: page.limit,
      offset: page.offset,
      estado: estado,
      q: q,
    );
    return listJsonResponse(
      items.map((e) => e.toJson()).toList(),
      total: total,
      limit: page.limit,
      offset: page.offset,
    );
  }

  Future<Response> obtenerFactura(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'ver');
    final item = await facturas.obtener(pathId(id));
    return jsonResponse(200, item.toJson());
  }

  Future<Response> emitirFactura(Request request) async {
    asegurarPermiso(request, 'ventas', 'crear');
    final body = await readJsonObject(request);
    // La factura no pide importes: copia subtotal, rebaja e IVA ya cobrados.
    final item = await facturas.emitir(
      ordenId:
          intOrNull(body, 'ordenId') ??
          (throw const BadRequestException(
            'El campo "ordenId" es obligatorio.',
            code: 'field_required',
          )),
      empleadoId: intOrNull(body, 'empleadoId'),
      clienteId: intOrNull(body, 'clienteId'),
    );
    return jsonResponse(201, item.toJson());
  }

  Future<Response> cambiarEstadoFactura(Request request, String id) async {
    // Solo se usa para anular una factura emitida.
    asegurarPermiso(request, 'ventas', 'eliminar');
    final body = await readJsonObject(request);
    // Estado ANTES: el evento registra qué factura se anuló y desde qué estado.
    final previo = (await facturas.obtener(pathId(id))).toJson();
    detalleAuditoria(request, {'estadoAntes': previo['estado']});
    final item = await facturas.cambiarEstado(
      pathId(id),
      requireText(body, 'estado', maxLength: 20),
    );
    detalleAuditoria(request, {'estadoDespues': item.toJson()['estado']});
    return jsonResponse(200, item.toJson());
  }

  Future<Response> eliminarFactura(Request request, String id) async {
    asegurarPermiso(request, 'ventas', 'eliminar');
    await facturas.eliminar(pathId(id));
    return noContent();
  }

  router
    ..get('/api/v1/ordenes', listarOrdenes)
    ..get('/api/v1/ordenes/<id>', obtenerOrden)
    ..post('/api/v1/ordenes', crearOrden)
    ..put('/api/v1/ordenes/<id>/estado', cambiarEstadoOrden)
    ..delete('/api/v1/ordenes/<id>', eliminarOrden)
    ..get('/api/v1/ordenes/<id>/detalles', listarDetalles)
    ..post('/api/v1/ordenes/<id>/detalles', agregarDetalle)
    ..delete('/api/v1/ordenes/<id>/detalles/<productoId>', quitarDetalle)
    ..get('/api/v1/facturas', listarFacturas)
    ..get('/api/v1/facturas/<id>', obtenerFactura)
    ..post('/api/v1/facturas', emitirFactura)
    ..put('/api/v1/facturas/<id>/estado', cambiarEstadoFactura)
    ..delete('/api/v1/facturas/<id>', eliminarFactura);
}

// --- Ayudantes ----------------------------------------------------------------

Map<String, Object?> _ordenConDetalles(
  OrdenPedido orden,
  List<DetalleOrden> detalles,
) => {...orden.toJson(), 'detalles': detalles.map((d) => d.toJson()).toList()};

/// Lee `pagos: [{metodoPago, monto, referencia?}, ...]` del cuerpo de una
/// orden. La validación fina (método permitido, cuadre con el total) la hace
/// el caso de uso; aquí solo se exige la forma.
List<Pago> _pagosDesdeBody(Map<String, Object?> body) {
  final raw = body['pagos'];
  if (raw is! List || raw.isEmpty) {
    throw const BadRequestException(
      'El campo "pagos" debe ser una lista no vacía de '
      '{metodoPago, monto, referencia}.',
      code: 'pagos_invalidos',
    );
  }
  final ahora = DateTime.now().toUtc();
  final pagos = <Pago>[];
  for (final element in raw) {
    if (element is! Map) {
      throw const BadRequestException(
        'Cada pago debe ser un objeto con "metodoPago" y "monto".',
        code: 'pago_invalido',
      );
    }
    final item = element.cast<String, Object?>();
    final monto =
        doubleOrNull(item, 'monto') ??
        (throw const BadRequestException(
          'Cada pago necesita "monto".',
          code: 'monto_requerido',
        ));
    pagos.add(
      Pago(
        metodoPago: requireText(item, 'metodoPago', maxLength: 50),
        monto: monto,
        referencia: textOrNull(item, 'referencia', maxLength: 100),
        fechaCreacion: ahora,
        fechaActualizacion: ahora,
      ),
    );
  }
  return pagos;
}
