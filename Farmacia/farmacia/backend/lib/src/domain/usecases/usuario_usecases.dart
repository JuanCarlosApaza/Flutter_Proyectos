import '../../core/errors/app_exception.dart';
import '../entities/rol.dart';
import '../entities/usuario.dart';
import '../repositories/rol_repository.dart';
import '../repositories/usuario_repository.dart';
import '../rules/contrasenas.dart';
import '../rules/estados.dart';
import 'rol_usecases.dart' show rolAdmin;

/// Casos de uso de usuarios del sistema.
///
/// Reglas de autorización (RBAC, `009_roles_permisos`):
///
/// * Un usuario nuevo/actualizado debe apuntar a un rol `ACTIVO` existente.
/// * [actor] es la cuenta que hace la petición: no puede asignar un rol con
///   permisos que ella no tiene (evita la escalada de privilegios). `null`
///   solo cabe en el arranque inicial, cuando la BD no tiene ningún usuario.
/// * Al último usuario ADMIN activo no se le puede quitar el rol, ni
///   desactivar, ni eliminar: dejaría el sistema sin administradores.
///
/// Reglas de contraseña:
///
/// * En la BD solo se guarda el hash **bcrypt**; nunca el texto claro.
/// * Cambiar una contraseña ([actualizar] con el campo `contrasena`) exige
///   [claveAdmin] con la clave propia del [actor]: sin ella `400
///   clave_admin_requerida`; si no coincide `403 clave_admin_incorrecta`.
/// * Crear ([crear]) no pide clave de admin (no es un cambio; además cubre
///   el primer arranque, todavía sin sesión).
final class Usuarios {
  const Usuarios({required this.repository, required this.roles});

  final UsuarioRepository repository;
  final RolRepository roles;

