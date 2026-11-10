import '../../domain/entities/ajuste.dart';
import '../../domain/repositories/ajuste_repository.dart';
import '../database/database.dart';
import '../models/ajuste_model.dart';

/// Implementación SQL del contrato [AjusteRepository].
///
/// Solo dos sentencias, ambas con parámetros posicionales (`$1`, `$2`): los
/// valores jamás se concatenan en el SQL. Las claves que llegan ya están
/// validadas por `domain/usecases/ajuste_usecases.dart`.
final class AjusteRepositoryImpl implements AjusteRepository {
  AjusteRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columnas =
      'id, clave, valor, fecha_creacion, fecha_actualizacion';

  @override
  Future<List<Ajuste>> findAjustes({int limit = 200, int offset = 0}) async {
    final rows = await _db.query(
      'SELECT $_columnas FROM ajustes ORDER BY clave LIMIT \$1 OFFSET \$2',
      [limit, offset],
    );
    return rows.map(AjusteModel.fila).toList();
  }

  @override
  Future<void> upsertAjustes(Map<String, String> valores) async {
    await _db.runInTransaction((session) async {
      for (final ajuste in valores.entries) {
        await session.query(
          'INSERT INTO ajustes (clave, valor) VALUES (\$1, \$2) '
          'ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor',
          [ajuste.key, ajuste.value],
        );
      }
    });
  }
}
