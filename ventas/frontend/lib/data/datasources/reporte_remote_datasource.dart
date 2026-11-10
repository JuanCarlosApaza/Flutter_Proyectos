import '../../core/errors/failure.dart';
import '../../core/fechas.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/reporte.dart';
import '../../domain/repositories/reporte_repository.dart';

/// Fuente de datos remota: los tres agregados de `GET /api/v1/reportes/…`.
///
/// Implementa [ReporteRepository] directamente (mismo criterio que
/// `RecursoRemoteDataSource`): la respuesta ya trae el formato de la entidad,
/// así que aquí solo se verifica la forma y se traduce cualquier error a
/// [Failure].
class ReporteRemoteDataSource implements ReporteRepository {
  ReporteRemoteDataSource(this._client);

  final ApiClient _client;

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  }) async {
    final body = await _client.get(
      '/api/v1/reportes/productos-vendidos',
      query: {'limite': '$limite', 'orden': orden},
    );

    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    final items = body['items'];
    if (items is! List) throw const ParsingFailure();

    return [
      for (final item in items.whereType<Map<String, dynamic>>())
        VentaProducto.fromJson(item),
    ];
  }

  @override
  Future<InformeVentas> ventasPorRango({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    final body = await _client.get(
      '/api/v1/reportes/ventas',
      query: {
        'desde': fechaCorta(desde),
        'hasta': fechaCorta(hasta),
        'agrupacion': agrupacion,
      },
    );

    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return InformeVentas.fromJson(body);
  }

  @override
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final body = await _client.get(
      '/api/v1/reportes/ventas-productos',
      query: {'desde': fechaCorta(desde), 'hasta': fechaCorta(hasta)},
    );

    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return InformeProductos.fromJson(body);
  }
}
