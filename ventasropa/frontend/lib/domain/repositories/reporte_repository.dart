import '../entities/reporte.dart';

/// Contrato que el dominio exige a la capa de datos.
///
/// Implementado por `data/datasources/reporte_remote_datasource.dart`; en
/// tests se sustituye por un doble en memoria.
abstract interface class ReporteRepository {
  /// Ranking de productos por unidades vendidas.
  ///
  /// * [limite]: cuántos productos devuelve (el dashboard pinta 6).
  /// * [orden]: `'desc'` = más vendidos; `'asc'` = menos vendidos (incluye
  ///   los que nunca se han vendido, con 0 unidades).
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  });

  /// Informe «ventas por día / mes / año» del rango `[desde, hasta]`
  /// (ambos días incluidos).
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  });

  /// Informe «ventas por producto y categoría» del mismo rango.
  Future<InformeProductos> ventasPorProductoYCategoria({
    required DateTime desde,
    required DateTime hasta,
  });
}
