import '../entities/product.dart';

/// Contrato del repositorio de productos.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class ProductRepository {
  /// Lista los productos paginados, ordenados por nombre.
  ///
  /// [q] es búsqueda libre sobre la fila completa — incluido el nombre de la
  /// marca, que se une por subconsulta (sin sensibilidad a mayúsculas ni
  /// acentos). [marcaId] filtra por la marca del desplegable de la tabla.
  Future<List<Product>> findAll({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
    int? marcaId,
  });

  /// Total de filas del listado con los mismos filtros (COUNT real).
  Future<int> count({String? estado, String? q, int? marcaId});

  Future<Product?> findById(int id);

  /// ¿Ya existe un producto con esa clave de duplicado?
  ///
  /// Lo usa la importación masiva para saltarse los repetidos con aviso
  /// (re-subir el mismo archivo no duplica nada). Con [codigo] se compara
  /// ese código (hay índice único cuando no está vacío); sin código, el
  /// nombre exacto **junto con** su categoría y presentación — dos productos
  /// pueden llamarse igual si van en distinta categoría.
  ///
  /// Solo se miran filas vivas (`estado <> 'ELIMINADO'`).
  Future<bool> existe({
    String? codigo,
    String? nombre,
    int? categoriaId,
    int? presentacionId,
  });

  /// Inserta el producto y sus variantes en **una transacción**.
  ///
  /// [variantes] es la lista de filas del cuerpo (`{colorId|color,
  /// cantidad}`): si trae filas, el `stock` agregado del producto pasa a ser
  /// su suma (el [datos].stock se ignora); si está vacía, nace la variante
  /// «Único» con el stock del cuerpo.
  Future<Product> insert(Product datos, {List<VarianteEntrada> variantes});

  /// Escribe únicamente los campos indicados en [campos] (nombres de
  /// campos de dominio); `null` en un campo enviado borra su valor.
  /// Actualización parcial con **guarda optimista**: cuando se pasa
  /// [versionEsperado], el `UPDATE` solo aplica si la columna `version`
  /// todavía coincide (otra persona no editó el producto entre leerlo y
  /// guardarlo); si no, la implementación lanza `409 producto_desactualizado`.
  ///
  /// [variantes] (`null` = no se tocan): con lista no vacía se reescriben
  /// las variantes y el stock agregado pasa a ser su suma; con lista vacía
  /// el producto vuelve a la variante «Único» con el stock del cuerpo. Si
  /// no viene [variantes] y sí `stock` con varias variantes vivas, la
  /// implementación lanza `400 stock_por_variante`.
  Future<Product> update(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
    List<VarianteEntrada>? variantes,
  });

  /// `true` si existía y se borró.
  Future<bool> delete(int id);
}
