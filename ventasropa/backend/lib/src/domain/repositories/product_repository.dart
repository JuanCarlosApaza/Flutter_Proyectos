import '../entities/product.dart';
import '../entities/variante.dart';

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

  /// Producto con sus [Product.variantes] rellenadas; `null` si no existe.
  Future<Product?> findById(int id);

  /// Inserta el producto y sus variantes en **una transacción**.
  ///
  /// Si [variantes] viene vacío, se crea una variante única
  /// (talla «Única» / color «Único») con el stock del producto, de modo que
  /// toda prenda sea vendible desde el primer momento.
  Future<Product> insert(Product datos, {List<DatoVariante> variantes});

  /// Escribe únicamente los campos indicados en [campos] (nombres de
  /// campos de dominio); `null` en un campo enviado borra su valor.
  /// Actualización parcial con **guarda optimista**: cuando se pasa
  /// [versionEsperado], el `UPDATE` solo aplica si la columna `version`
  /// todavía coincide (otra persona no editó el producto entre leerlo y
  /// guardarlo); si no, la implementación lanza `409 producto_desactualizado`.
  ///
  /// El `stock` **no** se puede escribir aquí: el stock real vive en las
  /// variantes (`updateVariante`) y `productos.stock` es su agregado.
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
  });

  /// `true` si existía y se borró.
  Future<bool> delete(int id);

  // --- Variantes (talla + color: el stock real) ---------------------------

  /// Variantes del producto (incluidas las ocultas, para el editor de admin).
  Future<List<ProductoVariante>> findVariantes(int productoId);

  /// Variante con nombres de talla/color resueltos; `null` si no existe.
  Future<ProductoVariante?> findVarianteById(int id);

  /// Crea la variante y actualiza el agregado de `productos.stock` (+kardex)
  /// en la misma transacción.
  Future<ProductoVariante> insertVariante(int productoId, DatoVariante datos);

  /// Actualiza los campos indicados de la variante (p. ej. su `stock`,
  /// con recálculo del agregado y kardex `AJUSTE`).
  Future<ProductoVariante> updateVariante(
    int id,
    DatoVariante datos,
    Set<String> campos,
  );

  /// Borrado lógico de la variante. Lanza `409 variante_con_stock` si la
  /// variante todavía tiene existencias (ajústalas a 0 antes).
  Future<bool> deleteVariante(int id);
}
