import '../entities/reporte.dart';

/// Contrato (puerto) de los reportes agregados.
///
/// El dominio **solo** conoce esta interfaz: la implementación concreta vive en
/// `data/`. Estos datos no son un CRUD —no se piden filas, se piden **cifras
/// agregadas**— por eso no pasan por `VentaRepository`.
///
/// Aquí la agregación es SIEMPRE del servidor (`GROUP BY` en SQL): el cliente
/// recibe periodos, productos y categorías ya sumados, nunca los detalles.
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

  /// Serie de ventas agrupada por periodo dentro de un rango.
  ///
  /// * [desde] día de inicio, incluido (medianoche local, sin hora);
  /// * [hasta] día de cierre, **incluido**;
  /// * [agrupacion] `'dia'`, `'mes'` o `'anio'`.
  ///
  /// Solo cuenta órdenes **PAGADAS** y no anuladas. El servidor devuelve los
  /// periodos con ventas (el cliente rellena los huecos con ceros) y la
  /// etiqueta ya está formateada en la hora local del negocio.
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  });

  /// Ranking de productos de un rango con su categoría, más el reparto por
  /// categorías (misma regla: solo órdenes PAGADAS y no anuladas; [desde] y
  /// [hasta] incluidos).
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  });
}
