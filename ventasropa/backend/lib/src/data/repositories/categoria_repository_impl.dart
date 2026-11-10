import '../../domain/entities/categoria.dart';
import '../../domain/entities/marca.dart';
import '../../domain/entities/talla.dart';
import '../../domain/repositories/categoria_repository.dart';
import '../database/database.dart';
import '../models/categoria_model.dart';
import '../models/marca_model.dart';
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

  static const String _tallaColumns =
      'talla_id, nombre, orden, estado::text AS estado';

  static const String _colorColumns =
      'color_id, nombre, codigo_hex, estado::text AS estado';

  static const String _marcaColumns =
      'marca_id, nombre_marca, estado::text AS estado, '
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

  // --- Tallas -------------------------------------------------------------

  @override
  Future<List<Talla>> findTallas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('tallas', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_tallaColumns FROM tallas$where${busqueda.sql} '
      'ORDER BY orden, nombre LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(CategoriaModel.talla).toList();
  }

  @override
  Future<int> countTallas({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('tallas', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM tallas$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Talla?> findTallaById(int id) async {
    final rows = await _db.query(
      'SELECT $_tallaColumns FROM tallas WHERE talla_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : CategoriaModel.talla(rows.first);
  }

  @override
  Future<Talla> insertTalla({
    required String nombre,
    required int orden,
    required String estado,
  }) async {
    final rows = await _db.query(
      'INSERT INTO tallas (nombre, orden, estado) '
      'VALUES (\$1, \$2, \$3::estado_general) '
      'RETURNING $_tallaColumns',
      [nombre, orden, estado],
    );
    return CategoriaModel.talla(rows.first);
  }

  @override
  Future<Talla> updateTalla(
    int id, {
    required String nombre,
    required int orden,
    required String estado,
  }) async {
    final rows = await _db.query(
      'UPDATE tallas SET nombre = \$1, orden = \$2, '
      'estado = \$3::estado_general, fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE talla_id = \$4 '
      'RETURNING $_tallaColumns',
      [nombre, orden, estado, id],
    );
    return CategoriaModel.talla(rows.first);
  }

  @override
  Future<bool> deleteTalla(int id) => ocultarRegistro(
    _db,
    tabla: 'tallas',
    pk: 'talla_id',
    enumTipo: 'estado_general',
    id: id,
  );

  // --- Colores ------------------------------------------------------------

  @override
  Future<List<ColorRopa>> findColores({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('colores', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_colorColumns FROM colores$where${busqueda.sql} '
      'ORDER BY nombre LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(CategoriaModel.color).toList();
  }

  @override
  Future<int> countColores({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('colores', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM colores$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<ColorRopa?> findColorById(int id) async {
    final rows = await _db.query(
      'SELECT $_colorColumns FROM colores WHERE color_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : CategoriaModel.color(rows.first);
  }

  @override
  Future<ColorRopa> insertColor({
    required String nombre,
    String? codigoHex,
    required String estado,
  }) async {
    final rows = await _db.query(
      'INSERT INTO colores (nombre, codigo_hex, estado) '
      'VALUES (\$1, \$2, \$3::estado_general) '
      'RETURNING $_colorColumns',
      [nombre, codigoHex, estado],
    );
    return CategoriaModel.color(rows.first);
  }

  @override
  Future<ColorRopa> updateColor(
    int id, {
    required String nombre,
    String? codigoHex,
    required String estado,
  }) async {
    final rows = await _db.query(
      'UPDATE colores SET nombre = \$1, codigo_hex = \$2, '
      'estado = \$3::estado_general, fecha_actualizacion = CURRENT_TIMESTAMP '
      'WHERE color_id = \$4 '
      'RETURNING $_colorColumns',
      [nombre, codigoHex, estado, id],
    );
    return CategoriaModel.color(rows.first);
  }

  @override
  Future<bool> deleteColor(int id) => ocultarRegistro(
    _db,
    tabla: 'colores',
    pk: 'color_id',
    enumTipo: 'estado_general',
    id: id,
  );

  // --- Marcas ------------------------------------------------------------

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
      'ORDER BY nombre_marca LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(MarcaModel.marca).toList();
  }

  @override
  Future<int> countMarcas({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('marcas', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total FROM marcas$where${busqueda.sql}',
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
  Future<Marca> insertMarca({
    required String nombre,
    required String estado,
  }) async {
    final rows = await _db.query(
      'INSERT INTO marcas (nombre_marca, estado) '
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
      'UPDATE marcas SET nombre_marca = \$1, '
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
