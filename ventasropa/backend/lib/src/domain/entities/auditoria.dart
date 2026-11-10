/// Evento de la auditoría: quién hizo qué, cuándo, desde dónde y con qué
/// resultado.
///
/// `usuarioId`/`nombreUsuario`/`rol` son **instantáneas** de la cuenta en ese
/// momento (la fila no depende de que la cuenta siga existiendo). `detalles`
/// solo lo rellenan explícitamente las rutas sensibles y nunca contiene
/// contraseñas ni tokens (la capa que lo captura sanea las claves prohibidas).
library;

final class AuditoriaEvento {
  const AuditoriaEvento({
    this.id = 0,
    required this.fecha,
    this.usuarioId,
    this.nombreUsuario,
    this.rol,
    required this.accion,
    this.exitoso = true,
    this.codigoError,
    this.entidad,
    this.entidadId,
    required this.resumen,
    this.detalles,
    this.ip,
  });

  final int id;
  final DateTime fecha;

  /// Cuenta que ejecutó la operación (`null` en operaciones sin sesión:
  /// login o el primer arranque).
  final int? usuarioId;
  final String? nombreUsuario;
  final String? rol;

  /// `LOGIN`, `LOGIN_FALLIDO`, `LOGOUT`, `CREAR`, `ACTUALIZAR`, `ELIMINAR`,
  /// `RESTABLECER_CONTRASENA`...
  final String accion;

  /// `false` cuando la operación fue rechazada (403/400/401...): los
  /// intentos denegados también son auditoría.
  final bool exitoso;
  final String? codigoError;

  final String? entidad;
  final int? entidadId;

  /// Resumen legible de la petición, p. ej. `PUT /api/v1/usuarios/27 -> 200`.
  final String resumen;

  /// Detalle explícito aportado por la ruta (antes/después, campos...).
  final Map<String, Object?>? detalles;

  final String? ip;

  Map<String, Object?> toJson() => {
    'id': id,
    'fecha': fecha.toUtc().toIso8601String(),
    'usuarioId': usuarioId,
    'nombreUsuario': nombreUsuario,
    'rol': rol,
    'accion': accion,
    'exitoso': exitoso,
    'codigoError': codigoError,
    'entidad': entidad,
    'entidadId': entidadId,
    'resumen': resumen,
    'detalles': detalles,
    'ip': ip,
  };
}
