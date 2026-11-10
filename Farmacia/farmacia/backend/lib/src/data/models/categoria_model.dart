import '../../domain/entities/categoria.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `categorias` y `presentaciones` a sus
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

  static Presentacion presentacion(Map<String, Object?> row) => Presentacion(
    id: RowUtils.intValue(row['presentacion_id']),
    nombre: RowUtils.text(row['nombre_presentacion']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
