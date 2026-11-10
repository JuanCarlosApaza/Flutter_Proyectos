import '../../domain/entities/categoria.dart';
import '../../domain/repositories/categoria_repository.dart';
import '../database/database.dart';
import '../models/categoria_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [CategoriaRepository].
///
/// Todas las sentencias usan parámetros posicionales (`$1`, `$2`): los valores
/// nunca se concatenan en el SQL (inyección SQL). Los nombres de tabla y
/// columna que se interpolan son constantes del código, jamás datos de la petición.
final class CategoriaRepositoryImpl implements CategoriaRepository {
  CategoriaRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _categoriaColumns =
      'categoria_id, nombre_categoria, estado::text AS estado, '
      'fecha_creacion, fecha_actualizacion';

  static const String _presentacionColumns =
      'presentacion_id, nombre_presentacion, estado::text AS estado, '
      'fecha_creacion, fecha_actualizacion';

  // --- Categorías ---------------------------------------------------------

  @override
  Future<List<Categoria>> findCategorias({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('categorias', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_categoriaColumns FROM categorias$where${busqueda.sql} '
      'ORDER BY nombre_categoria LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(CategoriaModel.categoria).toList();
  }

  @override
  Future<int> countCategorias({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('categorias', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM categorias$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Categoria?> findCategoriaById(int id) async {
    final rows = await _db.query(
      'SELECT $_categoriaColumns FROM categorias WHERE categoria_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : CategoriaModel.categoria(rows.first);
  }

  @override
  Future<Categoria> insertCategoria({
    required String nombre,
    required String estado,
  }) async {
    final rows = await _db.query(
      'INSERT INTO categorias (nombre_categoria, estado) '
      'VALUES (\$1, \$2::estado_general) '
      'RETURNING $_categoriaColumns',
      [nombre, estado],
    );
    return CategoriaModel.categoria(rows.first);
  }

  @override
  Future<Categoria> updateCategoria(
    int id, {
    required String nombre,
    required String estado,
  }) async {
    final rows = await _db.query(
      'UPDATE categorias SET nombre_categoria = \$1, '
      'estado = \$2::estado_general, fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE categoria_id = \$3 '
      'RETURNING $_categoriaColumns',
      [nombre, estado, id],
    );
    return CategoriaModel.categoria(rows.first);
  }

  @override
  Future<bool> deleteCategoria(int id) => ocultarRegistro(
    _db,
    tabla: 'categorias',
    pk: 'categoria_id',
    enumTipo: 'estado_general',
    id: id,
  );

  // --- Presentaciones ------------------------------------------------------

  @override
  Future<List<Presentacion>> findPresentaciones({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('presentaciones', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_presentacionColumns FROM presentaciones$where${busqueda.sql} '
      'ORDER BY nombre_presentacion LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(CategoriaModel.presentacion).toList();
  }

  @override
  Future<int> countPresentaciones({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('presentaciones', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM presentaciones$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Presentacion?> findPresentacionById(int id) async {
    final rows = await _db.query(
      'SELECT $_presentacionColumns FROM presentaciones WHERE presentacion_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : CategoriaModel.presentacion(rows.first);
  }

  @override
  Future<Presentacion> insertPresentacion({
    required String nombre,
    required String estado,
  }) async {
    final rows = await _db.query(
      'INSERT INTO presentaciones (nombre_presentacion, estado) '
      'VALUES (\$1, \$2::estado_general) '
      'RETURNING $_presentacionColumns',
      [nombre, estado],
    );
    return CategoriaModel.presentacion(rows.first);
  }

  @override
  Future<Presentacion> updatePresentacion(
    int id, {
    required String nombre,
    required String estado,
  }) async {
    final rows = await _db.query(
      'UPDATE presentaciones SET nombre_presentacion = \$1, '
      'estado = \$2::estado_general, fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE presentacion_id = \$3 '
      'RETURNING $_presentacionColumns',
      [nombre, estado, id],
    );
    return CategoriaModel.presentacion(rows.first);
  }

  @override
  Future<bool> deletePresentacion(int id) => ocultarRegistro(
    _db,
    tabla: 'presentaciones',
    pk: 'presentacion_id',
    enumTipo: 'estado_general',
    id: id,
  );
}
