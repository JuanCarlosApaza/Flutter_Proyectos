/// Personas y empresas que intervienen en la farmacia.
///
/// Dominio puro: sin SQL, sin HTTP. El `toJson()` de cada entidad es el
/// contrato JSON que expone la API.
library;

/// Cliente de la farmacia (persona física).
final class Cliente {
  const Cliente({
    required this.id,
    required this.nombre,
    this.apellido,
    this.direccion,
    this.ciudad,
    this.genero,
    this.ci,
    this.telefono,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final String nombre;

  /// Apellido: **obligatorio** en altas y ediciones (2-100). Los registros
  /// antiguos lo traen en `null` y la app muestra entonces solo el nombre.
  final String? apellido;

  final String? direccion;
  final String? ciudad;

  /// `M`, `F` u `O` (enum de negocio, columna `CHAR(1)`).
  final String? genero;

  /// El CI (Cédula de Identidad boliviano) es único en la BD.
  final String? ci;
  final String? telefono;

  /// Valor del enum `estado_general`.
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'apellido': apellido,
    'direccion': direccion,
    'ciudad': ciudad,
    'genero': genero,
    'ci': ci,
    'telefono': telefono,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}

/// Proveedor de la farmacia.
final class Proveedor {
  const Proveedor({
    required this.id,
    required this.nombre,
    this.direccion,
    this.ciudad,
    this.telefono,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final String nombre;
  final String? direccion;
  final String? ciudad;
  final String? telefono;

  /// Valor del enum `estado_general`.
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'direccion': direccion,
    'ciudad': ciudad,
    'telefono': telefono,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}

/// Empleado de la farmacia (vendedor, administrador...).
final class Empleado {
  const Empleado({
    required this.id,
    required this.nombre,
    this.apellido,
    this.direccion,
    this.ciudad,
    this.rol,
    this.permisos = const [],
    this.edad,
    this.telefono,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final String nombre;

  /// Apellido: igual que en [Cliente.apellido] (obligatorio en la API).
  final String? apellido;

  final String? direccion;
  final String? ciudad;

  /// Nombre del rol de la cuenta vinculada (`usuarios.empleado_id` →
  /// `roles`); `null` cuando el empleado no tiene usuario o su cuenta no
  /// está activa. Es **solo lectura**: se gestiona en el módulo Usuarios.
  final String? rol;

  /// Permisos `modulo.accion` de ese rol (vacío sin cuenta vinculada).
  final List<String> permisos;

  final int? edad;
  final String? telefono;

  /// Valor del enum `estado_empleado`
  /// (`ACTIVO`, `VACACIONES`, `LICENCIA`, `INACTIVO`).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'apellido': apellido,
    'direccion': direccion,
    'ciudad': ciudad,
    'rol': rol,
    'permisos': [...permisos]..sort(),
    'edad': edad,
    'telefono': telefono,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
