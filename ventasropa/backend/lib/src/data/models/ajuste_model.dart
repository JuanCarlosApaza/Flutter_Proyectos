import '../../domain/entities/ajuste.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `ajustes` a la entidad de dominio.
final class AjusteModel {
  const AjusteModel._();

  static Ajuste fila(Map<String, Object?> row) => Ajuste(
    id: RowUtils.intValue(row['id']),
    clave: RowUtils.text(row['clave']),
    valor: RowUtils.text(row['valor']),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
