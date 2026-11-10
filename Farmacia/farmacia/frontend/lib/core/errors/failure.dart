/// Errores de la capa `data`, traducidos a un lenguaje entendible.
///
/// El resto de la app (dominio y presentación) **nunca** ve excepciones de
/// `http` ni de JSON: solo [Failure].
sealed class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// No hay conexión o el servidor no responde.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Sin conexión con el servidor']);
}

/// El backend devolvió un error (4xx/5xx).
final class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.statusCode, this.code});

  final int? statusCode;

  /// `error.code` de la API (p. ej. `producto_desactualizado`,
  /// `stock_insuficiente`), para poder reaccionar al tipo de fallo.
  final String? code;
}

/// Respuesta inesperada: el contrato con la API cambió.
final class ParsingFailure extends Failure {
  const ParsingFailure([super.message = 'Respuesta inválida del servidor']);
}

/// Datos introducidos por el usuario que no pasan la validación local.
final class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Revisa los datos indicados']);
}
