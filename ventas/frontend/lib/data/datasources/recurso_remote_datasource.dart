import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/recurso.dart';
import '../../domain/repositories/recurso_repository.dart';

/// Fuente de datos remota de los recursos de `/api/v1`.
class RecursoRemoteDataSource implements RecursoRepository {
  RecursoRemoteDataSource(this._client);

  final ApiClient _client;

  static const _prefijo = '/api/v1/';

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    // Ojo: `Uri.replace(queryParameters:)` sustituye la query entera, por eso
    // los filtros viajan en este mapa y no embebidos en la ruta.
    final body = await _client.get(
      '$_prefijo$recurso',
      query: {
        ...?filtros,
        'limit': '$limit',
        'offset': '$offset',
        if (estado != null && estado.isNotEmpty) 'estado': estado,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );

    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    final items = body['items'];
    if (items is! List) throw const ParsingFailure();

    return ListadoRecurso(
      total: (body['total'] as num?)?.toInt() ?? items.length,
      items: [
        for (final item in items.whereType<Map<String, dynamic>>())
          Recurso.fromJson(item),
      ],
    );
  }

  @override
  Future<Recurso> obtener(String ruta) async {
    final response = await _client.get('$_prefijo$ruta');
    return _comoRecurso(response);
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    final response = await _client.post('$_prefijo$ruta', body: body);
    return _comoRecurso(response);
  }

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) async {
    final response = await _client.put('$_prefijo$ruta', body: body);
    return _comoRecurso(response);
  }

  @override
  Future<void> eliminar(String ruta) async {
    await _client.delete('$_prefijo$ruta');
  }

  Recurso _comoRecurso(Object response) {
    if (response is! Map<String, dynamic>) throw const ParsingFailure();
    return Recurso.fromJson(response);
  }
}
