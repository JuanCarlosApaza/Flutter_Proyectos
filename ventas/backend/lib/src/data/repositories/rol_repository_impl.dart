import '../../core/errors/app_exception.dart';
import '../../domain/entities/rol.dart';
import '../../domain/repositories/rol_repository.dart';
import '../database/database.dart';
import '../models/rol_model.dart';
import '../models/row_utils.dart';
import 'borrado_logico.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [RolRepository].
final class RolRepositoryImpl implements RolRepository {
  RolRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columns =
      'rol_id, nombre, descripcion, es_sistema, estado::text AS estado, '
      'creado_en, actualizado_en';

  @override
  Future<List<Rol>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    final rows = await _db.query(
      'SELECT $_columns FROM roles$where '
      'ORDER BY nombre LIMIT \$${estado == null ? 1 : 2} '
      'OFFSET \$${estado == null ? 2 : 3}',
      [?estado, limit, offset],
    );
    final permisos = await permisosPorRol();
    final salida = <Rol>[];
    for (final row in rows) {
      final rol = RolModel.rol(row);
      salida.add(rol.conPermisos(permisos[rol.id] ?? const <String>{}));
    }
    return salida;
  }

  @override
  Future<Rol?> findById(int id) async {
    final rows = await _db.query(
      'SELECT $_columns FROM roles WHERE rol_id = \$1',
      [id],
    );
    if (rows.isEmpty) return null;
    return RolModel.rol(rows.first).conPermisos(await permisosDeRol(id));
  }

  @override
  Future<Set<String>> permisosDeRol(int rolId) async {
    final rows = await _db.query(
      'SELECT p.modulo || \'.\' || p.accion AS permiso '
      'FROM rol_permisos rp '
      'JOIN permisos p ON p.permiso_id = rp.permiso_id '
      'WHERE rp.rol_id = \$1 ORDER BY p.modulo, p.accion',
      [rolId],
    );
    return {for (final row in rows) RowUtils.text(row['permiso'])};
  }

  @override
  Future<Map<int, Set<String>>> permisosPorRol() async {
    final rows = await _db.query(
      'SELECT rp.rol_id, p.modulo || \'.\' || p.accion AS permiso '
      'FROM rol_permisos rp '
      'JOIN permisos p ON p.permiso_id = rp.permiso_id '
      'ORDER BY rp.rol_id, p.modulo, p.accion',
    );
    final mapa = <int, Set<String>>{};
    for (final row in rows) {
      mapa
          .putIfAbsent(RowUtils.intValue(row['rol_id']), () => <String>{})
          .add(RowUtils.text(row['permiso']));
    }
    return mapa;
  }

  @override
  Future<Rol> insert(Rol datos, Set<String> permisos) async {
    final ids = await _idsDePermisos(permisos);
    late int rolId;
    await _db.runInTransaction((session) async {
      final rows = await session.query(
        'INSERT INTO roles (nombre, descripcion, es_sistema, estado) '
        'VALUES (\$1, \$2, \$3, \$4::estado_general) RETURNING rol_id',
        [datos.nombre, datos.descripcion, datos.esSistema, datos.estado],
      );
      rolId = RowUtils.intValue(rows.first['rol_id']);
      await _insertarPermisos(session, rolId, ids);
    });
    final creado = await findById(rolId);
    if (creado == null) {
      throw const NotFoundException(
        'El rol creado no se pudo recuperar.',
        code: 'rol_no_encontrado',
      );
    }
    return creado;
  }

  @override
  Future<Rol> update(
    int id,
    Rol datos,
    Set<String> campos, {
    Set<String>? permisos,
  }) async {
    final ids = permisos == null ? null : await _idsDePermisos(permisos);
    await _db.runInTransaction((session) async {
      final cambios = <String, Object?>{
        if (campos.contains('nombre')) 'nombre': datos.nombre,
        if (campos.contains('descripcion')) 'descripcion': datos.descripcion,
        if (campos.contains('estado')) 'estado': datos.estado,
      };
      if (cambios.isNotEmpty) {
        final upd = updateSet(
          cambios,
          casts: const {'estado': 'estado_general'},
          // Roles no tiene `fecha_actualizacion` (usa `actualizado_en`, que
          // tampoco tocaba el trigger de esta tabla): se mantiene igual.
          columnaFecha: null,
        );
        await session.query(
          'UPDATE roles SET ${upd.set} WHERE rol_id = '
          '\$${upd.params.length + 1}',
          [...upd.params, id],
        );
      }
      if (ids != null) {
        await session.query('DELETE FROM rol_permisos WHERE rol_id = \$1', [
          id,
        ]);
        await _insertarPermisos(session, id, ids);
      }
    });
    final actualizado = await findById(id);
    if (actualizado == null) {
      throw const NotFoundException(
        'El rol no existe.',
        code: 'rol_no_encontrado',
      );
    }
    return actualizado;
  }

  @override
  Future<bool> delete(int id) => ocultarRegistro(
    _db,
    tabla: 'roles',
    pk: 'rol_id',
    enumTipo: 'estado_general',
    id: id,
  );

  @override
  Future<int> contarUsuariosActivos(int rolId) async {
    final rows = await _db.query(
      "SELECT COUNT(*)::int AS total FROM usuarios "
      "WHERE rol_id = \$1 AND estado = 'ACTIVO'",
      [rolId],
    );
    return RowUtils.intValue(rows.first['total']);
  }

  /// `permiso.accion` → `permiso_id`; lanza `400` con los desconocidos.
  Future<List<int>> _idsDePermisos(Set<String> permisos) async {
    if (permisos.isEmpty) return const [];
    final rows = await _db.query(
      'SELECT permiso_id, modulo || \'.\' || accion AS permiso FROM permisos',
    );
    final catalogo = {
      for (final row in rows)
        RowUtils.text(row['permiso']): RowUtils.intValue(row['permiso_id']),
    };
    final desconocidos = permisos.where((p) => !catalogo.containsKey(p));
    if (desconocidos.isNotEmpty) {
      throw BadRequestException(
        'Permisos desconocidos: ${desconocidos.join(', ')}.',
        code: 'permiso_desconocido',
      );
    }
    return [for (final p in permisos) catalogo[p]!];
  }

  Future<void> _insertarPermisos(
    DatabaseSession session,
    int rolId,
    List<int> ids,
  ) async {
    if (ids.isEmpty) return;
    final values = <String>[];
    final params = <Object?>[rolId];
    for (final permisoId in ids) {
      params.add(permisoId);
      values.add('(\$1, \$${params.length})');
    }
    await session.query(
      'INSERT INTO rol_permisos (rol_id, permiso_id) '
      'VALUES ${values.join(', ')}',
      params,
    );
  }
}
