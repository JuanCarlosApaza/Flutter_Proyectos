import '../../domain/entities/categoria.dart';
import '../../domain/entities/talla.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `categorias`, `tallas` y `colores` a sus
/// entidades de dominio.
final class CategoriaModel {
  const CategoriaModel._();

  static Categoria categoria(Map<String, Object?> row) => Categoria(
    id: RowUtils.intValue(row['categoria_id']),
    nombre: RowUtils.text(row['nombre_categoria']),
    // Los enums propios se seleccionan con `::text` para llegar como String.
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );

  static Talla talla(Map<String, Object?> row) => Talla(
    id: RowUtils.intValue(row['talla_id']),
    nombre: RowUtils.text(row['nombre']),
    orden: RowUtils.intValue(row['orden']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
  );

  static ColorRopa color(Map<String, Object?> row) => ColorRopa(
    id: RowUtils.intValue(row['color_id']),
    nombre: RowUtils.text(row['nombre']),
    codigoHex: RowUtils.textOrNull(row['codigo_hex']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
  );
}
