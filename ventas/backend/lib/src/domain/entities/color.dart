/// Colores de la tienda (catálogo de variantes de producto).
///
/// Dominio puro: sin SQL, sin HTTP, sin dependencias externas. Su `toJson()`
/// *es* el contrato JSON de la API.
library;

/// Color del catálogo (`Rojo`, `Azul`...). Cada producto vende sus
/// variantes atadas a un color; el nombre que queda en la variante es el
/// **congelado** del alta, de modo que renombrar el color aquí no reescribe
/// el histórico de ventas.
final class Color {
  const Color({
    required this.id,
    required this.nombre,
    this.codigoHex,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final String nombre;

  /// Muestra `#RRGGBB` para el chip de la UI; `null` si no se definió (el
  /// frontend entonces pinta un chip neutro). No se imprime en recibos.
  final String? codigoHex;

  /// Valor del enum `estado_general` (`ACTIVO`, `INACTIVO`, `BLOQUEADO`).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'codigoHex': codigoHex,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
