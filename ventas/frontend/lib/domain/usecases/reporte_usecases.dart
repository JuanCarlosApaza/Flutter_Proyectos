import '../entities/reporte.dart';
import '../repositories/reporte_repository.dart';

/// Caso de uso: los tres agregados de reportes (ranking del dashboard e
/// informe de la pantalla «Reportes»).
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

  /// Informe de ventas de un rango: resumen (KPI) + serie de periodos.
  Future<InformeVentas> ventasPorRango({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) => repository.ventasPorRango(
    desde: desde,
    hasta: hasta,
    agrupacion: agrupacion,
  );

  /// Ranking de productos del rango con su categoría + reparto por
  /// categorías.
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) => repository.productosPorRango(desde: desde, hasta: hasta);
}
