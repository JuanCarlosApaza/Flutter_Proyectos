/// Marcas de ropa (`Nike`, `Adidas`...).
///
/// Dominio puro: sin SQL, sin HTTP, sin dependencias externas. Cada entidad
/// expone su `toJson()` porque ese objeto *es* el contrato JSON de la API.
library;

/// Agrupación opcional de productos por marca de fabricación.
///
/// La marca es anulable en el producto: una prenda puede no tenerla.
final class Marca {
  const Marca({
    required this.id,
    required this.nombre,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final String nombre;

  /// Valor del enum `estado_general` (`ACTIVO`, `INACTIVO`, `BLOQUEADO`).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
