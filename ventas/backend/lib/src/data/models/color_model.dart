import '../../domain/entities/color.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `colores` a su entidad de dominio.
final class ColorModel {
  const ColorModel._();

  static Color color(Map<String, Object?> row) => Color(
    id: RowUtils.intValue(row['color_id']),
    nombre: RowUtils.text(row['nombre']),
    codigoHex: RowUtils.textOrNull(row['codigo_hex']),
    // El enum propio se selecciona con `::text` para llegar como String.
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
