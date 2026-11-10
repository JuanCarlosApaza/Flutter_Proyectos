import '../entities/usuario.dart';

/// Contrato del repositorio de usuarios del sistema.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class UsuarioRepository {
  Future<List<Usuario>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de filas del listado con los mismos filtros (COUNT real).
  Future<int> count({String? estado, String? q});

  Future<Usuario?> findById(int id);

  /// Busca por nombre de login (case-sensitive, único en la BD).
  ///
  /// Es la consulta del login: **incluye** la contraseña, que el resto de
  /// lecturas omiten.
  Future<Usuario?> findByNombreUsuario(String nombreUsuario);

  Future<Usuario> insert(Usuario datos);

  /// Escribe únicamente los campos indicados en [campos]; un campo enviado
  /// como `null` borra su valor (p. ej. `empleadoId`).
  Future<Usuario> update(int id, Usuario datos, Set<String> campos);

  Future<bool> delete(int id);
}
