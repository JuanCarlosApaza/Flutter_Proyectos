import '../entities/health_status.dart';
import '../repositories/health_repository.dart';

/// Caso de uso: consultar la salud del backend.
final class GetHealthStatus {
  const GetHealthStatus({required this.repository});

  final HealthRepository repository;

  Future<HealthStatus> call() => repository.getStatus();
}
