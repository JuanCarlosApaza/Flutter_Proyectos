import '../../core/errors/app_exception.dart';
import '../../domain/entities/usuario.dart';
import '../../domain/repositories/rol_repository.dart';
import '../../domain/repositories/usuario_repository.dart';
import '../database/database.dart';
import '../models/row_utils.dart';
import '../models/usuario_model.dart';
import 'borrado_logico.dart';
import 'rol_repository_impl.dart';
import 'sql_builder.dart';

/// Implementación SQL del contrato [UsuarioRepository].
///
/// Desde la migración `009_roles_permisos` la columna `nivel_usuario` ya no
/// existe: el nombre del rol se obtiene de `Roles` y los permisos se
/// hidratan con el repositorio de roles (solo en las lecturas de sesión).
final class UsuarioRepositoryImpl implements UsuarioRepository {
  UsuarioRepositoryImpl(this._db) : _roles = RolRepositoryImpl(_db);

  final DatabaseConnection _db;
  final RolRepository _roles;

  // El rol se selecciona con un escalar (no un JOIN) para que `whereEstado`
  // pueda seguir calificando `estado` sin ambigüedad.
  static const String _columns =
      'u.usuario_id, u.empleado_id, u.rol_id, '
      "(SELECT r.nombre FROM roles r WHERE r.rol_id = u.rol_id) "
      'AS nivel_usuario, '
      'u.nombre_usuario, u.contrasena, u.estado::text AS estado, '
      'u.fecha_creacion, u.fecha_actualizacion';

  static const String _from = 'FROM usuarios u';

  @override
  Future<List<Usuario>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) async {
    final where = whereEstado(estado, 'estado_general');
    // La fila referenciada por la búsqueda es el alias `u` de [_from]:
    // con alias, PostgreSQL ignora el nombre real de la tabla.
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('u', q, params.length + 1);
    params.addAll(busqueda.params);
    final iLimit = params.length + 1;
    final iOffset = params.length + 2;
    final rows = await _db.query(
      'SELECT $_columns $_from$where${busqueda.sql} '
      'ORDER BY u.nombre_usuario LIMIT \$$iLimit OFFSET \$$iOffset',
      [...params, limit, offset],
    );
    return rows.map(UsuarioModel.usuario).toList();
  }

  @override
  Future<int> count({String? estado, String? q}) async {
    final where = whereEstado(estado, 'estado_general');
    final params = <Object?>[?estado];
    final busqueda = andBusqueda('u', q, params.length + 1);
    params.addAll(busqueda.params);
    final rows = await _db.query(
      'SELECT COUNT(*)::int AS total $_from$where${busqueda.sql}',
      params,
    );
    return RowUtils.intValue(rows.first['total']);
  }

  @override
  Future<Usuario?> findById(int id) async {
    final rows = await _db.query(
      'SELECT $_columns $_from WHERE u.usuario_id = \$1',
      [id],
    );
    if (rows.isEmpty) return null;
    return _hidratar(UsuarioModel.usuario(rows.first));
  }

  @override
  Future<Usuario?> findByNombreUsuario(String nombreUsuario) async {
    final rows = await _db.query(
      'SELECT $_columns $_from WHERE u.nombre_usuario = \$1',
      [nombreUsuario],
    );
    if (rows.isEmpty) return null;
    return _hidratar(UsuarioModel.usuario(rows.first));
  }

  @override
  Future<Usuario> insert(Usuario datos) async {
    final rows = await _db.query(
      'INSERT INTO usuarios (empleado_id, rol_id, nombre_usuario, '
      'contrasena, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5::estado_general) '
      'RETURNING usuario_id',
      [
        datos.empleadoId,
        datos.rolId,
        datos.nombreUsuario,
        datos.contrasena,
        datos.estado,
      ],
    );
    final creado = await findById(RowUtils.intValue(rows.first['usuario_id']));
    if (creado == null) {
      throw const NotFoundException(
        'El usuario creado no se pudo recuperar.',
        code: 'usuario_no_encontrado',
      );
    }
    return creado;
  }

  @override
  Future<Usuario> update(int id, Usuario datos, Set<String> campos) async {
    final cambios = <String, Object?>{
      if (campos.contains('empleadoId')) 'empleado_id': datos.empleadoId,
      if (campos.contains('rolId')) 'rol_id': datos.rolId,
      if (campos.contains('nombreUsuario'))
        'nombre_usuario': datos.nombreUsuario,
      if (campos.contains('contrasena')) 'contrasena': datos.contrasena,
      if (campos.contains('estado')) 'estado': datos.estado,
    };
    final upd = updateSet(cambios, casts: const {'estado': 'estado_general'});
    final rows = await _db.query(
      'UPDATE usuarios SET ${upd.set} WHERE usuario_id = '
      '\$${upd.params.length + 1} RETURNING usuario_id',
      [...upd.params, id],
    );
    if (rows.isEmpty) {
      throw const NotFoundException(
        'El usuario no existe.',
        code: 'usuario_no_encontrado',
      );
    }
    final actualizado = await findById(id);
    if (actualizado == null) {
      throw const NotFoundException(
        'El usuario no existe.',
        code: 'usuario_no_encontrado',
      );
    }
    return actualizado;
  }

  @override
  Future<bool> delete(int id) => ocultarRegistro(
    _db,
    tabla: 'usuarios',
    pk: 'usuario_id',
    enumTipo: 'estado_general',
    id: id,
  );

  /// Adjunta los permisos del rol (los listados no los necesitan).
  Future<Usuario> _hidratar(Usuario usuario) async {
    if (usuario.rolId == 0) return usuario;
    return usuario.conPermisos(await _roles.permisosDeRol(usuario.rolId));
  }
}
