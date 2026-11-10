import 'usuario.dart';

/// Sesión de acceso abierta por el login.
///
/// El [token] es un valor aleatorio generado por la capa `data` y guardado en
/// la tabla `sesiones`; el cliente lo envía en `Authorization: Bearer <token>`.
/// [usuario] es la cuenta dueña de la sesión (se rellena al validarla) y es
/// lo único que viaja en las respuestas: la contraseña nunca sale de la API.
final class Sesion {
  const Sesion({
    required this.token,
    required this.usuarioId,
    required this.expiraEn,
    this.usuario,
  });

  final String token;
  final int usuarioId;

  /// Instante (UTC) en el que la sesión deja de ser válida.
  final DateTime expiraEn;

  /// Cuenta dueña de la sesión; `null` hasta que se valida contra la BD.
  final Usuario? usuario;

  bool get caducada => expiraEn.toUtc().isBefore(DateTime.now().toUtc());

  Sesion conUsuario(Usuario valor) => Sesion(
    token: token,
    usuarioId: usuarioId,
    expiraEn: expiraEn,
    usuario: valor,
  );

  Map<String, Object?> toJson() => {
    'token': token,
    'expiraEn': expiraEn.toUtc().toIso8601String(),
    'usuario': usuario?.toJson(),
  };
}
