import '../../core/errors/app_exception.dart';
import '../../domain/entities/cotizacion.dart';
import '../../domain/repositories/cotizacion_repository.dart';
import '../database/database.dart';
import '../models/cotizacion_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [CotizacionRepository].
///
/// La cabecera y sus líneas se insertan en `runInTransaction`: o se guarda
/// la cotización entera o no se guarda nada. Las líneas son inmutables
/// (no hay edición posterior), así que no necesitan estado propio.
final class CotizacionRepositoryImpl implements CotizacionRepository {
  CotizacionRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _cotizacionColumns =
      'cotizacion_id, fecha_cotizacion, cliente_id, nombre_cliente, '
      'empleado_id, total, estado::text AS estado, fecha_creacion, '
      'fecha_actualizacion';

  /// Líneas de cotización con su variante unida (misma lectura que las
  /// órdenes: `nombre_color` congelado de la variante).
  static const String _detalleSelect =
      'SELECT d.producto_id, d.nombre_producto, d.imagen, d.unidad, '
      'd.cantidad, d.precio_venta, d.monto_total, '
      'd.variante_id, v.nombre_color '
      'FROM detalles_cotizaciones d '
      'LEFT JOIN producto_variantes v ON v.variante_id = d.variante_id ';

  @override
  Future<List<Cotizacion>> findCotizaciones({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_cotizacion');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('cotizaciones', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_cotizacionColumns FROM cotizaciones$where${busqueda.sql} '
      'ORDER BY cotizacion_id DESC LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(CotizacionModel.cotizacion).toList();
  }

  @override
  Future<int> countCotizaciones({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_cotizacion');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('cotizaciones', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM cotizaciones$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Cotizacion?> findCotizacionById(int id) async {
    final rows = await _db.query(
      'SELECT $_cotizacionColumns FROM cotizaciones WHERE cotizacion_id = \$1',
      [id],
    );
    if (rows.isEmpty) return null;
    final lineas = await findDetallesByCotizacion(id);
    return CotizacionModel.cotizacion(rows.first, detalles: lineas);
  }

  /// Líneas de la cotización (la PK compuesta `(producto_id, cotizacion_id,
  /// variante_id)` no sirve para buscar solo por `cotizacion_id` sin índice
  /// previo).
  Future<List<DetalleCotizacion>> findDetallesByCotizacion(
    int cotizacionId,
  ) async {
    final rows = await _db.query(
      '${_detalleSelect}WHERE d.cotizacion_id = \$1 ORDER BY d.nombre_producto',
      [cotizacionId],
    );
    return rows.map(CotizacionModel.detalle).toList();
  }

  @override
  Future<Cotizacion> insertCotizacion(
    Cotizacion datos,
    List<DetalleCotizacion> detalles,
  ) async {
    Cotizacion? creada;

    await _db.runInTransaction((session) async {
      final rows = await session.query(
        'INSERT INTO cotizaciones (cliente_id, nombre_cliente, empleado_id, '
        'total, estado) '
        'VALUES (\$1, \$2, \$3, \$4, \$5::estado_cotizacion) '
        'RETURNING $_cotizacionColumns',
        [
          datos.clienteId,
          datos.nombreCliente,
          datos.empleadoId,
          datos.total,
          datos.estado,
        ],
      );

      final cabecera = CotizacionModel.cotizacion(rows.first);

      for (final linea in detalles) {
        await session.query(
          'INSERT INTO detalles_cotizaciones (producto_id, cotizacion_id, '
          'nombre_producto, imagen, unidad, cantidad, precio_venta, '
          'monto_total, variante_id) '
          'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9)',
          [
            linea.productoId,
            cabecera.id,
            linea.nombreProducto,
            linea.imagen,
            linea.unidad,
            linea.cantidad,
            linea.precioVenta,
            linea.montoTotal,
            linea.varianteId,
          ],
        );
      }

      creada = cabecera.conDetalles(detalles);
    });

    return creada!;
  }

  @override
  Future<Cotizacion> updateEstadoCotizacion(int id, String estado) async {
    final rows = await _db.query(
      'UPDATE cotizaciones SET estado = \$1::estado_cotizacion, '
      'fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE cotizacion_id = \$2 RETURNING $_cotizacionColumns',
      [estado, id],
    );
    if (rows.isEmpty) {
      throw const NotFoundException(
        'La cotización no existe.',
        code: 'cotizacion_no_encontrada',
      );
    }
    return CotizacionModel.cotizacion(rows.first);
  }

  @override
  Future<bool> deleteCotizacion(int id) => ocultarRegistro(
    _db,
    tabla: 'cotizaciones',
    pk: 'cotizacion_id',
    enumTipo: 'estado_cotizacion',
    id: id,
  );
}
