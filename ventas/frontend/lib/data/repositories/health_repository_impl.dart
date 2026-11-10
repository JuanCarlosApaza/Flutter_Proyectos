import '../../domain/entities/health_status.dart';
import '../../domain/repositories/health_repository.dart';
import '../datasources/health_remote_datasource.dart';

/// Implementación del contrato [HealthRepository] contra la API real.
final class HealthRepositoryImpl implements HealthRepository {
  HealthRepositoryImpl(this._dataSource);

  final HealthRemoteDataSource _dataSource;

  @override
  Future<HealthStatus> getStatus() async {
    final model = await _dataSource.fetchStatus();
    return model.toEntity();
  }
}
