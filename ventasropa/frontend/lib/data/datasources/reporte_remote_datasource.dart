import '../../core/errors/failure.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/reporte.dart';
import '../../domain/repositories/reporte_repository.dart';

/// Fuente de datos remota: `GET /api/v1/reportes/productos-vendidos`.
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
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    final body = await _client.get(
      '/api/v1/reportes/ventas',
      query: {'desde': _dia(desde), 'hasta': _dia(hasta), 'agrupacion': agrupacion},
    );

    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return InformeVentas.fromJson(body);
  }

  @override
  Future<InformeProductos> ventasPorProductoYCategoria({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final body = await _client.get(
      '/api/v1/reportes/ventas-productos',
      query: {'desde': _dia(desde), 'hasta': _dia(hasta)},
    );

    if (body is! Map<String, dynamic>) throw const ParsingFailure();
    return InformeProductos.fromJson(body);
  }

  /// Día → `yyyy-MM-dd` (el formato que entiende la API).
  String _dia(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}
