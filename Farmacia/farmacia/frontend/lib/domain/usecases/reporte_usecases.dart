import '../entities/reporte.dart';
import '../repositories/reporte_repository.dart';

/// Caso de uso: ranking de productos vendidos para los gráficos del dashboard.
///
/// El servidor hace el `GROUP BY`; el frontend solo pide el trozo que pinta.
final class Reportes {
  const Reportes({required this.repository});

  final ReporteRepository repository;

  /// Ranking de productos por unidades vendidas.
  Future<List<VentaProducto>> productosVendidos({
    int limite = 6,
    String orden = 'desc',
  }) => repository.ventasPorProducto(limite: limite, orden: orden);
}
