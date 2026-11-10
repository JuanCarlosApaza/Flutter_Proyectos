import '../entities/reporte.dart';

/// Contrato (puerto) de los reportes agregados del dashboard.
///
/// El dominio **solo** conoce esta interfaz: la implementación concreta vive en
/// `data/`. Estos datos no son un CRUD —no se piden filas, se piden **cifras
/// agregadas**— por eso no pasan por `VentaRepository`.
abstract interface class ReporteRepository {
  /// Ranking de productos por unidades vendidas.
  ///
  /// * [descendente] `true` → de más a menos vendido (top);
  ///   `false` → de menos a más, incluidos los que **nunca** se han vendido.
  /// * [limite] cuántos productos devuelve.
  Future<List<VentaProducto>> ventasPorProducto({
    required int limite,
    required bool descendente,
  });
}
