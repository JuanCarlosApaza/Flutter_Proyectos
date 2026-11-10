import '../../core/errors/app_exception.dart';
import '../../domain/repositories/health_repository.dart';
import '../database/database.dart';

/// Implementación concreta del contrato [HealthRepository].
///
/// Capa `data`: es la única que sabe *cómo* se comprueba el estado
/// (aquí, haciendo ping a PostgreSQL) usando la abstracción de la BD.
final class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl(this._db);

  final DatabaseConnection _db;

  @override
  Future<bool> isDatabaseAvailable() async {
    try {
      await _db.ping();
      return true;
    } on AppException {
      return false;
    } on Exception {
      return false;
    }
  }
}
