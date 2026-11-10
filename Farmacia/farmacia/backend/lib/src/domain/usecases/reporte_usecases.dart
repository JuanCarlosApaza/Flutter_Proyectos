import '../../core/errors/app_exception.dart';
import '../entities/reporte.dart';
import '../repositories/reporte_repository.dart';

/// Casos de uso de los reportes agregados del dashboard.
///
/// Reglas de negocio que aquí se aplican:
///
/// * el ranking solo cuenta líneas de órdenes **no anuladas**
///   (`PENDIENTE` y `PAGADO`): una orden cancelada o devuelta no es venta;
/// * `orden` acepta `'desc'` (más vendidos) o `'asc'` (menos vendidos);
/// * el límite de filas está acotado: la API nunca barrerá la tabla entera
///   por un gráfico.
final class Reportes {
  const Reportes({required this.repository});

  final ReporteRepository repository;

  /// Máximo de productos que devuelve un ranking (el dashboard pinta 6).
  static const int limiteMaximo = 50;

  /// Ranking de productos por unidades vendidas.
  ///
  /// * [limite]: cuántos productos se devuelven (1..[limiteMaximo]).
  /// * [orden]: `'desc'` = más vendidos; `'asc'` = menos vendidos (incluye
  ///   los que nunca se han vendido, con 0 unidades).
  Future<List<VentaProducto>> productosVendidos({
    int limite = 10,
    String orden = 'desc',
  }) {
    final descendente = switch (orden.trim().toLowerCase()) {
      'desc' => true,
      'asc' => false,
      _ => throw const BadRequestException(
        'El parámetro "orden" debe ser "desc" o "asc".',
        code: 'orden_invalido',
      ),
    };

    if (limite < 1 || limite > limiteMaximo) {
      throw BadRequestException(
        'El parámetro "limite" debe estar entre 1 y $limiteMaximo.',
        code: 'limite_invalido',
      );
    }

    return repository.ventasPorProducto(
      limite: limite,
      descendente: descendente,
    );
  }
}
