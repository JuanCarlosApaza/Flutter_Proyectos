import 'package:shelf/shelf.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/usecases/auth_usecases.dart';

/// Rutas que **no** exigen sesión (coincidencia exacta).
///
/// * `/` y `/api/v1/health` → comprobar que la API vive sin entrar.
/// * `/api/v1/network`      → el QR de acceso móvil.
/// * `/api/v1/auth/login`   → el propio inicio de sesión.
/// * `/docs`, `/openapi.json` → documentación (solo desarrollo).
const Set<String> rutasPublicas = {
  '/',
  '/api/v1/health',
  '/api/v1/network',
  '/api/v1/auth/login',
  '/docs',
  '/openapi.json',
};

/// Prefijos públicos **solo en GET**: `/docs/*` (assets de Swagger) y las
/// imágenes subidas.
///
/// Las imágenes se sirven en etiquetas `<img src="…">`, que **no** pueden
/// llevar cabeceras `Authorization`, así que su lectura queda abierta (solo
/// hay ficheros que la propia app subió). Cualquier otra petición sobre
/// esos prefijos —en particular `POST /api/v1/archivos/imagenes`— **sí**
/// exige sesión: subir un fichero es una mutación y el frontend ya manda
/// el token.
const List<String> prefijosPublicos = ['/docs', '/api/v1/archivos/'];

/// Ruta de creación de usuarios: se permite sin sesión únicamente cuando la
/// BD todavía no tiene **ningún** usuario (primer arranque de la aplicación).
const String rutaPrimerUsuario = '/api/v1/usuarios';

/// Ruta de activación de la suscripción: la clave maestra es la
/// autorización, así que funciona **sin sesión** (también desde la pantalla
/// de bloqueo, donde aún no se ha entrado).
const String rutaSuscripcion = '/api/v1/ajustes/suscripcion';

Middleware autenticar({
  required Autenticar autenticar,
  Future<bool> Function()? sinUsuarios,
  Future<bool> Function()? suscripcion,
}) =>
    (Handler innerHandler) => (Request request) async {
      final ruta = request.requestedUri.path;

      if (rutasPublicas.contains(ruta) ||
          (request.method == 'GET' && prefijosPublicos.any(ruta.startsWith)) ||
          (ruta == rutaSuscripcion && request.method == 'PUT') ||
          (request.method == 'POST' &&
              ruta == rutaPrimerUsuario &&
              sinUsuarios != null &&
              await sinUsuarios())) {
        return innerHandler(request);
      }

      // Lanza 401/403 si el token falta, caducó o la cuenta está inactiva;
      // `errorHandler` (middleware externo) lo traduce a la respuesta JSON.
      final sesion = await autenticar.validarSesion(_tokenDe(request) ?? '');

      // Suscripción activa (si nunca se activó, [suscripcion] dice true):
      // con la fecha trucada o vencida, todo queda bloqueado salvo la propia
      // ruta de reactivación y el cierre de sesión.
      if (suscripcion != null &&
          ruta != rutaSuscripcion &&
          ruta != '/api/v1/auth/logout' &&
          !await suscripcion()) {
        throw const ForbiddenException(
          'La suscripción de este sistema está vencida o la fecha del '
          'sistema es incorrecta: contacta con el programador.',
          code: 'suscripcion_vencida',
        );
      }

      return innerHandler(request.change(context: {'sesion': sesion}));
    };

/// Token enviado en `Authorization: Bearer <token>` (`null` si no lo hay).
String? _tokenDe(Request request) {
  final cabecera = request.headers['authorization'] ?? '';
  final espacios = cabecera.indexOf(' ');
  if (espacios < 0) return null;
  if (cabecera.substring(0, espacios).toLowerCase() != 'bearer') return null;
  final token = cabecera.substring(espacios + 1).trim();
  return token.isEmpty ? null : token;
}

/// Sesión validada por el middleware [autenticar] (dentro de una ruta).
///
/// Las rutas públicas no la tienen: si alguna la necesitara, lanza `401`.
Sesion sesionDe(Request request) {
  final sesion = request.context['sesion'];
  if (sesion is Sesion) return sesion;
  throw const UnauthorizedException(
    'Se requiere iniciar sesión.',
    code: 'sesion_requerida',
  );
}

/// Igual que [sesionDe] pero devuelve `null` en rutas públicas.
///
/// Solo lo necesita `POST /api/v1/usuarios` del arranque inicial (la BD sin
/// usuarios), donde aún no hay sesión que validar.
Sesion? sesionOrNull(Request request) {
  final sesion = request.context['sesion'];
  return sesion is Sesion ? sesion : null;
}
