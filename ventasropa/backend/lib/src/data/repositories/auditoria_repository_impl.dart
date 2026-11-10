import 'dart:convert';

import '../../domain/entities/auditoria.dart';
import '../../domain/repositories/auditoria_repository.dart';
import '../database/database.dart';
import '../models/auditoria_model.dart';
import '../models/row_utils.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [AuditoriaRepository].
final class AuditoriaRepositoryImpl implements AuditoriaRepository {
  AuditoriaRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columns =
      'id, fecha, usuario_id, nombre_usuario, rol, accion, exitoso, '
      'codigo_error, entidad, entidad_id, resumen, detalles, ip';

  @override
  Future<void> registrar(AuditoriaEvento evento) async {
    await _db.query(
      'INSERT INTO auditoria (fecha, usuario_id, nombre_usuario, rol, accion, '
      'exitoso, codigo_error, entidad, entidad_id, resumen, detalles, ip) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, '
      '\$11::jsonb, \$12)',
      [
        evento.fecha.toUtc(),
        evento.usuarioId,
        evento.nombreUsuario,
        evento.rol,
        evento.accion,
        evento.exitoso,
        evento.codigoError,
        evento.entidad,
        evento.entidadId,
        evento.resumen,
        evento.detalles == null ? null : jsonEncode(evento.detalles),
        evento.ip,
      ],
    );
  }

  @override
  Future<List<AuditoriaEvento>> listar({
    int limit = 50,
    int offset = 0,
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) async {
    final filtros = _filtros(
      usuario: usuario,
      desde: desde,
      hasta: hasta,
      entidad: entidad,
      accion: accion,
      q: q,
    );
    final params = [...filtros.params, limit, offset];

    final rows = await _db.query(
      'SELECT $_columns FROM auditoria${filtros.where} '
      'ORDER BY fecha DESC LIMIT \$${params.length - 1} '
      'OFFSET \$${params.length}',
      params,
    );
    return rows.map(AuditoriaModel.evento).toList();
  }

  @override
  Future<int> count({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) async {
    final filtros = _filtros(
      usuario: usuario,
      desde: desde,
      hasta: hasta,
      entidad: entidad,
      accion: accion,
      q: q,
    );
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM auditoria${filtros.where}',
      filtros.params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  /// Construye el `WHERE` y sus parámetros a partir de los filtros comunes
  /// de [listar] y [count]: así ambos aplican exactamente lo mismo.
  ({String where, List<Object?> params}) _filtros({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  }) {
    final condiciones = <String>[];
    final params = <Object?>[];

    void agregar(String columna, String operador, Object valor) {
      params.add(valor);
      condiciones.add('$columna $operador \$${params.length}');
    }

    if (usuario != null && usuario.trim().isNotEmpty) {
      agregar('nombre_usuario', 'ILIKE', '%${usuario.trim()}%');
    }
    if (desde != null) agregar('fecha', '>=', desde.toUtc());
    if (hasta != null) {
      // `hasta` incluye el día completo: se compara contra el día siguiente.
      agregar('fecha', '<', hasta.toUtc().add(const Duration(days: 1)));
    }
    if (entidad != null && entidad.isNotEmpty) {
      agregar('entidad', '=', entidad);
    }
    if (accion != null && accion.isNotEmpty) {
      agregar('accion', '=', accion);
    }

    final busqueda = andBusqueda('auditoria', q, params.length + 1);
    params.addAll(busqueda.params);
    if (busqueda.sql.isNotEmpty) {
      // [andBusqueda] entrega la condición precedida de ` AND `.
      condiciones.add(busqueda.sql.substring(' AND '.length));
    }

    final where = condiciones.isEmpty ? '' : ' WHERE ${condiciones.join(' AND ')}';
    return (where: where, params: params);
  }

  @override
  Future<int> eliminarAntesDe(DateTime fecha) async {
    final previos = await _db.query(
      'SELECT COUNT(*)::int AS total FROM auditoria WHERE fecha < \$1',
      [fecha.toUtc()],
    );
    final total = RowUtils.intValue(previos.first['total']);
    if (total > 0) {
      await _db.query('DELETE FROM auditoria WHERE fecha < \$1', [
        fecha.toUtc(),
      ]);
    }
    return total;
  }

  @override
  Future<int> eliminarTodo() async {
    final previos = await _db.query(
      'SELECT COUNT(*)::int AS total FROM auditoria',
    );
    final total = RowUtils.intValue(previos.first['total']);
    if (total > 0) await _db.query('DELETE FROM auditoria');
    return total;
  }
}
