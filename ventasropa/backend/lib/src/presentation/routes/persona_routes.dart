import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/entities/persona.dart';
import '../../domain/usecases/persona_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de personas:
///
/// * `/api/v1/clientes`, `/api/v1/proveedores`, `/api/v1/empleados`
///   con `GET` (lista), `GET {id}`, `POST`, `PUT {id}` y `DELETE {id}`.
///
/// `PUT` es una **actualización parcial**: solo se modifican los campos que
/// aparecen en el cuerpo (`null` borra el valor, campo ausente no se toca).
void addPersonaRoutes(
  Router router, {
  required Clientes clientes,
  required Proveedores proveedores,
  required Empleados empleados,
}) {
  router
    // --- Clientes --------------------------------------------------------
    ..get('/api/v1/clientes', (Request request) async {
      asegurarPermiso(request, 'clientes', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await clientes.contar(estado: estado, q: q);
      final items = await clientes.listar(
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
    ..get('/api/v1/clientes/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'clientes', 'ver');
      final item = await clientes.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/clientes', (Request request) async {
      asegurarPermiso(request, 'clientes', 'crear');
      final body = await readJsonObject(request);
      detalleRegistro(request, nombre: body['nombre']?.toString());
      final item = await clientes.crear(
        nombre: requireText(body, 'nombre', maxLength: 150),
        apellido: requireText(body, 'apellido', maxLength: 100),
        direccion: textOrNull(body, 'direccion', maxLength: 200),
        ciudad: textOrNull(body, 'ciudad', maxLength: 100),
        genero: textOrNull(body, 'genero', maxLength: 1),
        ci: requireText(body, 'ci', maxLength: 15),
        telefono: textOrNull(body, 'telefono', maxLength: 20),
        estado: textOrNull(body, 'estado') ?? 'ACTIVO',
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/clientes/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'clientes', 'editar');
      final body = await readJsonObject(request);
      final campos = camposEnviados(body, const [
        'nombre',
        'apellido',
        'direccion',
        'ciudad',
        'genero',
        'ci',
        'telefono',
        'estado',
      ]);
      ensureHayCampos(campos);
      final antes = await clientes.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.nombre,
        antes: antes.toJson(),
        despues: body,
        campos: campos,
      );
      final item = await clientes.actualizar(
        pathId(id),
        _cliente(body),
        campos,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/clientes/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'clientes', 'eliminar');
      final antes = await clientes.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.nombre);
      await clientes.eliminar(pathId(id));
      return noContent();
    })
    // --- Proveedores -----------------------------------------------------
    ..get('/api/v1/proveedores', (Request request) async {
      asegurarPermiso(request, 'proveedores', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await proveedores.contar(estado: estado, q: q);
      final items = await proveedores.listar(
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
    ..get('/api/v1/proveedores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'proveedores', 'ver');
      final item = await proveedores.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/proveedores', (Request request) async {
      asegurarPermiso(request, 'proveedores', 'crear');
      final body = await readJsonObject(request);
      detalleRegistro(request, nombre: body['nombre']?.toString());
      final item = await proveedores.crear(
        nombre: requireText(body, 'nombre', maxLength: 150),
        direccion: textOrNull(body, 'direccion', maxLength: 200),
        ciudad: textOrNull(body, 'ciudad', maxLength: 100),
        telefono: textOrNull(body, 'telefono', maxLength: 20),
        email: textOrNull(body, 'email', maxLength: 150),
        nit: textOrNull(body, 'nit', maxLength: 20),
        estado: textOrNull(body, 'estado') ?? 'ACTIVO',
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/proveedores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'proveedores', 'editar');
      final body = await readJsonObject(request);
      final campos = camposEnviados(body, const [
        'nombre',
        'direccion',
        'ciudad',
        'telefono',
        'email',
        'nit',
        'estado',
      ]);
      ensureHayCampos(campos);
      final antes = await proveedores.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.nombre,
        antes: antes.toJson(),
        despues: body,
        campos: campos,
      );
      final item = await proveedores.actualizar(
        pathId(id),
        _proveedor(body),
        campos,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/proveedores/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'proveedores', 'eliminar');
      final antes = await proveedores.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.nombre);
      await proveedores.eliminar(pathId(id));
      return noContent();
    })
    // --- Empleados -------------------------------------------------------
    ..get('/api/v1/empleados', (Request request) async {
      asegurarPermiso(request, 'empleados', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await empleados.contar(estado: estado, q: q);
      final items = await empleados.listar(
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
    ..get('/api/v1/empleados/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'empleados', 'ver');
      final item = await empleados.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/empleados', (Request request) async {
      asegurarPermiso(request, 'empleados', 'crear');
      final body = await readJsonObject(request);
      detalleRegistro(request, nombre: body['nombre']?.toString());
      final item = await empleados.crear(
        nombre: requireText(body, 'nombre', maxLength: 150),
        apellido: requireText(body, 'apellido', maxLength: 100),
        direccion: textOrNull(body, 'direccion', maxLength: 200),
        ciudad: textOrNull(body, 'ciudad', maxLength: 100),
        edad: intOrNull(body, 'edad'),
        telefono: textOrNull(body, 'telefono', maxLength: 20),
        estado: textOrNull(body, 'estado') ?? 'ACTIVO',
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/empleados/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'empleados', 'editar');
      final body = await readJsonObject(request);
      final campos = camposEnviados(body, const [
        'nombre',
        'apellido',
        'direccion',
        'ciudad',
        'edad',
        'telefono',
        'estado',
      ]);
      ensureHayCampos(campos);
      final antes = await empleados.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.nombre,
        antes: antes.toJson(),
        despues: body,
        campos: campos,
      );
      final item = await empleados.actualizar(
        pathId(id),
        _empleado(body),
        campos,
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/empleados/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'empleados', 'eliminar');
      final antes = await empleados.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.nombre);
      await empleados.eliminar(pathId(id));
      return noContent();
    });
}

// --- Lectura de cuerpos (solo forma; el dominio valida las reglas) -----------

Cliente _cliente(Map<String, Object?> body) => Cliente(
  id: 0,
  nombre: body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: 150)
      : '',
  apellido: textOrNull(body, 'apellido', maxLength: 100),
  direccion: textOrNull(body, 'direccion', maxLength: 200),
  ciudad: textOrNull(body, 'ciudad', maxLength: 100),
  genero: textOrNull(body, 'genero', maxLength: 1),
  ci: textOrNull(body, 'ci', maxLength: 15),
  telefono: textOrNull(body, 'telefono', maxLength: 20),
  estado: textOrNull(body, 'estado') ?? '',
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);

Proveedor _proveedor(Map<String, Object?> body) => Proveedor(
  id: 0,
  nombre: body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: 150)
      : '',
  direccion: textOrNull(body, 'direccion', maxLength: 200),
  ciudad: textOrNull(body, 'ciudad', maxLength: 100),
  telefono: textOrNull(body, 'telefono', maxLength: 20),
  email: textOrNull(body, 'email', maxLength: 150),
  nit: textOrNull(body, 'nit', maxLength: 20),
  estado: textOrNull(body, 'estado') ?? '',
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);

Empleado _empleado(Map<String, Object?> body) => Empleado(
  id: 0,
  nombre: body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: 150)
      : '',
  apellido: textOrNull(body, 'apellido', maxLength: 100),
  direccion: textOrNull(body, 'direccion', maxLength: 200),
  ciudad: textOrNull(body, 'ciudad', maxLength: 100),
  edad: intOrNull(body, 'edad'),
  telefono: textOrNull(body, 'telefono', maxLength: 20),
  estado: textOrNull(body, 'estado') ?? '',
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);
