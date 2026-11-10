import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/entities/usuario.dart';
import '../../domain/usecases/usuario_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/auth_middleware.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de usuarios del sistema:
///
/// * `GET/POST    /api/v1/usuarios`
/// * `GET/PUT/DEL /api/v1/usuarios/{id}`
///
/// `contrasena` es un campo de solo escritura: se puede crear o cambiar con
/// él, pero **nunca** aparece en la respuesta.
///
/// El nivel de acceso ya no es texto libre: se envía `rolId` (catálogo en
/// `GET /api/v1/roles`). Toda operación exige el permiso de su acción en el
/// módulo `usuarios`, salvo el `POST` del **arranque inicial** (BD sin
/// usuarios), que sigue abierto para crear la primera cuenta.
///
/// Cambiar la contraseña en un `PUT` exige además `claveAdmin` con la clave
/// propia de quien hace la petición (la verifica el backend).
void addUsuarioRoutes(Router router, {required Usuarios usuarios}) {
  router
    ..get('/api/v1/usuarios', (Request request) async {
      asegurarPermiso(request, 'usuarios', 'ver');
      final page = paginationOf(request);
      final q = queryOrNull(request, 'q', maxLength: 100);
      final estado = queryOrNull(request, 'estado');
      final total = await usuarios.contar(estado: estado, q: q);
      final items = await usuarios.listar(
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
    ..get('/api/v1/usuarios/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'usuarios', 'ver');
      final item = await usuarios.obtener(pathId(id));
      return jsonResponse(200, item.toJson());
    })
    ..post('/api/v1/usuarios', (Request request) async {
      // `null` solo cabe sin sesión: el middleware permite esta ruta únicamente
      // cuando la BD no tiene ningún usuario (primer arranque).
      final actor = sesionOrNull(request)?.usuario;
      if (actor != null) {
        asegurarPermiso(request, 'usuarios', 'crear');
      }
      final body = await readJsonObject(request);
      // Identidad de la cuenta creada (jamás la contraseña) para la auditoría.
      detalleAuditoria(request, {
        'nombreUsuario': requireText(body, 'nombreUsuario', maxLength: 50),
        'rolId': intOrNull(body, 'rolId'),
        'empleadoId': intOrNull(body, 'empleadoId'),
      });
      final item = await usuarios.crear(
        nombreUsuario: requireText(body, 'nombreUsuario', maxLength: 50),
        contrasena: requireText(body, 'contrasena', maxLength: 255),
        rolId: intOrNull(body, 'rolId') ?? 0,
        empleadoId: intOrNull(body, 'empleadoId'),
        estado: textOrNull(body, 'estado') ?? 'ACTIVO',
        actor: actor,
      );
      return jsonResponse(201, item.toJson());
    })
    ..put('/api/v1/usuarios/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'usuarios', 'editar');
      final body = await readJsonObject(request);
      final campos = camposEnviados(body, const [
        'empleadoId',
        'rolId',
        'nombreUsuario',
        'contrasena',
        'estado',
      ]);
      ensureHayCampos(campos);
      // Estado ANTES: nombre + diff de los campos enviados. La contraseña
      // entra solo como flag (detalleRegistro excluye su valor).
      final antes = await usuarios.obtener(pathId(id));
      detalleRegistro(
        request,
        nombre: antes.nombreUsuario,
        antes: antes.toJson(),
        despues: body,
        campos: campos,
      );
      if (campos.contains('contrasena')) {
        detalleAuditoria(
          request,
          {'contrasenaCambiada': true},
          // Si SOLO cambia la contraseña, el evento es explícito.
          accion: campos.length == 1 ? 'RESTABLECER_CONTRASENA' : null,
        );
      }
      final item = await usuarios.actualizar(
        pathId(id),
        _usuario(body),
        campos,
        actor: sesionDe(request).usuario,
        claveAdmin: textOrNull(body, 'claveAdmin', maxLength: 255),
      );
      return jsonResponse(200, item.toJson());
    })
    ..delete('/api/v1/usuarios/<id>', (Request request, String id) async {
      asegurarPermiso(request, 'usuarios', 'eliminar');
      final antes = await usuarios.obtener(pathId(id));
      detalleRegistro(request, nombre: antes.nombreUsuario);
      await usuarios.eliminar(pathId(id));
      return noContent();
    });
}

Usuario _usuario(Map<String, Object?> body) => Usuario(
  id: 0,
  empleadoId: intOrNull(body, 'empleadoId'),
  rolId: intOrNull(body, 'rolId') ?? 0,
  nivelUsuario: '',
  nombreUsuario: body.containsKey('nombreUsuario')
      ? requireText(body, 'nombreUsuario', maxLength: 50)
      : '',
  contrasena: textOrNull(body, 'contrasena', maxLength: 255),
  estado: textOrNull(body, 'estado') ?? '',
  fechaCreacion: DateTime.now(),
  fechaActualizacion: DateTime.now(),
);
