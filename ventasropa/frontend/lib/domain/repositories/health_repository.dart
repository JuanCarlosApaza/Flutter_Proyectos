import '../entities/health_status.dart';

/// Contrato que el dominio exige a la capa de datos.
///
/// Implementado por `data/repositories/health_repository_impl.dart`;
/// en tests se sustituye por un doble en memoria.
abstract interface class HealthRepository {
  Future<HealthStatus> getStatus();
}
