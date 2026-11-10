import '../entities/health_status.dart';
import '../repositories/health_repository.dart';

/// Caso de uso: obtener el estado de salud de la API.
///
/// Los casos de uso encapsulan la lógica de negocio. Aquí compone la
/// información del repositorio con los datos del servicio.
final class GetHealthStatus {
  const GetHealthStatus({
    required this.repository,
    required this.serviceName,
    required this.version,
  });

  final HealthRepository repository;
  final String serviceName;
  final String version;

  Future<HealthStatus> call() async {
    final databaseConnected = await repository.isDatabaseAvailable();
    return HealthStatus(
      service: serviceName,
      version: version,
      databaseConnected: databaseConnected,
      checkedAt: DateTime.now(),
    );
  }
}
