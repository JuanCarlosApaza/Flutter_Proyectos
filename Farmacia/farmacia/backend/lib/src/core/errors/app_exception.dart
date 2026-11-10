/// Error de dominio/atención de la API.
///
/// Todas las capas lanzan estos errores; la capa HTTP los traduce a un
/// código de respuesta con el [statusCode] adecuado.
class AppException implements Exception {
  const AppException(this.message, {this.statusCode = 500, this.code});

  final String message;
  final int statusCode;

  /// Código interno estable, útil para el cliente (ej. `db_unavailable`).
  final String? code;

  @override
  String toString() =>
      'AppException($statusCode${code == null ? '' : ', $code'}): $message';
}

final class BadRequestException extends AppException {
  const BadRequestException(super.message, {super.code})
    : super(statusCode: 400);
}

final class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code}) : super(statusCode: 404);
}

final class ConflictException extends AppException {
  const ConflictException(super.message, {super.code}) : super(statusCode: 409);
}

/// Credenciales inválidas o sesión ausente/caducada.
final class UnauthorizedException extends AppException {
  const UnauthorizedException(super.message, {super.code = 'unauthorized'})
    : super(statusCode: 401);
}

/// La sesión es válida, pero el usuario no puede hacer esa operación
/// (cuenta bloqueada/inactiva o nivel de acceso insuficiente).
final class ForbiddenException extends AppException {
  const ForbiddenException(super.message, {super.code = 'forbidden'})
    : super(statusCode: 403);
}

/// Fallo de infraestructura (BD caída, timeout, red...).
final class InfrastructureException extends AppException {
  const InfrastructureException(super.message, {super.code = 'infra_error'})
    : super(statusCode: 503);
}

/// Demasiadas peticiones en poco tiempo (rate-limit, p. ej. fuerza bruta
/// contra `POST /auth/login`).
final class TooManyRequestsException extends AppException {
  const TooManyRequestsException(super.message, {super.code = 'too_many'})
    : super(statusCode: 429);
}

/// Cuerpo de la petición por encima del tamaño permitido.
final class PayloadTooLargeException extends AppException {
  const PayloadTooLargeException(super.message, {super.code = 'cuerpo_grande'})
    : super(statusCode: 413);
}
