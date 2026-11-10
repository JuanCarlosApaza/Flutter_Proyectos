import '../../domain/entities/marca.dart';
import '../../domain/repositories/marca_repository.dart';
import '../database/database.dart';
import '../models/marca_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [MarcaRepository].
///
/// Todas las sentencias usan parámetros posicionales (`$1`, `$2`): los valores
/// nunca se concatenan en el SQL (inyección SQL). Los nombres de tabla y
/// columna que se interpolan son constantes del código, jamás datos de la
/// petición.
final class MarcaRepositoryImpl implements MarcaRepository {
  MarcaRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _marcaColumns =
      'marca_id, nombre, estado::text AS estado, '
      'fecha_creacion, fecha_actualizacion';

  @override
  Future<List<Marca>> findMarcas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('marcas', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_marcaColumns FROM marcas$where${busqueda.sql} '
      'ORDER BY nombre LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(MarcaModel.marca).toList(growable: false);
  }

  @override
  Future<int> countMarcas({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('marcas', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT count(*) AS total FROM marcas$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Marca?> findMarcaById(int id) async {
    final rows = await _db.query(
      'SELECT $_marcaColumns FROM marcas WHERE marca_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : MarcaModel.marca(rows.first);
  }

  @override
  Future<Marca?> findMarcaVivaByNombre(String nombre) async {
    // `LOWER(nombre)` replica la clave parcial 023; el parámetro llega ya en
    // minúsculas para que el índice de expresión pueda usarse.
    final rows = await _db.query(
      'SELECT $_marcaColumns FROM marcas '
      'WHERE LOWER(nombre) = \$1 AND estado <> \'ELIMINADO\' '
      'LIMIT 1',
      [nombre.trim().toLowerCase()],
    );
    return rows.isEmpty ? null : MarcaModel.marca(rows.first);
  }

  @override
  Future<Marca> insertMarca({required String nombre, required String estado}) async {
    final rows = await _db.query(
      'INSERT INTO marcas (nombre, estado) '
      'VALUES (\$1, \$2::estado_general) '
      'RETURNING $_marcaColumns',
      [nombre, estado],
    );
    return MarcaModel.marca(rows.first);
  }

  @override
  Future<Marca> updateMarca(
    int id, {
    required String nombre,
    required String estado,
  }) async {
    final rows = await _db.query(
      'UPDATE marcas SET nombre = \$1, '
      'estado = \$2::estado_general, fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE marca_id = \$3 '
      'RETURNING $_marcaColumns',
      [nombre, estado, id],
    );
    return MarcaModel.marca(rows.first);
  }

  @override
  Future<bool> deleteMarca(int id) => ocultarRegistro(
    _db,
    tabla: 'marcas',
    pk: 'marca_id',
    enumTipo: 'estado_general',
    id: id,
  );
}
