import '../../core/errors/app_exception.dart';
import '../entities/sesion.dart';
import '../repositories/sesion_repository.dart';
import '../repositories/usuario_repository.dart';
import '../rules/contrasenas.dart';

/// Casos de uso de autenticación: login, validación de sesión y logout.
///
/// Reglas de sesión:
///
/// * `recuerdame = true`  → la sesión dura [duracionRecordada] (30 días) y el
///   cliente puede persistirla para entrar sin volver a escribir nada.
/// * `recuerdame = false` → la sesión dura [duracionCorta] (24 h).
/// * Cerrar la sesión borra la fila en la BD: el token deja de servir **en el
///   servidor**, no solo en el dispositivo.
final class Autenticar {
  const Autenticar({required this.usuarios, required this.sesiones});

  final UsuarioRepository usuarios;
  final SesionRepository sesiones;

  /// Validez de una sesión pedida sin "recordarme".
  static const Duration duracionCorta = Duration(hours: 24);

  /// Validez de una sesión pedida con "recordarme".
  static const Duration duracionRecordada = Duration(days: 30);

  /// Valida credenciales y abre una sesión.
  ///
  /// Lanza `401` con el **mismo** mensaje para usuario inexistente y para
  /// contraseña incorrecta (no se revela cuál de los dos falló).
  ///
  /// La contraseña se compara contra el hash **bcrypt** guardado en la BD.
  /// Si una cuenta sigue con la contraseña en texto plano (legado que no
  /// pasó por el backfill de arranque) y la clave es correcta, se re-hashea
  /// al vuelo para que no vuelva a quedar texto claro.
  Future<Sesion> iniciarSesion({
    required String nombreUsuario,
    required String contrasena,
    bool recuerdame = false,
  }) async {
    var usuario = await usuarios.findByNombreUsuario(nombreUsuario.trim());

    if (usuario == null ||
        !verificarContrasena(
          guardada: usuario.contrasena ?? '',
          recibida: contrasena,
        )) {
      throw const UnauthorizedException(
        'Usuario o contraseña incorrectos.',
        code: 'credenciales_invalidas',
      );
    }
    if (usuario.estado != 'ACTIVO') {
      throw ForbiddenException(
        'La cuenta está ${usuario.estado.toLowerCase()}: contacta con el '
        'administrador.',
        code: 'cuenta_inactiva',
      );
    }

    // Cuenta legada en texto plano → se guarda ya hasheada (si cabe en
    // bcrypt: una clave de más de 72 bytes se queda legada para no romper
    // su login; el backfill la omite por el mismo motivo).
    if (usuario.contrasena != null &&
        !esHashBcrypt(usuario.contrasena!) &&
        cabeEnBcrypt(contrasena)) {
      final hasheada = hashContrasena(contrasena);
      await usuarios.update(usuario.id, usuario.conContrasena(hasheada), {
        'contrasena',
      });
      usuario = usuario.conContrasena(hasheada);
    }

    await sesiones.deleteExpired();

    final duracion = recuerdame ? duracionRecordada : duracionCorta;
    final abierta = await sesiones.insert(
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(duracion),
    );
    return abierta.conUsuario(usuario);
  }

  /// Devuelve la sesión válida asociada a [token] (con su usuario).
  ///
  /// Lanza `401` si el token no existe, ya caducó o su cuenta ya no existe, y
  /// `403` si la cuenta dejó de estar activa.
  Future<Sesion> validarSesion(String token) async {
    final limpia = token.trim();
    if (limpia.isEmpty) {
      throw const UnauthorizedException(
        'Se requiere iniciar sesión.',
        code: 'sesion_requerida',
      );
    }

    final sesion = await sesiones.findByToken(limpia);
    if (sesion == null) {
      throw const UnauthorizedException(
        'La sesión ya no es válida: vuelve a iniciar sesión.',
        code: 'sesion_invalida',
      );
    }
    if (sesion.caducada) {
      await sesiones.delete(limpia);
      throw const UnauthorizedException(
        'La sesión expiró: vuelve a iniciar sesión.',
        code: 'sesion_expirada',
      );
    }

    final usuario = await usuarios.findById(sesion.usuarioId);
    if (usuario == null) {
      await sesiones.delete(limpia);
      throw const UnauthorizedException(
        'La cuenta de la sesión ya no existe.',
        code: 'usuario_inexistente',
      );
    }
    if (usuario.estado != 'ACTIVO') {
      throw ForbiddenException(
        'La cuenta está ${usuario.estado.toLowerCase()}.',
        code: 'cuenta_inactiva',
      );
    }
    return sesion.conUsuario(usuario);
  }

  /// Cierra la sesión del token indicado (idempotente).
  Future<void> cerrarSesion(String token) => sesiones.delete(token);
}
