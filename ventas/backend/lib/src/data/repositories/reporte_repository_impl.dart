import '../../domain/entities/reporte.dart';
import '../../domain/repositories/reporte_repository.dart';
import '../../domain/rules/estados.dart';
import '../database/database.dart';
import '../database/dialecto.dart';
import '../models/row_utils.dart';

/// Implementación SQL del contrato [ReporteRepository].
///
/// Toda la agregación ocurre **en la BD** con `GROUP BY`: el backend nunca
/// manda detalles al cliente, solo periodos, productos y categorías ya
/// sumados. La tabla ya tiene los índices que hacen esto barato
/// (`idx_detalles_producto`, `idx_detalles_orden` e `idx_ordenes_fecha`).
///
/// Reglas comunes a los tres informes:
///
/// * solo órdenes **PAGADAS** y no anuladas (`o.estado = 'PAGADO'`);
/// * las líneas anuladas de una orden quedan fuera
///   (`d.estado <> 'ELIMINADO'`);
/// * el rango se recibe como fechas (Dart) y se compara contra
///   `fecha_orden`: en PostgreSQL como `TIMESTAMPTZ` (la hora local del
///   servidor, la misma que usa `to_char` para etiquetar) y en SQLite como
///   texto **en hora local** (`date(..., 'localtime')`), de modo que filtro y
///   etiqueta siempre caen en el mismo día.
final class ReporteRepositoryImpl implements ReporteRepository {
  ReporteRepositoryImpl(this._db);

