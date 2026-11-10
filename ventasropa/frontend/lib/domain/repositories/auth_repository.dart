import '../entities/sesion.dart';

/// Usuario y contraseña marcados con el check "Recordarme".
typedef Credenciales = ({String usuario, String contrasena});

/// Contrato del repositorio de autenticación.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (API + almacenamiento
/// local del navegador o del exe). La persistencia vive aquí porque es el
/// propio repositorio el que sabe qué es una sesión y dónde se guarda.
abstract interface class AuthRepository {
  /// Abre sesión en la API.
  ///
  /// Con [recuerdame] `true` guarda token, usuario y contraseña en el
  /// dispositivo (autologin + autocompletado la próxima vez); con `false`
  /// **no** persiste nada y borra lo guardado anteriormente.
  Future<Sesion> iniciarSesion({
    required String nombreUsuario,
    required String contrasena,
    required bool recuerdame,
  });

  /// Restaura la sesión persistida, verificándola contra el servidor.
  ///
  /// Devuelve `null` si no hay nada guardado o si el servidor la rechaza
  /// (token caducado, cerrada desde otro dispositivo). Si el servidor no
  /// responde (arranque sin backend), se acepta la sesión guardada.
  Future<Sesion?> restaurarSesion();

  /// Cierra la sesión: la invalida en el servidor y borra lo guardado.
  ///
  /// * [invalidarEnServidor] = `false` cuando el propio servidor acaba de
  ///   rechazar el token (no tiene sentido volver a llamarlo).
  /// * [olvidarCredenciales] = `false` cuando la sesión caducó sola: se
  ///   borra el token pero se mantienen usuario y contraseña para poder
  ///   volver a entrar sin reescribirlos.
  Future<void> cerrarSesion({
    bool invalidarEnServidor = true,
    bool olvidarCredenciales = true,
  });

  /// Credenciales guardadas por el check "Recordarme" (`null` si no hay).
  Future<Credenciales?> credencialesGuardadas();
}
