import '../../domain/entities/marca.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `marcas` a su entidad de dominio.
final class MarcaModel {
  const MarcaModel._();

  static Marca marca(Map<String, Object?> row) => Marca(
    id: RowUtils.intValue(row['marca_id']),
    nombre: RowUtils.text(row['nombre_marca']),
    // Los enums propios se seleccionan con `::text` para llegar como String.
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
