import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../models/health_status_model.dart';

/// Fuente de datos remota: endpoint `/api/v1/health`.
///
/// Traduce la respuesta HTTP a modelos; cualquier error se lanza como
/// [Failure].
class HealthRemoteDataSource {
  HealthRemoteDataSource(this._client);

  final ApiClient _client;

  Future<HealthStatusModel> fetchStatus() async {
    final body = await _client.get('/api/v1/health');
    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return HealthStatusModel.fromJson(body);
  }
}
