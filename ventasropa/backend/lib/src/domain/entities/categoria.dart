/// Categorías de la tienda.
///
/// Dominio puro: sin SQL, sin HTTP, sin dependencias externas. Cada entidad
/// expone su `toJson()` porque ese objeto *es* el contrato JSON de la API.
/// Las tallas y colores viven en `entities/talla.dart`.
library;

/// Agrupación de productos (`Camisas`, `Pantalones`...).
final class Categoria {
  const Categoria({
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
