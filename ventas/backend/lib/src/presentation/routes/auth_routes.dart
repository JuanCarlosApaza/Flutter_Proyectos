import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/usecases/auth_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/auth_middleware.dart';
import '../http/json_response.dart';
import '../http/middlewares.dart';
import '../http/rate_limit.dart';

/// Rutas de autenticación:
///
/// * `POST /api/v1/auth/login`  → pública; devuelve token + usuario
/// * `POST /api/v1/auth/logout` → exige sesión; invalida el token en la BD
/// * `GET  /api/v1/auth/me`     → exige sesión; devuelve el usuario actual
///
/// Login y logout quedan en la auditoría (LOGIN, LOGIN_FALLIDO y LOGOUT);
/// la contraseña nunca se incluye en el detalle.
///
/// El login aplica [rateLimiter] (fuerza bruta): la clave es IP + usuario,
/// los `401` cuentan y un acierto reinicia el contador.
void addAuthRoutes(
  Router router, {
  required Autenticar autenticar,
  RateLimiter? rateLimiter,
}) {
  router
    ..post('/api/v1/auth/login', (Request request) async {
      final body = await readJsonObject(request);
      final nombreUsuario = requireText(body, 'nombreUsuario', maxLength: 50);
      // La identidad intentada se anota ANTES de validar: si las credenciales
      // fallan, la auditoría conserva quién lo intentó (LOGIN_FALLIDO).
      detalleAuditoria(request, {'nombreUsuario': nombreUsuario});
      final claveLimite =
          '${ipCliente(request) ?? 'desconocida'}|'
          '${nombreUsuario.toLowerCase()}';
      rateLimiter?.verificar(claveLimite);
      try {
        final sesion = await autenticar.iniciarSesion(
          nombreUsuario: nombreUsuario,
          contrasena: requireText(body, 'contrasena', maxLength: 255),
          recuerdame: body['recuerdame'] == true,
        );
        rateLimiter?.registrarExito(claveLimite);
        detalleAuditoria(request, {'usuarioId': sesion.usuarioId});
        return jsonResponse(200, sesion.toJson());
      } on UnauthorizedException {
        rateLimiter?.registrarFallo(claveLimite);
        rethrow;
      }
    })
    ..post('/api/v1/auth/logout', (Request request) async {
      await autenticar.cerrarSesion(sesionDe(request).token);
      return jsonResponse(200, {'ok': true});
    })
    ..get('/api/v1/auth/me', (Request request) async {
      final sesion = sesionDe(request);
      final usuario = sesion.usuario;
      if (usuario == null) {
        throw const UnauthorizedException(
          'La sesión ya no es válida.',
          code: 'sesion_invalida',
        );
      }
      return jsonResponse(200, {
        'usuario': usuario.toJson(),
        'expiraEn': sesion.expiraEn.toUtc().toIso8601String(),
      });
    });
}