  final DatabaseConnection _db;

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    required int limite,
    required bool descendente,
  }) async {
    // Los nombres de tabla/columna y los literal de estado son constantes del
    // código: `orden` llega traducido a `desc`/`asc` desde el caso de uso, y
    // el único parámetro dinámico va por marcador posicionales ($1).
    final filas = await _db.query(
      'SELECT p.producto_id, '
      'p.nombre_producto AS nombre, '
      'COALESCE(SUM(d.cantidad), 0) AS unidades, '
      'COALESCE(SUM(d.monto_total), 0) AS monto '
      'FROM productos p '
      'LEFT JOIN detalles_ordenes_pedidos d '
      'ON d.producto_id = p.producto_id '
      "AND d.estado <> '$estadoEliminado' "
      // Solo cuenta si la orden que lo incluye sigue viva (no cancelada ni
      // devuelta): `PENDIENTE` o `PAGADO`.
      'AND EXISTS (SELECT 1 FROM ordenes_pedidos o '
      'WHERE o.orden_id = d.orden_id '
      "AND o.estado IN ('PENDIENTE', 'PAGADO')) "
      "WHERE p.estado <> '$estadoEliminado' "
      'GROUP BY p.producto_id, p.nombre_producto '
      // El alias de salida `unidades` se puede usar en ORDER BY y no admite
      // inyección: es un nombre fijo de esta consulta.
      'ORDER BY unidades ${descendente ? 'DESC' : 'ASC'}, p.nombre_producto ASC '
      'LIMIT \$1',
      [limite],
    );

    return [
      for (final fila in filas)
        VentaProducto(
          productoId: RowUtils.intValue(fila['producto_id']),
          nombre: RowUtils.text(fila['nombre']),
          unidades: RowUtils.doubleValue(fila['unidades']),
          monto: RowUtils.doubleValue(fila['monto']),
        ),
    ];
  }

  @override
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    final filas = await _db.query(_sqlPeriodos(agrupacion), [
      desde,
      _diaSiguiente(hasta),
    ]);

    final serie = [
      for (final fila in filas)
        PeriodoVenta(
          etiqueta: RowUtils.text(fila['periodo']),
          ordenes: RowUtils.intValue(fila['ordenes']),
          total: RowUtils.doubleValue(fila['total']),
          unidades: RowUtils.doubleValue(fila['unidades']),
          utilidad: RowUtils.doubleValue(fila['utilidad']),
        ),
    ];
    // El resumen sale de sumar la propia serie: así los KPI de la pantalla y
    // la fila «Total del rango» son la misma cifra por construcción.
    return InformeVentas.resumiendo(serie);
  }

  @override
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final fin = _diaSiguiente(hasta);
    final rango = _condicionRango('o.fecha_orden');

    final productos = await _db.query(
      'SELECT p.producto_id AS producto_id, '
      'p.nombre_producto AS nombre, '
      'c.nombre_categoria AS categoria, '
      'COALESCE(SUM(d.cantidad), 0) AS unidades, '
      'COALESCE(SUM(d.monto_total), 0) AS monto '
      'FROM detalles_ordenes_pedidos d '
      'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
      'JOIN productos p ON p.producto_id = d.producto_id '
      'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
      "WHERE o.estado = 'PAGADO' "
      "AND d.estado <> '$estadoEliminado' "
      'AND $rango '
      'GROUP BY p.producto_id, p.nombre_producto, c.nombre_categoria '
      'ORDER BY monto DESC, unidades DESC, p.nombre_producto ASC '
      // Red de seguridad: un rango amplio no puede vaciar la BD en el
      // cliente. La tabla de la pantalla muestra todo lo que llega.
      'LIMIT \$3',
      [desde, fin, _topeProductos],
    );

    final categorias = await _db.query(
      'SELECT c.nombre_categoria AS nombre, '
      'COALESCE(SUM(d.cantidad), 0) AS unidades, '
      'COALESCE(SUM(d.monto_total), 0) AS monto '
      'FROM detalles_ordenes_pedidos d '
      'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
      'LEFT JOIN productos p ON p.producto_id = d.producto_id '
      'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
      "WHERE o.estado = 'PAGADO' "
      "AND d.estado <> '$estadoEliminado' "
      'AND $rango '
      'GROUP BY c.nombre_categoria '
      'ORDER BY monto DESC',
      [desde, fin],
    );

    return InformeProductos(
      productos: [
        for (final fila in productos)
          ProductoRango(
            productoId: RowUtils.intValue(fila['producto_id']),
            nombre: RowUtils.text(fila['nombre']),
            unidades: RowUtils.doubleValue(fila['unidades']),
            monto: RowUtils.doubleValue(fila['monto']),
            categoria: RowUtils.textOrNull(fila['categoria']),
          ),
      ],
      categorias: [
        for (final fila in categorias)
          VentaCategoria(
            nombre: RowUtils.textOrNull(fila['nombre']),
            monto: RowUtils.doubleValue(fila['monto']),
            unidades: RowUtils.doubleValue(fila['unidades']),
          ),
      ],
    );
  }

  /// Tope de filas del ranking de productos (margen muy por encima de lo que
  /// una pantalla puede mostrar).
  static const int _topeProductos = 500;

  /// Día siguiente al último incluido: el rango se cierra con `<`, así que
  /// `hasta` es inclusivo para quien lo llama y exclusivo para el SQL.
  static DateTime _diaSiguiente(DateTime fecha) =>
      DateTime(fecha.year, fecha.month, fecha.day).add(const Duration(days: 1));

  /// Condición de rango sobre [columna] (`$1` = desde, `$2` = hasta
  /// exclusivo).
  ///
  /// En SQLite `fecha_orden` se guarda en UTC (es `CURRENT_TIMESTAMP`), así
  /// que se convierte a hora local **también en el filtro**: si no, una
  /// orden de las 23:30 se filtraría en un día y se etiquetaría en otro.
  static String _condicionRango(String columna) => Dialecto.sqlite
      ? "date($columna, 'localtime') >= \$1 "
            "AND date($columna, 'localtime') < \$2"
      : '$columna >= \$1 AND $columna < \$2';

  /// Expresión que convierte `fecha_orden` en la etiqueta del periodo
  /// (`2026-10-01`, `2026-10` o `2026`), en la hora local del negocio.
  static String _etiquetaPeriodo(String agrupacion) {
    if (Dialecto.sqlite) {
      return switch (agrupacion) {
        'mes' => "strftime('%Y-%m', fecha_orden, 'localtime')",
        'anio' => "strftime('%Y', fecha_orden, 'localtime')",
        _ => "date(fecha_orden, 'localtime')",
      };
    }
    return switch (agrupacion) {
      'mes' => "to_char(fecha_orden, 'YYYY-MM')",
      'anio' => "to_char(fecha_orden, 'YYYY')",
      _ => "to_char(fecha_orden, 'YYYY-MM-DD')",
    };
  }

  /// Una sola consulta para la serie: primero agrega **por orden** (total de
  /// la orden, sus unidades y su utilidad) y después por periodo, de modo que
  /// `ordenes` cuente órdenes y no líneas.
  ///
  /// La utilidad es `monto_total − costo_unitario × cantidad` **solo de las
  /// líneas con costo conocido** (`costo_unitario IS NOT NULL`): las líneas
  /// antiguas sin costo no aportan ni restan, para no inflar la cifra.
  static String _sqlPeriodos(String agrupacion) {
    final porOrden =
        'WITH por_orden AS ('
        'SELECT o.orden_id, o.total, o.fecha_orden, '
        '(SELECT COALESCE(SUM(d.cantidad), 0) '
        'FROM detalles_ordenes_pedidos d '
        'WHERE d.orden_id = o.orden_id '
        "AND d.estado <> '$estadoEliminado') AS unidades, "
        '(SELECT COALESCE(SUM(d.monto_total - d.costo_unitario * d.cantidad), 0) '
        'FROM detalles_ordenes_pedidos d '
        'WHERE d.orden_id = o.orden_id '
        "AND d.estado <> '$estadoEliminado' "
        'AND d.costo_unitario IS NOT NULL) AS utilidad '
        'FROM ordenes_pedidos o '
        "WHERE o.estado = 'PAGADO' "
        'AND ${_condicionRango('o.fecha_orden')})';
    return '$porOrden '
        'SELECT ${_etiquetaPeriodo(agrupacion)} AS periodo, '
        'COUNT(*) AS ordenes, '
        'COALESCE(SUM(total), 0) AS total, '
        'COALESCE(SUM(unidades), 0) AS unidades, '
        'COALESCE(SUM(utilidad), 0) AS utilidad '
        'FROM por_orden GROUP BY 1 ORDER BY 1';
  }
}
