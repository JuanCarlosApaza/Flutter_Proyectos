/// Un respaldo de la base de datos generado con `pg_dump`.
///
/// Dominio puro: describe el fichero que ya está en disco (nombre, tamaño y
/// cuándo se escribió). Su `toJson()` es el contrato JSON de la API.
library;

final class Respaldo {
  const Respaldo({
    required this.nombre,
    required this.bytes,
    required this.creado,
  });

  /// Nombre del fichero dentro de la carpeta de respaldos.
  final String nombre;

  /// Tamaño en bytes.
  final int bytes;

  /// Cuándo se escribió el fichero.
  final DateTime creado;

  Map<String, Object?> toJson() => {
    'nombre': nombre,
    'bytes': bytes,
    'creado': creado.toUtc().toIso8601String(),
  };
}
