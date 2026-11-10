import '../../domain/entities/reporte.dart';
import '../../domain/repositories/reporte_repository.dart';
import '../../domain/rules/estados.dart';
import '../database/database.dart';
import '../models/row_utils.dart';

/// Implementación SQL del contrato [ReporteRepository].
///
/// El ranking se calcula en PostgreSQL con `GROUP BY`: el resultado es una fila
/// por producto y no hay que cargar los miles de detalles en memoria (el
/// frontend nunca recibiría más de [limite] filas).
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
  }) async {
    // Los nombres de tabla/columna y los literal de estado son constantes del
    // código: `orden` llega traducido a `desc`/`asc` desde el caso de uso, y
    // el único parámetro dinámico va por marcador posicionales ($1).
    final filas = await _db.query(
      'SELECT p.producto_id, '
      'p.nombre_producto AS nombre, '
      'COALESCE(SUM(d.cantidad), 0)::int AS unidades, '
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
          unidades: RowUtils.intValue(fila['unidades']),
          monto: RowUtils.doubleValue(fila['monto']),
        ),
    ];
  }
}
