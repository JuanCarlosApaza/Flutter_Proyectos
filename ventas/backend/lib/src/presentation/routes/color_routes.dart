import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/color_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas del catálogo de colores:
///
/// * `GET/POST    /api/v1/colores`
/// * `GET/PUT/DEL /api/v1/colores/{id}`
///
/// Los colores son la variante nueva de la página de Categorías (pestaña
/// «Colores»), así que reutilizan los permisos del módulo `categorias`:
/// `categorias.ver/crear/editar/eliminar`. No hay módulo RBAC propio.
///
/// Las rutas solo traducen HTTP <-> casos de uso: nunca hacen SQL ni
/// contienen reglas de negocio.
void addColorRoutes(Router router, {required Colores colores}) {
  router
    ..get('/api/v1/colores', (Request request) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await colores.contar(estado: estado, q: q);
      final items = await colores.listar(
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
    })
    ..get('/api/v1/colores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final item = await colores.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/colores', (Request request) async {
      asegurarPermiso(request, 'categorias', 'crear');
      final body = await readJsonObject(request);
      final fields = readColorCreacion(body);
      detalleRegistro(request, nombre: fields.nombre);
      final item = await colores.crear(
        nombre: fields.nombre,
        codigoHex: fields.codigoHex,
        estado: fields.estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/colores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'editar');
      final body = await readJsonObject(request);
      final fields = readColorParcial(body);
      final antes = await colores.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.toJson()['nombre']?.toString(),
        antes: antes.toJson(),
        despues: body,
        campos: camposEnviados(body, const ['nombre', 'codigoHex', 'estado']),
      );
      final item = await colores.actualizar(
        pathId(id),
        nombre: fields.nombre,
        codigoHex: fields.codigoHex,
        fijarCodigoHex: fields.fijarCodigoHex,
        estado: fields.estado,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/colores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'eliminar');
      final antes = await colores.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await colores.eliminar(pathId(id));
      return noContent();
    });
}
