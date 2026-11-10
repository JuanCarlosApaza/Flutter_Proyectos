/// Rol de acceso: agrupa permisos (`módulo.accion`) aplicados a los usuarios.
///
/// Los roles base (`Es_Sistema = true`: ADMIN, CAJERO, VENDEDOR) se crean con
/// la migración `009_roles_permisos`; el resto se crean desde la UI.
library;

final class Rol {
  const Rol({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.esSistema = false,
    this.estado = 'ACTIVO',
    this.permisos = const {},
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final String nombre;
  final String? descripcion;

  /// Rol de la semilla: no se borra ni se renombra.
  final bool esSistema;

  /// Valor del enum `estado_general`.
  final String estado;

  /// Permisos del rol en formato `modulo.accion` (`productos.editar`).
  final Set<String> permisos;

  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  /// Copia con los permisos ya cargados.
  Rol conPermisos(Set<String> valor) => Rol(
    id: id,
    nombre: nombre,
    descripcion: descripcion,
    esSistema: esSistema,
    estado: estado,
    permisos: valor,
    fechaCreacion: fechaCreacion,
    fechaActualizacion: fechaActualizacion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'descripcion': descripcion,
    'esSistema': esSistema,
    'estado': estado,
    'permisos': [...permisos]..sort(),
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
