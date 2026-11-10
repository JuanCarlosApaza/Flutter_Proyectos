import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/entities/usuario.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../datasources/sesion_local_datasource.dart';

/// Implementación del contrato [AuthRepository]: API + almacenamiento local.
///
/// Es el único sitio que sabe que una sesión = token en la API + copia en el
/// dispositivo, y el que mantiene sincronizado el token que viaja en cada
/// petición ([ApiClient.token]).
final class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remoto, this._local, this._cliente);

  final AuthRemoteDataSource _remoto;
  final SesionLocalDataSource _local;
  final ApiClient _cliente;

  @override
  Future<Sesion> iniciarSesion({
    required String nombreUsuario,
    required String contrasena,
    required bool recuerdame,
  }) async {
    final json = await _remoto.login(
      nombreUsuario: nombreUsuario,
      contrasena: contrasena,
      recuerdame: recuerdame,
    );

    final sesion = Sesion.fromJson(json);
    final usuario = sesion.usuario;
    if (sesion.token.isEmpty || usuario == null) throw const ParsingFailure();

    _cliente.token = sesion.token;

    if (recuerdame) {
      await _local.guardarSesion(sesion);
      await _local.guardarCredenciales((
        usuario: nombreUsuario,
        contrasena: contrasena,
      ));
    } else {
      // Sin "Recordarme" no queda nada de la sesión anterior en el equipo.
      await _local.limpiarTodo();
    }
    return sesion;
  }

  @override
  Future<Sesion?> restaurarSesion() async {
    final guardada = await _local.sesion();
    if (guardada == null) return null;

    if (guardada.caducada) {
      await _local.limpiarSesion();
      return null;
    }

    // El token pasa a viajar en las peticiones desde este punto.
    _cliente.token = guardada.token;

    try {
      final me = await _remoto.me();
      final usuarioJson = me['usuario'];
      final usuario = usuarioJson is Map<String, dynamic>
          ? Usuario.fromJson(usuarioJson)
          : guardada.usuario;

      if (usuario == null) {
        await _descartar(olvidarCredenciales: false);
        return null;
      }

      final sesion = Sesion(
        token: guardada.token,
        expiraEn: guardada.expiraEn,
        usuario: usuario,
      );
      await _local.guardarSesion(sesion);
      return sesion;
    } on ServerFailure catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        // Cerrada en otro dispositivo o caducada: fuera el token, pero se
        // conservan usuario y contraseña para rellenar el formulario.
        await _descartar(olvidarCredenciales: false);
        return null;
      }
      // Error puntual del servidor: se mantiene la sesión guardada.
      return guardada;
    } on Failure {
      // Sin red / backend apagado: se acepta lo guardado (la app arranca).
      return guardada;
    }
  }

  @override
  Future<void> cerrarSesion({
    bool invalidarEnServidor = true,
    bool olvidarCredenciales = true,
  }) async {
    if (invalidarEnServidor && _cliente.token != null) {
      try {
        await _remoto.logout();
      } on Failure {
        // Servidor caído o token ya rechazado: de todas formas se limpia
        // el dispositivo, que es lo que le importa al usuario.
      }
    }
    await _descartar(olvidarCredenciales: olvidarCredenciales);
  }

  @override
  Future<Credenciales?> credencialesGuardadas() => _local.credenciales();

  /// Deja el cliente sin token y borra lo persistido en el equipo.
  Future<void> _descartar({required bool olvidarCredenciales}) async {
    _cliente.token = null;
    if (olvidarCredenciales) {
      await _local.limpiarTodo();
    } else {
      await _local.limpiarSesion();
    }
  }
}
