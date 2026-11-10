/// Estado del backend y de su conexión con la base de datos.
///
/// Modelo puro de dominio: sin dependencias de HTTP ni de Flutter.
final class HealthStatus {
  const HealthStatus({
    required this.service,
    required this.version,
    required this.databaseConnected,
    required this.checkedAt,
  });

  final String service;
  final String version;
  final bool databaseConnected;
  final DateTime checkedAt;
}
