import '../../domain/entities/reporte.dart';
import '../../domain/repositories/reporte_repository.dart';
import '../../domain/rules/estados.dart';
import '../database/database.dart';
import '../database/dialecto.dart';
import '../models/row_utils.dart';

/// Implementación SQL del contrato [ReporteRepository].
///
/// El ranking se calcula con `GROUP BY`: el resultado es una fila por
/// producto (o por periodo) y no hay que cargar los miles de detalles en
/// memoria.
///
/// La tabla ya tiene los índices que hacen esto barato
/// (`idx_detalles_producto` y `idx_detalles_orden`).
final class ReporteRepositoryImpl implements ReporteRepository {
  ReporteRepositoryImpl(this._db);

  final DatabaseConnection _db;

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    required int limite,
    required bool descendente,
    bool porVariante = false,
  }) async {
    // Los nombres de tabla/columna y los literal de estado son constantes del
    // código: `orden` llega traducido a `desc`/`asc` desde el caso de uso, y
    // el único parámetro dinámico va por marcador posicionales ($1).
    // Con `porVariante` se unen las variantes y sus catálogos para que cada
    // fila lleve su talla y color.
    final filas = await _db.query(
      'SELECT p.producto_id, '
      'p.nombre_producto AS nombre, '
      '${porVariante ? 'd.variante_id, t.nombre AS talla, c.nombre AS color, ' : ''}'
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
      '${porVariante ? 'LEFT JOIN producto_variantes v '
              'ON v.variante_id = d.variante_id '
              'LEFT JOIN tallas t ON t.talla_id = v.talla_id '
              'LEFT JOIN colores c ON c.color_id = v.color_id ' : ''}'
      "WHERE p.estado <> '$estadoEliminado' "
      'GROUP BY p.producto_id, p.nombre_producto'
      '${porVariante ? ', d.variante_id, t.nombre, c.nombre' : ''} '
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
          varianteId: RowUtils.intOrNull(fila['variante_id']),
          talla: RowUtils.textOrNull(fila['talla']),
          color: RowUtils.textOrNull(fila['color']),
        ),
    ];
  }

  @override
  Future<List<VentaPeriodo>> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    final rango = _rango('o.fecha_orden', desde, hasta);
    final filas = await _db.query(
      'SELECT etiqueta, COUNT(*)::int AS ordenes, '
      'COALESCE(SUM(total), 0) AS total, '
      'COALESCE(SUM(unidades), 0) AS unidades '
      'FROM ('
      'SELECT o.orden_id, '
      '${_etiqueta('o.fecha_orden', agrupacion)} AS etiqueta, '
      'o.total AS total, '
      // Unidades de la orden en una subconsulta correlacionada: así el
      // importe no se multiplica por el número de líneas al hacer el JOIN.
      '(SELECT COALESCE(SUM(d.cantidad), 0) '
      'FROM detalles_ordenes_pedidos d '
      'WHERE d.orden_id = o.orden_id '
      "AND d.estado <> '$estadoEliminado') AS unidades "
      'FROM ordenes_pedidos o '
      "WHERE o.estado = 'PAGADO' "
      'AND ${rango.sql}'
      ') t '
      'GROUP BY etiqueta '
      'ORDER BY etiqueta',
      rango.params,
    );

    return [
      for (final fila in filas)
        VentaPeriodo(
          etiqueta: RowUtils.text(fila['etiqueta']),
          ordenes: RowUtils.intValue(fila['ordenes']),
          total: RowUtils.doubleValue(fila['total']),
          unidades: RowUtils.doubleValue(fila['unidades']),
        ),
    ];
  }

  @override
  Future<List<VentaProducto>> productosVendidosEnRango({
    required DateTime desde,
    required DateTime hasta,
    required int limite,
  }) async {
    final rango = _rango('o.fecha_orden', desde, hasta);
    final filas = await _db.query(
      'SELECT p.producto_id, p.nombre_producto AS nombre, '
      "COALESCE(c.nombre_categoria, '(sin categoría)') AS categoria, "
      'COALESCE(SUM(d.cantidad), 0) AS unidades, '
      'COALESCE(SUM(d.monto_total), 0) AS monto '
      'FROM detalles_ordenes_pedidos d '
      'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
      'JOIN productos p ON p.producto_id = d.producto_id '
      'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
      "WHERE d.estado <> '$estadoEliminado' "
      "AND o.estado = 'PAGADO' "
      'AND ${rango.sql} '
      'GROUP BY p.producto_id, p.nombre_producto, c.nombre_categoria '
      'ORDER BY monto DESC, p.nombre_producto ASC '
      'LIMIT \$${rango.params.length + 1}',
      [...rango.params, limite],
    );

    return [
      for (final fila in filas)
        VentaProducto(
          productoId: RowUtils.intValue(fila['producto_id']),
          nombre: RowUtils.text(fila['nombre']),
          categoria: RowUtils.text(fila['categoria']),
          unidades: RowUtils.doubleValue(fila['unidades']),
          monto: RowUtils.doubleValue(fila['monto']),
        ),
    ];
  }

  @override
  Future<List<VentaCategoria>> categoriasVendidas({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final rango = _rango('o.fecha_orden', desde, hasta);
    final filas = await _db.query(
      'SELECT COALESCE(c.nombre_categoria, \'(sin categoría)\') AS nombre, '
      'COALESCE(SUM(d.cantidad), 0) AS unidades, '
      'COALESCE(SUM(d.monto_total), 0) AS monto '
      'FROM detalles_ordenes_pedidos d '
      'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
      'JOIN productos p ON p.producto_id = d.producto_id '
      'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
      "WHERE d.estado <> '$estadoEliminado' "
      "AND o.estado = 'PAGADO' "
      'AND ${rango.sql} '
      "GROUP BY COALESCE(c.nombre_categoria, '(sin categoría)') "
      'ORDER BY monto DESC, nombre ASC',
      rango.params,
    );

    return [
      for (final fila in filas)
        VentaCategoria(
          nombre: RowUtils.text(fila['nombre']),
          unidades: RowUtils.doubleValue(fila['unidades']),
          monto: RowUtils.doubleValue(fila['monto']),
        ),
    ];
  }
}

