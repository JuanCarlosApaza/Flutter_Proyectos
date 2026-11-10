import '../entities/reporte.dart';
import '../repositories/reporte_repository.dart';

/// Casos de uso de los reportes: rankings del dashboard e informes de la
/// pantalla «Reportes».
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

  /// Informe «ventas por día / mes / año» del rango `[desde, hasta]`.
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) => repository.ventasPorPeriodo(
    desde: desde,
    hasta: hasta,
    agrupacion: agrupacion,
  );

  /// Informe «ventas por producto y categoría» del rango.
  Future<InformeProductos> ventasPorProductoYCategoria({
    required DateTime desde,
    required DateTime hasta,
  }) => repository.ventasPorProductoYCategoria(desde: desde, hasta: hasta);
}
