import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/marca_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas del catálogo de marcas:
///
/// * `GET/POST    /api/v1/marcas`
/// * `GET/PUT/DEL /api/v1/marcas/{id}`
///
/// Las marcas son la pestaña «Marcas» de la página de Categorías, así que
/// reutilizan los permisos del módulo `categorias`: `categorias.ver/crear/
/// editar/eliminar`. No hay módulo RBAC propio.
///
/// Las rutas solo traducen HTTP <-> casos de uso: nunca hacen SQL ni
/// contienen reglas de negocio.
void addMarcaRoutes(Router router, {required Marcas marcas}) {
  router
    ..get('/api/v1/marcas', (Request request) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await marcas.contar(estado: estado, q: q);
      final items = await marcas.listar(
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
    ..get('/api/v1/marcas/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final item = await marcas.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/marcas', (Request request) async {
      asegurarPermiso(request, 'categorias', 'crear');
      final body = await readJsonObject(request);
      final fields = readNombreEstado(body, maxNombre: 50);
      detalleRegistro(request, nombre: fields.nombre);
      final item = await marcas.crear(
        nombre: fields.nombre,
        estado: fields.estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/marcas/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'editar');
      final body = await readJsonObject(request);
      final fields = readNombreEstadoParcial(body, maxNombre: 50);
      final antes = await marcas.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.toJson()['nombre']?.toString(),
        antes: antes.toJson(),
        despues: body,
        campos: camposEnviados(body, const ['nombre', 'estado']),
      );
      final item = await marcas.actualizar(
        pathId(id),
        nombre: fields.nombre,
        estado: fields.estado,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/marcas/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'eliminar');
      final antes = await marcas.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await marcas.eliminar(pathId(id));
      return noContent();
    });
}
