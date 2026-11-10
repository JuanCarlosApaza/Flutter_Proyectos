import '../../domain/entities/unidad_medida.dart';
import '../../domain/repositories/unidad_medida_repository.dart';
import '../database/database.dart';
import '../models/row_utils.dart';
import '../models/unidad_medida_model.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [UnidadMedidaRepository].
///
/// Todas las sentencias usan parámetros posicionales (`$1`, `$2`): los valores
/// nunca se concatenan en el SQL (inyección SQL). Los nombres de tabla y
/// columna que se interpolan son constantes del código, jamás datos de la
/// petición.
final class UnidadMedidaRepositoryImpl implements UnidadMedidaRepository {
  UnidadMedidaRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columnas =
      'unidad_id, codigo, nombre_unidad, tipo, decimales, '
      'estado::text AS estado, fecha_creacion, fecha_actualizacion';

  /// El código es el símbolo que viaja en `productos.unidad`, así que se
  /// ordena por tipo (peso, luego lo que se cuenta, luego volumen) y dentro
  /// de cada uno por código: el desplegable del producto lee este orden.
  static const String _orden = 'ORDER BY tipo, codigo';

  @override
  Future<List<UnidadMedida>> findUnidades({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('unidades_medida', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_columnas FROM unidades_medida$where${busqueda.sql} '
      '$_orden LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(UnidadMedidaModel.unidad).toList();
  }

  @override
  Future<int> countUnidades({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('unidades_medida', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM unidades_medida$where'
      '${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<UnidadMedida?> findUnidadById(int id) async {
    final rows = await _db.query(
      'SELECT $_columnas FROM unidades_medida WHERE unidad_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : UnidadMedidaModel.unidad(rows.first);
  }

  @override
  Future<UnidadMedida?> findUnidadActivaByCodigo(String codigo) async {
    // Literal de estado, no parámetro: es una constante del código.
    final rows = await _db.query(
      'SELECT $_columnas FROM unidades_medida '
      "WHERE codigo = \$1 AND estado = 'ACTIVO'",
      [codigo],
    );
    return rows.isEmpty ? null : UnidadMedidaModel.unidad(rows.first);
  }

  @override
  Future<UnidadMedida> insertUnidad({
    required String codigo,
    required String nombre,
    required String tipo,
    required int decimales,
    required String estado,
  }) async {
    final rows = await _db.query(
      'INSERT INTO unidades_medida '
      '(codigo, nombre_unidad, tipo, decimales, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5::estado_general) '
      'RETURNING $_columnas',
      [codigo, nombre, tipo, decimales, estado],
    );
    return UnidadMedidaModel.unidad(rows.first);
  }

  @override
  Future<UnidadMedida> updateUnidad(
    int id, {
    required String codigo,
    required String nombre,
    required String tipo,
    required int decimales,
    required String estado,
  }) async {
    final rows = await _db.query(
      'UPDATE unidades_medida SET codigo = \$1, nombre_unidad = \$2, '
      'tipo = \$3, decimales = \$4, estado = \$5::estado_general, '
      'fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE unidad_id = \$6 '
      'RETURNING $_columnas',
      [codigo, nombre, tipo, decimales, estado, id],
    );
    return UnidadMedidaModel.unidad(rows.first);
  }

  @override
  Future<bool> deleteUnidad(int id) => ocultarRegistro(
    _db,
    tabla: 'unidades_medida',
    pk: 'unidad_id',
    enumTipo: 'estado_general',
    id: id,
  );
}
