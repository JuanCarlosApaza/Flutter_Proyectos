/// Usuario de acceso (cuenta de login) tal y como la devuelve la API.
///
/// La contraseña **nunca** llega en las respuestas: solo existe en la
/// petición de login.
final class Usuario {
  const Usuario({
    required this.id,
    required this.nombreUsuario,
    required this.nivelUsuario,
    this.rolId = 0,
    this.permisos = const [],
    this.empleadoId,
    this.estado = 'ACTIVO',
  });

  factory Usuario.fromJson(Map<String, dynamic> json) => Usuario(
    id: (json['id'] as num?)?.toInt() ?? 0,
    nombreUsuario: json['nombreUsuario']?.toString() ?? '',
    nivelUsuario: json['nivelUsuario']?.toString() ?? '',
    rolId: (json['rolId'] as num?)?.toInt() ?? 0,
    permisos: [
      for (final p in (json['permisos'] as List?) ?? const []) p.toString(),
    ],
    empleadoId: (json['empleadoId'] as num?)?.toInt(),
    estado: json['estado']?.toString() ?? 'ACTIVO',
  );

  final int id;

  /// Nombre de login.
  final String nombreUsuario;

  /// Nombre del rol al que pertenece (`ADMIN`, `CAJERO`, `VENDEDOR`...).
  final String nivelUsuario;

  /// Rol asignado (`Roles.Rol_ID` de la API).
  final int rolId;

  /// Permisos del rol en formato `modulo.accion` (`productos.editar`).
  ///
  /// Vacío en sesiones guardadas antes del sistema de permisos: `GET /auth/me`
  /// los refresca al arrancar la app.
  final List<String> permisos;

  final int? empleadoId;

  final String estado;

  /// ¿Tiene el permiso `modulo.accion`? (`accion` por defecto: `ver`).
  bool puede(String modulo, [String accion = 'ver']) =>
      permisos.contains('$modulo.$accion');

  /// Iniciales para el avatar del sidebar (`CA` de "Cajero Ana"...).
  String get iniciales {
    final partes = nombreUsuario
        .split(RegExp(r'[._\-\s]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    return partes.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'nombreUsuario': nombreUsuario,
    'nivelUsuario': nivelUsuario,
    'rolId': rolId,
    'permisos': permisos,
    'empleadoId': empleadoId,
    'estado': estado,
  };
}
