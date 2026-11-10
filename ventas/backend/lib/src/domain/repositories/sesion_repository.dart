import '../entities/sesion.dart';

/// Contrato del repositorio de sesiones (login).
///
/// El dominio define el *qué*; `data/` decide el *cómo* (tabla `sesiones`
/// en PostgreSQL, caché...). El token lo genera la implementación: el dominio
/// solo pide crear, buscar y cerrar.
abstract interface class SesionRepository {
  /// Abre una sesión que caduca en [expiraEn].
  Future<Sesion> insert({required int usuarioId, required DateTime expiraEn});

  /// Sesión asociada a [token]; `null` si no existe.
  Future<Sesion?> findByToken(String token);

  /// Cierra la sesión ([token] inexistente no es error: devuelve `false`).
  Future<bool> delete(String token);

  /// Borra las sesiones ya caducadas y devuelve cuántas se borraron.
  Future<int> deleteExpired();
}
