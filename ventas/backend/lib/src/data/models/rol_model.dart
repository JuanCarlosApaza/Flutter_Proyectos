import '../../domain/entities/rol.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `roles` a la entidad [Rol].
///
/// `permisos` no viene en la fila: lo carga el repositorio con
/// [Rol.conPermisos] a partir de `rol_permisos`.
final class RolModel {
  const RolModel._();

  static Rol rol(Map<String, Object?> row) => Rol(
    id: RowUtils.intValue(row['rol_id']),
    nombre: RowUtils.text(row['nombre']),
    descripcion: RowUtils.textOrNull(row['descripcion']),
    esSistema: RowUtils.boolValue(row['es_sistema']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['creado_en']),
    fechaActualizacion: RowUtils.dateTime(row['actualizado_en']),
  );
}
