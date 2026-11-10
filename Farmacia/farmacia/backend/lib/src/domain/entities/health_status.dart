/// Estado de la API y de su conexión con la base de datos.
///
/// Los modelos de dominio son puros: no importan Flutter, HTTP ni SQL.
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

  Map<String, Object?> toJson() => {
    'service': service,
    'version': version,
    'database': databaseConnected ? 'up' : 'down',
    'checkedAt': checkedAt.toUtc().toIso8601String(),
  };
}
