import '../../core/errors/app_exception.dart';
import '../entities/rol.dart';
import '../repositories/rol_repository.dart';
import '../rules/estados.dart';

/// Nombre del rol de acceso total (semilla `009_roles_permisos`).
///
/// Su identidad no se toca: ni renombrarlo, ni editarle permisos, ni
/// desactivarlo desde la API.
const String rolAdmin = 'ADMIN';

/// Casos de uso de roles (RBAC): quién puede ver/crear/editar/eliminar en
/// cada módulo.
///
/// Reglas de protección:
///
/// * El rol [rolAdmin] no se modifica (siempre tiene los 56 permisos:
///   los 14 módulos × 4 acciones).
/// * Los roles de sistema (`Es_Sistema`) no se borran.
/// * Un rol asignado a usuarios activos no se borra.
final class Roles {
  const Roles({required this.repository});

  final RolRepository repository;

  Future<List<Rol>> listar({int limit = 50, int offset = 0, String? estado}) =>
      repository.findAll(
        limit: limit.clamp(1, 200),
        offset: offset.clamp(0, 100000),
        estado: estado == null
            ? null
            : ensureEstado(estado, estadosGenerales, 'estado'),
      );

  Future<Rol> obtener(int id) async {
    final rol = await repository.findById(id);
    if (rol == null) {
      throw NotFoundException(
        'El rol $id no existe.',
        code: 'rol_no_encontrado',
      );
    }
    return rol;
  }

  Future<Rol> crear({
    required String nombre,
    String? descripcion,
    Set<String> permisos = const {},
  }) {
    final limpio = _ensureNombre(nombre);
    final validos = _ensurePermisos(permisos);
    return repository.insert(
      Rol(
        id: 0,
        nombre: limpio,
        descripcion: _descripcion(descripcion),
        esSistema: false,
        estado: 'ACTIVO',
        permisos: validos,
        fechaCreacion: DateTime.now(),
        fechaActualizacion: DateTime.now(),
      ),
      validos,
    );
  }

  /// Actualización parcial: lo que no venga no se toca. Un `permisos` no
  /// nulo reemplaza el conjunto completo.
  Future<Rol> actualizar(
    int id, {
    String? nombre,
    String? descripcion,
    Set<String>? permisos,
    String? estado,
  }) async {
    final actual = await obtener(id);
    if (actual.nombre == rolAdmin) {
      throw const ConflictException(
        'El rol ADMIN tiene acceso total y no se puede modificar.',
        code: 'rol_protegido',
      );
    }

    final campos = <String>{};
    String? nombreNuevo;
    String? descripcionNueva;
    String? estadoNuevo;
    Set<String>? permisosNuevos;

    if (nombre != null) {
      nombreNuevo = _ensureNombre(nombre);
      campos.add('nombre');
    }
    if (descripcion != null) {
      descripcionNueva = _descripcion(descripcion);
      campos.add('descripcion');
    }
    if (estado != null) {
      estadoNuevo = ensureEstado(estado, estadosGenerales, 'estado');
      campos.add('estado');
    }
    if (permisos != null) {
      permisosNuevos = _ensurePermisos(permisos);
    }
    if (campos.isEmpty && permisosNuevos == null) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }

    return repository.update(
      id,
      Rol(
        id: id,
        nombre: nombreNuevo ?? actual.nombre,
        // `''` en la petición significa "sin descripción" → `null`.
        descripcion: campos.contains('descripcion')
            ? descripcionNueva
            : actual.descripcion,
        esSistema: actual.esSistema,
        estado: estadoNuevo ?? actual.estado,
        permisos: actual.permisos,
        fechaCreacion: actual.fechaCreacion,
        fechaActualizacion: actual.fechaActualizacion,
      ),
      campos,
      permisos: permisosNuevos,
    );
  }

  Future<void> eliminar(int id) async {
    final actual = await obtener(id);
    if (actual.esSistema) {
      throw const ConflictException(
        'Los roles de sistema no se pueden eliminar.',
        code: 'rol_sistema',
      );
    }
    final enUso = await repository.contarUsuariosActivos(id);
    if (enUso > 0) {
      throw ConflictException(
        'El rol está asignado a $enUso usuario(s) activo(s): reasígnalos '
        'antes de eliminarlo.',
        code: 'rol_en_uso',
      );
    }
    final ocultado = await repository.delete(id);
    if (!ocultado) {
      throw NotFoundException(
        'El rol $id no existe.',
        code: 'rol_no_encontrado',
      );
    }
  }

  String _ensureNombre(String valor) {
    final limpio = valor.trim();
    if (limpio.length < 3 || limpio.length > 50) {
      throw BadRequestException(
        'El campo "nombre" debe tener entre 3 y 50 caracteres '
        '(recibido: "$valor").',
        code: 'nombre_invalido',
      );
    }
    return limpio;
  }

  /// Valida la forma `modulo.accion`; la existencia de cada permiso en el
  /// catálogo `Permisos` la comprueba el repositorio (devuelve `400`).
  Set<String> _ensurePermisos(Set<String> permisos) {
    final limpios = <String>{};
    for (final permiso in permisos) {
      final limpio = permiso.trim();
      if (limpio.isEmpty) continue;
      if (!RegExp(r'^[a-z][a-z0-9_]*\.(ver|crear|editar|eliminar)$')
          .hasMatch(limpio)) {
        throw BadRequestException(
          'Permiso inválido: "$permiso" (se espera "modulo.accion", p. ej. '
          '"productos.editar").',
          code: 'permiso_invalido',
        );
      }
      limpios.add(limpio);
    }
    return limpios;
  }

  String? _descripcion(String? valor) {
    if (valor == null) return null;
    final limpio = valor.trim();
    if (limpio.isEmpty) return null;
    if (limpio.length > 255) {
      throw const BadRequestException(
        'La descripción no puede superar 255 caracteres.',
        code: 'field_too_long',
      );
    }
    return limpio;
  }
}
