import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/categoria_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de categorías, tallas, colores y marcas:
///
/// * `GET/POST    /api/v1/categorias`
/// * `GET/PUT/DEL /api/v1/categorias/{id}`
/// * `GET/POST    /api/v1/tallas`
/// * `GET/PUT/DEL /api/v1/tallas/{id}`
/// * `GET/POST    /api/v1/colores`
/// * `GET/PUT/DEL /api/v1/colores/{id}`
/// * `GET/POST    /api/v1/marcas`
/// * `GET/PUT/DEL /api/v1/marcas/{id}`
///
/// Las rutas solo traducen HTTP <-> casos de uso: nunca hacen SQL ni
/// contienen reglas de negocio.
///
/// Marcas comparte el módulo de permisos `categorias` con tallas y colores
/// (mismo criterio del catálogo: una sola pestaña de gestión).
void addCategoriaRoutes(
  Router router, {
  required Categorias categorias,
  required Tallas tallas,
  required Colores colores,
  required Marcas marcas,
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
    // --- Tallas -----------------------------------------------------------
    ..get('/api/v1/tallas', (Request request) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await tallas.contar(estado: estado, q: q);
      final items = await tallas.listar(
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
    ..get('/api/v1/tallas/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'ver');
      final item = await tallas.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/tallas', (Request request) async {
      asegurarPermiso(request, 'categorias', 'crear');
      final body = await readJsonObject(request);
      final fields = _readTalla(body);
      detalleRegistro(request, nombre: fields.nombre);
      final item = await tallas.crear(
        nombre: fields.nombre,
        orden: fields.orden,
        estado: fields.estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/tallas/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'editar');
      final body = await readJsonObject(request);
      ensureHayCampos(camposEnviados(body, const ['nombre', 'orden', 'estado']));
      final antes = await tallas.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.toJson()['nombre']?.toString(),
        antes: antes.toJson(),
        despues: body,
        campos: camposEnviados(body, const ['nombre', 'orden', 'estado']),
      );
      final item = await tallas.actualizar(
        pathId(id),
        nombre: body.containsKey('nombre')
            ? requireText(body, 'nombre', maxLength: 30)
            : null,
        orden: body.containsKey('orden') ? intOrNull(body, 'orden') : null,
        estado: textOrNull(body, 'estado'),
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/tallas/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'eliminar');
      final antes = await tallas.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await tallas.eliminar(pathId(id));
      return noContent();
    })
    // --- Colores ----------------------------------------------------------
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
      final nombre = requireText(body, 'nombre', maxLength: 50);
      final codigoHex = textOrNull(body, 'codigoHex');
      final estado = textOrNull(body, 'estado') ?? 'ACTIVO';
      detalleRegistro(request, nombre: nombre);
      final item = await colores.crear(
        nombre: nombre,
        codigoHex: codigoHex,
        estado: estado,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/colores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'editar');
      final body = await readJsonObject(request);
      ensureHayCampos(camposEnviados(body, const ['nombre', 'codigoHex', 'estado']));
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
        nombre: body.containsKey('nombre')
            ? requireText(body, 'nombre', maxLength: 50)
            : null,
        // Ausente o null = no se toca; cadena vacía = quitar el color.
        codigoHex: body.containsKey('codigoHex')
            ? textOrNull(body, 'codigoHex')
            : null,
        estado: textOrNull(body, 'estado'),
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/colores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'categorias', 'eliminar');
      final antes = await colores.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.toJson()['nombre']?.toString());
      await colores.eliminar(pathId(id));
      return noContent();
    })
    // --- Marcas -----------------------------------------------------------
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
      final fields = readNombreEstado(body, maxNombre: 100);
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
      final fields = readNombreEstadoParcial(body, maxNombre: 100);
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

/// Cuerpo de alta de talla: `nombre` (obligatorio), `orden` y `estado`.
({String nombre, int orden, String estado}) _readTalla(
  Map<String, Object?> body,
) => (
  nombre: requireText(body, 'nombre', maxLength: 30),
  orden: intOrNull(body, 'orden') ?? 0,
  estado: textOrNull(body, 'estado') ?? 'ACTIVO',
);