/// Desfase horario de Bolivia: **UTC−4**, sin horario de verano. Toda la
/// app es boliviana (Bs, CI, IVA), así que un informe agrupa por el día de
/// la tienda y no por el del servidor: una venta de las 23:30 (03:30 UTC)
/// cuenta para el día en que la registró la cajera.
const int _horasBolivia = 4;

/// Etiqueta del periodo en hora de Bolivia: `YYYY-MM-DD`, `YYYY-MM` o
/// `YYYY`. En PostgreSQL es `to_char` sobre la hora local desplazada; en
/// SQLite, el trozo equivalente del texto `datetime` (que guarda en UTC).
String _etiqueta(String columna, String agrupacion) {
  if (Dialecto.sqlite) {
    final ancho = switch (agrupacion) {
      'mes' => 7,
      'anio' => 4,
      _ => 10,
    };
    return "substr(datetime($columna, '-$_horasBolivia hours'), 1, $ancho)";
  }
  final formato = switch (agrupacion) {
    'mes' => 'YYYY-MM',
    'anio' => 'YYYY',
    _ => 'YYYY-MM-DD',
  };
  return "to_char(($columna AT TIME ZONE 'UTC') "
      "- INTERVAL '$_horasBolivia hours', '$formato')";
}

/// Condición de rango `[desde, hasta]` (**ambos días incluidos**) sobre una
/// columna de fecha-hora de `ordenes_pedidos`.
///
/// El límite superior es el día siguiente, traducido a la medianoche
/// **local** (hora de Bolivia): `2026-10-07` incluye toda la jornada del 7.
/// El instante se calcula aquí para que solo viajen por la red los dos
/// parámetros del rango.
({String sql, List<Object?> params}) _rango(
  String columna,
  DateTime desde,
  DateTime hasta,
) {
  if (Dialecto.sqlite) {
    // La columna está en texto UTC (`yyyy-MM-dd HH:mm:ss`): `datetime(...)`
    // la deja en un formato canónico para comparar carácter a carácter, y el
    // límite se convierte a UTC sumando el desfase (la medianoche local de
    // un día es su 04:00 UTC). Así `'…T04:00:00Z'` y `'… 04:00:00'`
    // comparan igual.
    return (
      sql: 'datetime($columna) >= datetime(\$1, \'+$_horasBolivia hours\') '
          'AND datetime($columna) < datetime(\$2, \'+$_horasBolivia hours\')',
      params: [_fecha(desde), _fecha(hasta.add(const Duration(days: 1)))],
    );
  }
  // Medianoche local en UTC: la comparación es sobre el instante, así que
  // sigue aprovechando `idx_ordenes_fecha`.
  return (
    sql: '$columna >= \$1 AND $columna < \$2',
    params: [
      _medianocheLocal(desde),
      _medianocheLocal(hasta.add(const Duration(days: 1))),
    ],
  );
}

/// Medianoche **en hora de Bolivia** (UTC−4) del día [fecha] como instante
/// UTC: las 00:00 de La Paz de un día son las 04:00 de ese mismo día en UTC.
DateTime _medianocheLocal(DateTime fecha) =>
    DateTime.utc(fecha.year, fecha.month, fecha.day, _horasBolivia);

/// `DateTime` → `yyyy-MM-dd` (solo la fecha: el rango trabaja por días).
String _fecha(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';
