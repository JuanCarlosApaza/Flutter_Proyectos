import '../../domain/entities/health_status.dart';
import '../../core/errors/failure.dart';

/// Adapta el JSON de `/api/v1/health` a la entidad [HealthStatus].
final class HealthStatusModel {
  const HealthStatusModel._(this._json);

  final Map<String, dynamic> _json;

  factory HealthStatusModel.fromJson(Map<String, dynamic> json) {
    final database = json['database'];
    final checkedAt = DateTime.tryParse(json['checkedAt']?.toString() ?? '');
    if (database is! String || checkedAt == null) {
      throw const ParsingFailure();
    }
    return HealthStatusModel._({
      'service': json['service']?.toString() ?? 'desconocido',
      'version': json['version']?.toString() ?? '-',
      'database': database,
      'checkedAt': checkedAt,
    });
  }

  HealthStatus toEntity() => HealthStatus(
    service: _json['service']! as String,
    version: _json['version']! as String,
    databaseConnected: _json['database'] == 'up',
    checkedAt: _json['checkedAt']! as DateTime,
  );
}
