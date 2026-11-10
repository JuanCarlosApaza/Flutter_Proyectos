import '../entities/categoria.dart';
import '../entities/marca.dart';
import '../entities/talla.dart';

/// Contrato del repositorio de categorías, tallas, colores y marcas.
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

  // --- Tallas -----------------------------------------------------------
  Future<List<Talla>> findTallas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de tallas del listado con los mismos filtros (COUNT real).
  Future<int> countTallas({String? estado, String? q});

  Future<Talla?> findTallaById(int id);

  Future<Talla> insertTalla({
    required String nombre,
    required int orden,
    required String estado,
  });

  Future<Talla> updateTalla(
    int id, {
    required String nombre,
    required int orden,
    required String estado,
  });

  Future<bool> deleteTalla(int id);

  // --- Colores ----------------------------------------------------------
  Future<List<ColorRopa>> findColores({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de colores del listado con los mismos filtros (COUNT real).
  Future<int> countColores({String? estado, String? q});

  Future<ColorRopa?> findColorById(int id);

  Future<ColorRopa> insertColor({
    required String nombre,
    String? codigoHex,
    required String estado,
  });

  Future<ColorRopa> updateColor(
    int id, {
    required String nombre,
    String? codigoHex,
    required String estado,
  });

  Future<bool> deleteColor(int id);

  // --- Marcas ------------------------------------------------------------
  Future<List<Marca>> findMarcas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de marcas del listado con los mismos filtros (COUNT real).
  Future<int> countMarcas({String? estado, String? q});

  Future<Marca?> findMarcaById(int id);

  Future<Marca> insertMarca({
    required String nombre,
    required String estado,
  });

  Future<Marca> updateMarca(
    int id, {
    required String nombre,
    required String estado,
  });

  Future<bool> deleteMarca(int id);
}
