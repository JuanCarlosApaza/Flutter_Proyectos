import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/usecases/rol_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de roles (RBAC):
///
/// * `GET    /api/v1/roles`        -> catálogo con sus permisos
/// * `GET    /api/v1/roles/{id}`
/// * `POST   /api/v1/roles`        -> crea un rol con sus permisos
/// * `PUT    /api/v1/roles/{id}`   -> nombre/descripción/estado/permisos
/// * `DELETE /api/v1/roles/{id}`   -> borrado lógico
///
/// Leer exige `usuarios.ver` (lo necesita el desplegable de la ficha de
/// usuario); escribir exige `usuarios.editar`. El rol ADMIN no se modifica y
/// los de sistema no se borran (reglas en `domain/usecases/rol_usecases.dart`).
void addRolRoutes(Router router, {required Roles roles}) {
  router
    ..get('/api/v1/roles', (Request request) async {
      asegurarPermiso(request, 'usuarios', 'ver');
      final page = paginationOf(request);
      final items = await roles.listar(
        limit: page.limit,
        offset: page.offset,
        estado: queryOrNull(request, 'estado'),
      );
      return listJsonResponse(items.map((e) => e.toJson()).toList());
    })
    ..get('/api/v1/roles/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'usuarios', 'ver');
      final item = await roles.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/roles', (Request request) async {
      asegurarPermiso(request, 'usuarios', 'editar');
      final body = await readJsonObject(request);
      final item = await roles.crear(
        nombre: requireText(body, 'nombre', maxLength: 50),
        descripcion: textOrNull(body, 'descripcion', maxLength: 255),
        permisos: _permisos(body) ?? const <String>{},
      );
      detalleAuditoria(request, {
        'nombre': item.nombre,
        'permisos': [...item.permisos]..sort(),
      });
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/roles/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'usuarios', 'editar');
      final body = await readJsonObject(request);
      final campos = camposEnviados(body, const [
        'nombre',
        'descripcion',
        'estado',
        'permisos',
      ]);
      ensureHayCampos(campos);
      // Estado ANTES del cambio: si la operación falla (p. ej. el rol ADMIN
      // no se puede tocar), la auditoría conserva los permisos previos.
      final antes = await roles.obtener(pathId(id));
      detalleAuditoria(request, {
        'nombre': antes.nombre,
        'permisosAntes': [...antes.permisos]..sort(),
      });
      final item = await roles.actualizar(
        pathId(id),
        nombre: campos.contains('nombre')
            ? requireText(body, 'nombre', maxLength: 50)
            : null,
        // `''` en el body limpia la descripción (lo traduce el caso de uso).
        descripcion: campos.contains('descripcion')
            ? textOrNull(body, 'descripcion', maxLength: 255) ?? ''
            : null,
        estado: campos.contains('estado') ? textOrNull(body, 'estado') : null,
        permisos: campos.contains('permisos') ? _permisos(body) : null,
      );
      detalleAuditoria(request, {
        'nombre': item.nombre,
        'permisosDespues': [...item.permisos]..sort(),
        'estado': item.estado,
      });
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/roles/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'usuarios', 'eliminar');
      final antes = await roles.obtener(pathId(id));
      detalleAuditoria(request, {'nombre': antes.nombre});
      await roles.eliminar(pathId(id));
      return noContent();
    });
}

/// Lee `permisos: ["productos.ver", ...]`; `null` si el campo no viene.
Set<String>? _permisos(Map<String, Object?> body) {
  if (!body.containsKey('permisos')) return null;
  final raw = body['permisos'];
  if (raw is! List) {
    throw const BadRequestException(
      'El campo "permisos" debe ser una lista de "modulo.accion".',
      code: 'permisos_invalidos',
    );
  }
  for (final elemento in raw) {
    if (elemento is! String) {
      throw const BadRequestException(
        'Cada permiso debe ser una cadena "modulo.accion".',
        code: 'permisos_invalidos',
      );
    }
  }
  return {for (final elemento in raw) elemento as String};
}
