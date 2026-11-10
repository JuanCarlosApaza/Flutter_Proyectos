import '../entities/categoria.dart';

/// Contrato del repositorio de categorías y presentaciones.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class CategoriaRepository {
  // --- Categorías -------------------------------------------------------
  Future<List<Categoria>> findCategorias({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de categorías del listado con los mismos filtros (COUNT real).
  Future<int> countCategorias({String? estado, String? q});

  Future<Categoria?> findCategoriaById(int id);

  Future<Categoria> insertCategoria({
    required String nombre,
    required String estado,
  });

  Future<Categoria> updateCategoria(
    int id, {
    required String nombre,
    required String estado,
  });

  /// `true` si existía y se borró.
  Future<bool> deleteCategoria(int id);

  // --- Presentaciones ---------------------------------------------------
  Future<List<Presentacion>> findPresentaciones({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de presentaciones del listado con los mismos filtros (COUNT real).
  Future<int> countPresentaciones({String? estado, String? q});

  Future<Presentacion?> findPresentacionById(int id);

  Future<Presentacion> insertPresentacion({
    required String nombre,
    required String estado,
  });

  Future<Presentacion> updatePresentacion(
    int id, {
    required String nombre,
    required String estado,
  });

  Future<bool> deletePresentacion(int id);
}
