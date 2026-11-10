import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/cotizacion_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/auth_middleware.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de cotizaciones:
///
/// * `GET/POST    /api/v1/cotizaciones`
/// * `GET/DELETE  /api/v1/cotizaciones/{id}`
/// * `PUT         /api/v1/cotizaciones/{id}/estado`
///
/// El creador **no** viene del body: la ruta lo toma de la sesión
/// (`sesionDe(request)`), así la API registra siempre al usuario
/// autenticado, sea lo que sea que mande el cliente.
void addCotizacionRoutes(Router router, {required Cotizaciones cotizaciones}) {
  Future<Response> listar(Request request) async {
    asegurarPermiso(request, 'cotizaciones', 'ver');
    final page = paginationOf(request);
    final q = queryOrNull(request, 'q', maxLength: 100);
    final estado = queryOrNull(request, 'estado');
    final total = await cotizaciones.contar(estado: estado, q: q);
    final items = await cotizaciones.listar(
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

  Future<Response> obtener(Request request, String id) async {
    asegurarPermiso(request, 'cotizaciones', 'ver');
    final item = await cotizaciones.obtener(pathId(id));
    return jsonResponse(200, item.toJson());
  }

  Future<Response> crear(Request request) async {
    asegurarPermiso(request, 'cotizaciones', 'crear');
    final body = await readJsonObject(request);
    detalleRegistro(
      request,
      nombre: textOrNull(body, 'nombreCliente', maxLength: 150),
    );
    final item = await cotizaciones.crear(
      clienteId: intOrNull(body, 'clienteId'),
      nombreCliente: textOrNull(body, 'nombreCliente', maxLength: 150),
      // Quien la creó sale de la sesión, nunca del body.
      empleadoId: sesionDe(request).usuario?.empleadoId,
      items: itemsDesdeBody(body),
    );
    return jsonResponse(201, item.toJson());
  }

  Future<Response> cambiarEstado(Request request, String id) async {
    // Aceptar/rechazar es parte del flujo de la cotización, no una edición
    // de datos: basta con `cotizaciones.crear`.
    asegurarPermiso(request, 'cotizaciones', 'crear');
    final body = await readJsonObject(request);
    // Estado ANTES: el evento deja el cliente y la transición completa.
    final previo = (await cotizaciones.obtener(pathId(id))).toJson();
    detalleAuditoria(request, {
      if (previo['nombreCliente'] != null) 'nombre': previo['nombreCliente'],
      'estadoAntes': previo['estado'],
    });
    final item = await cotizaciones.cambiarEstado(
      pathId(id),
      requireText(body, 'estado', maxLength: 20),
    );
    detalleAuditoria(request, {'estadoDespues': item.toJson()['estado']});
    return jsonResponse(200, item.toJson());
  }

  Future<Response> eliminar(Request request, String id) async {
    asegurarPermiso(request, 'cotizaciones', 'eliminar');
    final previo = (await cotizaciones.obtener(pathId(id))).toJson();
    detalleRegistro(request, nombre: previo['nombreCliente']?.toString());
    await cotizaciones.eliminar(pathId(id));
    return noContent();
  }

  router
    ..get('/api/v1/cotizaciones', listar)
    ..get('/api/v1/cotizaciones/<id>', obtener)
    ..post('/api/v1/cotizaciones', crear)
    ..put('/api/v1/cotizaciones/<id>/estado', cambiarEstado)
    ..delete('/api/v1/cotizaciones/<id>', eliminar);
}
