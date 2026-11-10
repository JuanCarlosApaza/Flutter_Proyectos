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
  /// * [porVariante] agrupa además por variante (talla + color) y rellena
  ///   `varianteId`/`talla`/`color` de cada fila.
  Future<List<VentaProducto>> ventasPorProducto({
    required int limite,
    required bool descendente,
    bool porVariante = false,
  });

  /// Ventas **pagadas** del rango `[desde, hasta]` (ambos días incluidos)
  /// agrupadas por día, mes o año.
  ///
  /// * [agrupacion] ya está validada: `dia`, `mes` o `anio`.
  /// * Solo órdenes en estado `PAGADO`: pendientes, canceladas y devueltas
  ///   no son ventas.
  /// * La etiqueta de cada fila se calcula en **hora de Bolivia** (UTC−4),
  ///   igual que el filtro de fechas.
  Future<List<VentaPeriodo>> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  });

  /// Productos vendidos en el rango `[desde, hasta]`, de mayor a menor
  /// importe, con su categoría.
  Future<List<VentaProducto>> productosVendidosEnRango({
    required DateTime desde,
    required DateTime hasta,
    required int limite,
  });

  /// Categorías con ventas en el rango `[desde, hasta]`, de mayor a menor
  /// importe (sin límite: las categorías son un catálogo corto).
  Future<List<VentaCategoria>> categoriasVendidas({
    required DateTime desde,
    required DateTime hasta,
  });
}
