/// Marcas de la tienda (catálogo de marcas de producto).
///
/// Dominio puro: sin SQL, sin HTTP, sin dependencias externas. Su `toJson()`
/// *es* el contrato JSON de la API.
library;

/// Marca del catálogo (`Samsung`, `Nike`...). El producto puede llevar marca
/// o no (`productos.marca_id` nullable): es solo texto — columna visible en
/// la tabla de productos, filtro del listado, búsqueda libre y, **únicamente
/// en el Recibo 1**, una línea del recibo de la orden. En la Boleta (Recibo 2)
/// no se imprime.
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
