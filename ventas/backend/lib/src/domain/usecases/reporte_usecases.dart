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

  /// Informe de ventas de un rango: resumen (KPI) + serie de periodos.
  ///
  /// * [desde] y [hasta] en `yyyy-MM-dd` (ambos incluidos);
  /// * [agrupacion] `'dia'`, `'mes'` o `'anio'`.
  ///
  /// El servidor hace el `GROUP BY` y etiqueta cada periodo en la hora local
  /// del negocio; los periodos sin ventas no se devuelven (los rellena el
  /// cliente con ceros).
  Future<InformeVentas> ventasPorRango({
    required String desde,
    required String hasta,
    String agrupacion = 'dia',
  }) {
    final grupo = switch (agrupacion.trim().toLowerCase()) {
      'dia' => 'dia',
      'mes' => 'mes',
      'anio' => 'anio',
      _ => throw const BadRequestException(
        'El parámetro "agrupacion" debe ser "dia", "mes" o "anio".',
        code: 'agrupacion_invalida',
      ),
    };
    final (inicio, fin) = _rango(desde, hasta);

    return repository.ventasPorPeriodo(
      desde: inicio,
      hasta: fin,
      agrupacion: grupo,
    );
  }

  /// Ranking de productos de un rango con su categoría + reparto por
  /// categorías. Mismas reglas de fechas que [ventasPorRango]; no agrupa.
  Future<InformeProductos> productosPorRango({
    required String desde,
    required String hasta,
  }) {
    final (inicio, fin) = _rango(desde, hasta);
    return repository.productosPorRango(desde: inicio, hasta: fin);
  }

  /// Valida el parámetro de fecha (`yyyy-MM-dd`) y lo devuelve como fecha.
  static DateTime _fecha(String texto, String campo) {
    final valor = texto.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(valor)) {
      throw BadRequestException(
        'El parámetro "$campo" debe ser una fecha en formato yyyy-MM-dd.',
        code: 'fecha_invalida',
      );
    }
    final fecha = DateTime.tryParse(valor);
    if (fecha == null) {
      throw BadRequestException(
        'El parámetro "$campo" no es una fecha válida.',
        code: 'fecha_invalida',
      );
    }
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  /// Parsea `desde`/`hasta` y comprueba que el rango no esté invertido.
  static (DateTime, DateTime) _rango(String desde, String hasta) {
    final inicio = _fecha(desde, 'desde');
    final fin = _fecha(hasta, 'hasta');
    if (inicio.isAfter(fin)) {
      throw const BadRequestException(
        'El parámetro "desde" no puede ser posterior a "hasta".',
        code: 'rango_invalido',
      );
    }
    return (inicio, fin);
  }
}
