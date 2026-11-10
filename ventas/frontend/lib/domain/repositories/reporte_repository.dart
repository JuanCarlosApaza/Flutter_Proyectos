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

  /// Informe de ventas de un rango: resumen + serie de periodos con ventas.
  ///
  /// * [desde] y [hasta]: días incluidos (`yyyy-MM-dd`);
  /// * [agrupacion]: `'dia'`, `'mes'` o `'anio'`.
  ///
  /// El servidor agrupa (`GROUP BY`) y etiqueta cada periodo en su hora
  /// local; solo manda los periodos con ventas (los huecos los rellena
  /// `InformeVentas.conHuecos`).
  Future<InformeVentas> ventasPorRango({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  });

  /// Ranking de productos del rango con su categoría + reparto por
  /// categorías (mismo rango y misma regla de órdenes que [ventasPorRango]).
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  });
}
