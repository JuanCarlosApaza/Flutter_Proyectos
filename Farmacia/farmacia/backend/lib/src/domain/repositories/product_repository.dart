import '../entities/product.dart';

/// Contrato del repositorio de productos.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class ProductRepository {
  /// Lista los productos paginados, ordenados por nombre.
  ///
  /// [q] es búsqueda libre sobre todas las columnas de la fila (sin
  /// sensibilidad a mayúsculas ni acentos).
  Future<List<Product>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de filas del listado con los mismos filtros (COUNT real).
  Future<int> count({String? estado, String? q});

  Future<Product?> findById(int id);

  Future<Product> insert(Product datos);

  /// Escribe únicamente los campos indicados en [campos] (nombres de
  /// campos de dominio); `null` en un campo enviado borra su valor.
  /// Actualización parcial con **guarda optimista**: cuando se pasa
  /// [versionEsperado], el `UPDATE` solo aplica si la columna `version`
  /// todavía coincide (otra persona no editó el producto entre leerlo y
  /// guardarlo); si no, la implementación lanza `409 producto_desactualizado`.
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
  });

  /// `true` si existía y se borró.
  Future<bool> delete(int id);
}
