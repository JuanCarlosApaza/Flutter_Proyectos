import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/categoria_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de categorías y presentaciones:
///
/// * `GET/POST    /api/v1/categorias`
/// * `GET/PUT/DEL /api/v1/categorias/{id}`
/// * `GET/POST    /api/v1/presentaciones`
/// * `GET/PUT/DEL /api/v1/presentaciones/{id}`
///
/// Las rutas solo traducen HTTP <-> casos de uso: nunca hacen SQL ni
/// contienen reglas de negocio.
void addCategoriaRoutes(
  Router router, {
  required Categorias categorias,
  required Presentaciones presentaciones,
}) {
  router
    // --- Categorías -----------------------------------------------------
    ..get('/api/v1/categorias', (Request request) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await categorias.contar(estado: estado, q: q);
      final items = await categorias.listar(
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
    ..get('/api/v1/categorias/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final item = await categorias.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/categorias', (Request request) async {
      asegurarPermiso(request, 'categorias', 'crear');
      final body = await readJsonObject(request);
      final fields = readNombreEstado(body, maxNombre: 100);
      detalleRegistro(request, nombre: fields.nombre);
      final item = await categorias.crear(
        nombre: fields.nombre,
        estado: fields.estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/categorias/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'editar');
      final body = await readJsonObject(request);
      final fields = readNombreEstadoParcial(body, maxNombre: 100);
      final antes = await categorias.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.toJson()['nombre']?.toString(),
        antes: antes.toJson(),
        despues: body,
        campos: camposEnviados(body, const ['nombre', 'estado']),
      );
      final item = await categorias.actualizar(
        pathId(id),
        nombre: fields.nombre,
        estado: fields.estado,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/categorias/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'eliminar');
      final antes = await categorias.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await categorias.eliminar(pathId(id));
      return noContent();
    })
    // --- Presentaciones --------------------------------------------------
    ..get('/api/v1/presentaciones', (Request request) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await presentaciones.contar(estado: estado, q: q);
      final items = await presentaciones.listar(
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
    ..get('/api/v1/presentaciones/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final item = await presentaciones.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/presentaciones', (Request request) async {
      asegurarPermiso(request, 'categorias', 'crear');
      final body = await readJsonObject(request);
      final fields = readNombreEstado(body, maxNombre: 100);
      detalleRegistro(request, nombre: fields.nombre);
      final item = await presentaciones.crear(
        nombre: fields.nombre,
        estado: fields.estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/presentaciones/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'editar');
      final body = await readJsonObject(request);
      final fields = readNombreEstadoParcial(body, maxNombre: 100);
      final antes = await presentaciones.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.toJson()['nombre']?.toString(),
        antes: antes.toJson(),
        despues: body,
        campos: camposEnviados(body, const ['nombre', 'estado']),
      );
      final item = await presentaciones.actualizar(
        pathId(id),
        nombre: fields.nombre,
        estado: fields.estado,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/presentaciones/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'eliminar');
      final antes = await presentaciones.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await presentaciones.eliminar(pathId(id));
      return noContent();
    });
}
