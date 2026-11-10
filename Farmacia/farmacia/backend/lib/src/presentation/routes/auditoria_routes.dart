import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/auditoria_usecases.dart';
import '../http/api_request.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de la auditoría de cambios:
///
/// * `GET    /api/v1/auditoria`                  → eventos (más recientes
///   primero) con filtros opcionales `usuario` (parcial), `desde`/`hasta`
///   (`yyyy-MM-dd`, el día `hasta` está incluido), `entidad`, `accion` y
///   `q` (búsqueda libre sobre toda la fila).
/// * `DELETE /api/v1/auditoria/antes-de/{fecha}` → borra los anteriores a la
///   fecha y devuelve `{"eliminados": N}`.
/// * `DELETE /api/v1/auditoria/todo`             → vacía la tabla.
///
/// Leer exige `auditoria.ver`; purgar, `auditoria.eliminar`. La purga es
/// ella misma una mutación: el wrapper de auditoría registra quién la hizo
/// DESPUÉS del borrado, así que su evento siempre queda.
void addAuditoriaRoutes(Router router, {required Auditorias auditorias}) {
  router
    ..get('/api/v1/auditoria', (Request request) async {
      asegurarPermiso(request, 'auditoria', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final usuario = queryOrNull(request, 'usuario');
      final desde = queryOrNull(request, 'desde');
      final hasta = queryOrNull(request, 'hasta');
      final entidad = queryOrNull(request, 'entidad');
      final accion = queryOrNull(request, 'accion');
      final total = await auditorias.contar(
        usuario: usuario,
        desde: desde,
        hasta: hasta,
        entidad: entidad,
        accion: accion,
        q: q,
      );
      final items = await auditorias.listar(
        limit: page.limit,
        offset: page.offset,
        usuario: usuario,
        desde: desde,
        hasta: hasta,
        entidad: entidad,
        accion: accion,
        q: q,
      );
      return listJsonResponse(
        items.map((e) => e.toJson()).toList(),
        total: total,
        limit: page.limit,
        offset: page.offset,
      );
    })
    ..delete('/api/v1/auditoria/antes-de/<fecha>', (
      Request request,
      String fecha,
    ) async {
      asegurarPermiso(request, 'auditoria', 'eliminar');
      final eliminados = await auditorias.limpiar(fecha);
      return jsonResponse(200, {'eliminados': eliminados});
    })
    ..delete('/api/v1/auditoria/todo', (Request request) async {
      asegurarPermiso(request, 'auditoria', 'eliminar');
      final eliminados = await auditorias.limpiarTodo();
      return jsonResponse(200, {'eliminados': eliminados});
    });
}
