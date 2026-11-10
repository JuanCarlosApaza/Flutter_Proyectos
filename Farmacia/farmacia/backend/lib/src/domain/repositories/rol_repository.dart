import '../entities/rol.dart';

/// Contrato del repositorio de roles (RBAC).
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class RolRepository {
  Future<List<Rol>> findAll({int limit = 50, int offset = 0, String? estado});

  Future<Rol?> findById(int id);

  /// Permisos (`modulo.accion`) de un rol.
  Future<Set<String>> permisosDeRol(int rolId);

  /// Permisos de **todos** los roles, agrupados por `rol_id` (una sola
  /// consulta para los listados).
  Future<Map<int, Set<String>>> permisosPorRol();

  /// Crea el rol y le escribe [permisos] en la misma transacción.
  ///
  /// Lanza `400` si algún permiso no existe en el catálogo `Permisos`.
  Future<Rol> insert(Rol datos, Set<String> permisos);

  /// Actualización parcial; si [permisos] no es `null`, se reemplaza el
  /// conjunto completo de permisos del rol.
  Future<Rol> update(
    int id,
    Rol datos,
    Set<String> campos, {
    Set<String>? permisos,
  });

  /// Borrado lógico (`estado = 'ELIMINADO'`).
  Future<bool> delete(int id);

  /// Nº de usuarios `ACTIVO` asignados al rol.
  Future<int> contarUsuariosActivos(int rolId);
}