  Future<List<Usuario>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findAll(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de usuarios con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.count(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<Usuario> obtener(int id) async {
    final usuario = await repository.findById(id);
    if (usuario == null) {
      throw NotFoundException(
        'El usuario $id no existe.',
        code: 'usuario_no_encontrado',
      );
    }
    return usuario;
  }

  Future<Usuario> crear({
    required String nombreUsuario,
    required String contrasena,
    required int rolId,
    int? empleadoId,
    String estado = 'ACTIVO',
    Usuario? actor,
  }) async {
    _ensureNombreUsuario(nombreUsuario);
    _ensureContrasena(contrasena);
    final rol = await _asegurarRolAsignable(rolId, actor);
    return repository.insert(
      Usuario(
        id: 0,
        empleadoId: empleadoId,
        rolId: rol.id,
        nivelUsuario: rol.nombre,
        nombreUsuario: nombreUsuario,
        // La BD guarda el hash: el texto claro no persiste.
        contrasena: hashContrasena(contrasena),
        estado: ensureEstado(estado, estadosGenerales, 'estado'),
        fechaCreacion: DateTime.now(),
        fechaActualizacion: DateTime.now(),
      ),
    );
  }

  /// Actualización parcial; la contraseña solo cambia si se envía, y en ese
  /// caso exige la [claveAdmin] del actor (ver doc de la clase).
  Future<Usuario> actualizar(
    int id,
    Usuario datos,
    Set<String> campos, {
    Usuario? actor,
    String? claveAdmin,
  }) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    if (campos.contains('contrasena')) {
      _asegurarClaveAdmin(actor, claveAdmin);
      _ensureContrasena(datos.contrasena ?? '');
    }
    if (campos.contains('nombreUsuario')) {
      _ensureNombreUsuario(datos.nombreUsuario);
    }

    final actual = await obtener(id);

    if (campos.contains('rolId')) {
      final rol = await _asegurarRolAsignable(datos.rolId, actor);
      if (actual.nivelUsuario == rolAdmin && rol.id != actual.rolId) {
        await _asegurarNoUltimoAdmin(actual, 'cambiarle el rol');
      }
    }
    if (campos.contains('estado') &&
        datos.estado != 'ACTIVO' &&
        actual.estado == 'ACTIVO') {
      await _asegurarNoUltimoAdmin(actual, 'desactivarlo');
    }

    return repository.update(
      id,
      Usuario(
        id: id,
        empleadoId: datos.empleadoId,
        rolId: datos.rolId,
        nivelUsuario: datos.nivelUsuario,
        nombreUsuario: datos.nombreUsuario,
        contrasena: campos.contains('contrasena')
            ? hashContrasena(datos.contrasena ?? '')
            : datos.contrasena,
        estado: campos.contains('estado')
            ? ensureEstado(datos.estado, estadosGenerales, 'estado')
            : datos.estado,
        fechaCreacion: datos.fechaCreacion,
        fechaActualizacion: datos.fechaActualizacion,
      ),
      campos,
    );
  }

  Future<void> eliminar(int id) async {
    final actual = await obtener(id);
    await _asegurarNoUltimoAdmin(actual, 'eliminarlo');
    final removed = await repository.delete(id);
    if (!removed) {
      throw NotFoundException(
        'El usuario $id no existe.',
        code: 'usuario_no_encontrado',
      );
    }
  }

  /// `400` si no se envía la clave del admin; `403` si no coincide con la
  /// contraseña del propio [actor] (hash bcrypt o valor legado).
  void _asegurarClaveAdmin(Usuario? actor, String? claveAdmin) {
    if (actor == null || claveAdmin == null || claveAdmin.isEmpty) {
      throw const BadRequestException(
        'Para cambiar una contraseña envía "claveAdmin" con tu propia clave.',
        code: 'clave_admin_requerida',
      );
    }
    if (!verificarContrasena(
      guardada: actor.contrasena ?? '',
      recibida: claveAdmin,
    )) {
      throw const ForbiddenException(
        'La clave de administrador no coincide.',
        code: 'clave_admin_incorrecta',
      );
    }
  }

  /// `404` si el rol no existe, `409` si está inactivo y `403` si [actor]
  /// no tiene todos los permisos que da el rol.
  Future<Rol> _asegurarRolAsignable(int rolId, Usuario? actor) async {
    if (rolId <= 0) {
      throw const BadRequestException(
        'El campo "rolId" es obligatorio (id de un rol existente).',
        code: 'rol_requerido',
      );
    }
    final rol = await roles.findById(rolId);
    if (rol == null) {
      throw NotFoundException(
        'El rol $rolId no existe.',
        code: 'rol_no_encontrado',
      );
    }
    if (rol.estado != 'ACTIVO') {
      throw ConflictException(
        'El rol ${rol.nombre} no está activo.',
        code: 'rol_inactivo',
      );
    }
    if (actor != null && !actor.permisos.containsAll(rol.permisos)) {
      throw const ForbiddenException(
        'No puedes asignar un rol con permisos que tú no tienes.',
        code: 'rol_superior',
      );
    }
    return rol;
  }

  /// `409` si [usuario] es el único ADMIN activo y la operación lo dejaría
  /// fuera de servicio (no puede quedar el sistema sin administradores).
  Future<void> _asegurarNoUltimoAdmin(Usuario usuario, String accion) async {
    if (usuario.nivelUsuario != rolAdmin || usuario.estado != 'ACTIVO') {
      return;
    }
    final total = await roles.contarUsuariosActivos(usuario.rolId);
    if (total <= 1) {
      throw ConflictException(
        'Es la única cuenta con rol ADMIN activa: no se puede $accion. '
        'Crea o activa primero otra cuenta administradora.',
        code: 'ultimo_admin',
      );
    }
  }

  void _ensureNombreUsuario(String valor) {
    final limpio = valor.trim();
    if (!RegExp(r'^[\w.\-]{4,50}$').hasMatch(limpio)) {
      throw BadRequestException(
        'El campo "nombreUsuario" debe tener entre 4 y 50 caracteres y solo '
        'letras, números, punto, guion o guion bajo (recibido: "$valor").',
        code: 'usuario_invalido',
      );
    }
  }

  void _ensureContrasena(String valor) {
    if (valor.length < 8 || valor.length > 255) {
      throw BadRequestException(
        'El campo "contrasena" debe tener entre 8 y 255 caracteres '
        '(recibido: ${valor.length}).',
        code: 'contrasena_invalida',
      );
    }
    if (!cabeEnBcrypt(valor)) {
      // bcrypt solo admite 72 bytes: una clave más larga no podría guardarse.
      throw const BadRequestException(
        'La contraseña no puede superar los 72 bytes (límite de bcrypt).',
        code: 'contrasena_demasiada_larga',
      );
    }
  }
}
