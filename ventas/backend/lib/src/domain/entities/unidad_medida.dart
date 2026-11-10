/// Unidades de medida en las que se vende un producto (kilogamo, unidad,
/// caja, libra...).
///
/// Dominio puro: sin SQL, sin HTTP, sin dependencias externas. Cada entidad
/// expone su `toJson()` porque ese objeto *es* el contrato JSON de la API.
library;

/// Una fila de la tabla `unidades_medida`.
final class UnidadMedida {
  const UnidadMedida({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.tipo,
    required this.decimales,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;

  /// Símbolo corto que viaja en `productos.unidad` (`KG`, `ONZA`...): 1-10
  /// caracteres alfanuméricos en mayúsculas. Es la referencia que usan los
  /// productos y las líneas ya emitidas, por eso es **inmutable**.
  final String codigo;

  /// Nombre para mostrar (`Kilogramo`).
  final String nombre;

  /// `PESO`, `VOLUMEN` o `UNIDAD` (agrupa la tabla y el desplegable).
  final String tipo;

  /// Cuántos decimales admite la cantidad en esta unidad: `KG` → 3 (gramos),
  /// `UN` → 0 (solo enteros). Va de 0 a 3, el mismo rango que las columnas
  /// `NUMERIC(12, 3)` de stock y cantidades.
  final int decimales;

  /// Valor del enum `estado_general` (`ACTIVO`, `INACTIVO`...).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Map<String, Object?> toJson() => {
    'id': id,
    'codigo': codigo,
    'nombre': nombre,
    'tipo': tipo,
    'decimales': decimales,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
