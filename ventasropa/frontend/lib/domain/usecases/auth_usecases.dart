import '../../core/errors/failure.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// Casos de uso de autenticación (login, restauración y cierre de sesión).
///
/// Un caso de uso por operación, como el resto de la capa `domain`: valida lo
/// justo y delega en el repositorio, sin conocer HTTP ni almacenamiento.
final class Autenticacion {
  const Autenticacion({required this.repository});

  final AuthRepository repository;

  /// Inicia sesión; lanza [Failure] si la API rechaza las credenciales.
  Future<Sesion> iniciar({
    required String usuario,
    required String contrasena,
    required bool recuerdame,
  }) {
    final nombre = usuario.trim();
    if (nombre.isEmpty || contrasena.isEmpty) {
      throw const ValidationFailure('Indica usuario y contraseña.');
    }
    return repository.iniciarSesion(
      nombreUsuario: nombre,
      contrasena: contrasena,
      recuerdame: recuerdame,
    );
  }

  /// Restaura la sesión persistida (`null` si no hay o ya no vale).
  Future<Sesion?> restaurar() => repository.restaurarSesion();

  /// Cierra la sesión en el servidor y limpia el dispositivo.
  Future<void> cerrar({
    bool invalidarEnServidor = true,
    bool olvidarCredenciales = true,
  }) => repository.cerrarSesion(
    invalidarEnServidor: invalidarEnServidor,
    olvidarCredenciales: olvidarCredenciales,
  );

  /// Usuario/contraseña guardados por el check "Recordarme".
  Future<Credenciales?> credenciales() => repository.credencialesGuardadas();
}
