import '../../domain/entities/sesion.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `sesiones` a la entidad [Sesion].
final class SesionModel {
  const SesionModel._();

  static Sesion sesion(Map<String, Object?> row) => Sesion(
    token: RowUtils.text(row['token']),
    usuarioId: RowUtils.intValue(row['usuario_id']),
    expiraEn: RowUtils.dateTime(row['expira_en']),
  );
}
