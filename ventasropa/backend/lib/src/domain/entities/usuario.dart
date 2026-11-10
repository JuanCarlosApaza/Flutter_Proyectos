/// Usuario de acceso al sistema (login de la tienda).
///
/// La contraseña **nunca** sale de la API: [toJson] no la incluye, solo se
/// usa internamente para persistirla.
library;

final class Usuario {
  const Usuario({
    required this.id,
    this.empleadoId,
    required this.rolId,
    required this.nivelUsuario,
    this.permisos = const {},
    required this.nombreUsuario,
    this.contrasena,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;

  /// Empleado al que está vinculado (único en la BD).
  final int? empleadoId;

  /// Rol al que pertenece (`Roles.Rol_ID`); única fuente de verdad de los
  /// niveles de acceso desde la migración `009_roles_permisos`.
  final int rolId;

  /// Nombre del rol (`ADMIN`, `CAJERO`, `VENDEDOR`...). En la API viaja como
  /// `nivelUsuario` para mantener el contrato histórico del cliente.
  final String nivelUsuario;

  /// Permisos del rol en formato `modulo.accion` (`productos.editar`).
  ///
  /// Solo se rellena al hidratar la sesión (login / `GET /auth/me`); los
  /// listados de usuarios lo dejan vacío.
  final Set<String> permisos;

  /// Nombre de login (único en la BD).
  final String nombreUsuario;

  /// Credencial de acceso: **write-only**, jamás aparece en [toJson].
  ///
  /// En la BD se guarda como hash **bcrypt** (`$2a$10$...`); el valor en
  /// claro solo existe en la petición que crea o cambia la contraseña.
  final String? contrasena;

  /// Valor del enum `estado_general`.
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  /// ¿Tiene el permiso `modulo.accion`? (`accion` por defecto: `ver`).
  bool tienePermiso(String modulo, [String accion = 'ver']) =>
      permisos.contains('$modulo.$accion');

  /// Copia con los permisos de su rol ya cargados.
  Usuario conPermisos(Set<String> valor) => Usuario(
    id: id,
    empleadoId: empleadoId,
    rolId: rolId,
    nivelUsuario: nivelUsuario,
    permisos: valor,
    nombreUsuario: nombreUsuario,
    contrasena: contrasena,
    estado: estado,
    fechaCreacion: fechaCreacion,
    fechaActualizacion: fechaActualizacion,
  );

  /// Copia con otra credencial (hash bcrypt o valor legado).
  Usuario conContrasena(String valor) => Usuario(
    id: id,
    empleadoId: empleadoId,
    rolId: rolId,
    nivelUsuario: nivelUsuario,
    permisos: permisos,
    nombreUsuario: nombreUsuario,
    contrasena: valor,
    estado: estado,
    fechaCreacion: fechaCreacion,
    fechaActualizacion: fechaActualizacion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'empleadoId': empleadoId,
    'rolId': rolId,
    'nivelUsuario': nivelUsuario,
    'nombreUsuario': nombreUsuario,
    'estado': estado,
    'permisos': [...permisos]..sort(),
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
