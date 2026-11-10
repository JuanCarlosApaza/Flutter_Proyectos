import '../../domain/entities/color.dart';
import '../../domain/repositories/color_repository.dart';
import '../database/database.dart';
import '../models/color_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [ColorRepository].
///
/// Todas las sentencias usan parámetros posicionales (`$1`, `$2`): los valores
/// nunca se concatenan en el SQL (inyección SQL). Los nombres de tabla y
/// columna que se interpolan son constantes del código, jamás datos de la
/// petición.
final class ColorRepositoryImpl implements ColorRepository {
  ColorRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _colorColumns =
      'color_id, nombre, codigo_hex, estado::text AS estado, '
      'fecha_creacion, fecha_actualizacion';

  @override
  Future<List<Color>> findColores({
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
    return rows.map(ColorModel.color).toList(growable: false);
  }

  @override
  Future<int> countColores({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('colores', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT count(*) AS total FROM colores$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Color?> findColorById(int id) async {
    final rows = await _db.query(
      'SELECT $_colorColumns FROM colores WHERE color_id = \$1',
      [id],
    );
    return rows.isEmpty ? null : ColorModel.color(rows.first);
  }

  @override
  Future<Color?> findColorVivoByNombre(String nombre) async {
    // `LOWER(nombre)` replica la clave parcial 022; el parámetro llega ya en
    // minúsculas para que el índice de expresión pueda usarse.
    final rows = await _db.query(
      'SELECT $_colorColumns FROM colores '
      'WHERE LOWER(nombre) = \$1 AND estado <> \'ELIMINADO\' '
      'LIMIT 1',
      [nombre.trim().toLowerCase()],
    );
    return rows.isEmpty ? null : ColorModel.color(rows.first);
  }

  @override
  Future<Color> insertColor({
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
    return ColorModel.color(rows.first);
  }

  @override
  Future<Color> updateColor(
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
    return ColorModel.color(rows.first);
  }

  @override
  Future<bool> deleteColor(int id) => ocultarRegistro(
    _db,
    tabla: 'colores',
    pk: 'color_id',
    enumTipo: 'estado_general',
    id: id,
  );
}
