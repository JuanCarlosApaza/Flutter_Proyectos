import '../../core/errors/app_exception.dart';
import '../entities/reporte.dart';
import '../repositories/reporte_repository.dart';

/// Casos de uso de los reportes agregados (dashboard e informes de ventas).
///
/// Reglas de negocio que aquí se aplican:
///
/// * el ranking del dashboard solo cuenta líneas de órdenes **no anuladas**
///   (`PENDIENTE` y `PAGADO`): una orden cancelada o devuelta no es venta;
/// * los **informes por rango** son más estrictos: solo cuentan las órdenes
///   `PAGADO`, porque «ventas» en un reporte es dinero que ya se cobró;
/// * `orden` acepta `'desc'` (más vendidos) o `'asc'` (menos vendidos);
/// * los límites de filas están acotados: la API nunca barrerá la tabla
///   entera por un gráfico.
final class Reportes {
  const Reportes({required this.repository});

  final ReporteRepository repository;

  /// Máximo de productos que devuelve un ranking (el dashboard pinta 6).
  static const int limiteMaximo = 50;

  /// Productos del ranking «por producto y categoría» de un rango.
  static const int limiteProductos = 500;

  /// Máximo de periodos de una serie: evita cientos de barras cuando el
  /// rango no encaja con la agrupación («un año por día» = 365 filas, ya
  /// bastante; dos = se pide agrupar por mes).
  static const int limiteGrupos = 400;

  /// Ranking de productos por unidades vendidas.
  ///
  /// * [limite]: cuántos productos se devuelven (1..[limiteMaximo]).
  /// * [orden]: `'desc'` = más vendidos, `'asc'` = menos vendidos (incluye
  ///   los que nunca se han vendido, con 0 unidades).
  /// * [porVariante]: agrupa además por talla y color.
  Future<List<VentaProducto>> productosVendidos({
    int limite = 10,
    String orden = 'desc',
    bool porVariante = false,
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
      porVariante: porVariante,
    );
  }

  /// Informe «ventas por día / mes / año» de un rango de fechas.
  ///
  /// * [desde] y [hasta] son días (`yyyy-MM-dd`), **ambos incluidos**; si
  ///   faltan, el rango es el último mes completo hasta hoy.
  /// * [agrupacion]: `'dia'`, `'mes'` o `'anio'`.
  /// * El resumen es la suma de la serie (total, órdenes, unidades y el
  ///   ticket medio), de modo que las dos cifras **siempre** cuadran.
  Future<InformeVentas> ventas({
    String? desde,
    String? hasta,
    String agrupacion = 'dia',
  }) async {
    final grupo = _agrupacion(agrupacion);
    final rango = _rangoFechas(desde, hasta);
    _asegurarGrupos(rango.desde, rango.hasta, grupo);

    final serie = await repository.ventasPorPeriodo(
      desde: rango.desde,
      hasta: rango.hasta,
      agrupacion: grupo,
    );

    var total = 0.0;
    var unidades = 0.0;
    var ordenes = 0;
    for (final fila in serie) {
      total += fila.total;
      unidades += fila.unidades;
      ordenes += fila.ordenes;
    }

    return InformeVentas(
      desde: _textoFecha(rango.desde),
      hasta: _textoFecha(rango.hasta),
      agrupacion: grupo,
      resumen: ResumenVentas(
        total: total,
        ordenes: ordenes,
        unidades: unidades,
      ),
      serie: serie,
    );
  }

  /// Informe «ventas por producto y categoría» del mismo rango.
  ///
  /// Las dos consultas salen en paralelo (una sola ida y vuelta de red).
  Future<InformeProductos> productosDelRango({
    String? desde,
    String? hasta,
  }) async {
    final rango = _rangoFechas(desde, hasta);
    final productos = repository.productosVendidosEnRango(
      desde: rango.desde,
      hasta: rango.hasta,
      limite: limiteProductos,
    );
    final categorias = repository.categoriasVendidas(
      desde: rango.desde,
      hasta: rango.hasta,
    );
    return InformeProductos(
      productos: await productos,
      categorias: await categorias,
    );
  }

  /// `dia` | `mes` | `anio`; cualquier otra cosa es un `400`.
  static String _agrupacion(String? texto) {
    final valor = (texto ?? 'dia').trim().toLowerCase();
    return switch (valor) {
      'dia' || 'día' => 'dia',
      'mes' => 'mes',
      'anio' || 'año' => 'anio',
      _ => throw const BadRequestException(
        'El parámetro "agrupacion" debe ser "dia", "mes" o "anio".',
        code: 'agrupacion_invalida',
      ),
    };
  }

  /// Rango `[desde, hasta]` como días: vacío → último mes hasta hoy;
  /// formato o coherencia malos → `400`.
  static ({DateTime desde, DateTime hasta}) _rangoFechas(
    String? desde,
    String? hasta,
  ) {
    final fin = hasta == null || hasta.trim().isEmpty
        ? DateTime.now()
        : _dia(hasta);
    final inicio = desde == null || desde.trim().isEmpty
        ? DateTime(fin.year, fin.month, fin.day - 29)
        : _dia(desde);

    if (inicio.isAfter(fin)) {
      throw const BadRequestException(
        'El rango no es válido: la fecha "desde" es posterior a la "hasta".',
        code: 'rango_invalido',
      );
    }
    return (desde: inicio, hasta: fin);
  }

  /// Rechaza rangos que pedirían más de [limiteGrupos] filas de serie,
  /// sugiriendo la agrupación que sí cabe.
  static void _asegurarGrupos(DateTime desde, DateTime hasta, String grupo) {
    final grupos = switch (grupo) {
      'mes' => (hasta.year - desde.year) * 12 + (hasta.month - desde.month) + 1,
      'anio' => hasta.year - desde.year + 1,
      _ => hasta.difference(desde).inDays + 1,
    };
    if (grupos <= limiteGrupos) return;
    throw BadRequestException(
      'El rango abarca $grupos periodos de "$grupo" y el máximo es '
      '$limiteGrupos: usa una agrupación mayor.',
      code: 'rango_demasiado_grande',
    );
  }

  /// `yyyy-MM-dd` → día entero; inválido → `400 fecha_invalida`.
  static DateTime _dia(String texto) {
    final limpio = texto.trim();
    final fecha = DateTime.tryParse(limpio);
    if (fecha == null) {
      throw BadRequestException(
        'La fecha "$limpio" no es válida (formato yyyy-MM-dd).',
        code: 'fecha_invalida',
      );
    }
    return DateTime(fecha.year, fecha.month, fecha.day);
  }

  /// Día → `yyyy-MM-dd` (el formato que entiende la API).
  static String _textoFecha(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}
