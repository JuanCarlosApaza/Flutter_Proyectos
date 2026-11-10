import '../../domain/entities/unidad_medida.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `unidades_medida` a su entidad de
/// dominio.
final class UnidadMedidaModel {
  const UnidadMedidaModel._();

  static UnidadMedida unidad(Map<String, Object?> row) => UnidadMedida(
    id: RowUtils.intValue(row['unidad_id']),
    codigo: RowUtils.text(row['codigo']),
    nombre: RowUtils.text(row['nombre_unidad']),
    tipo: RowUtils.text(row['tipo'], fallback: 'UNIDAD'),
    decimales: RowUtils.intValue(row['decimales']),
    // Los enums propios se seleccionan con `::text` para llegar como String.
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
