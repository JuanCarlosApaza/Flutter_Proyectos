import '../entities/unidad_medida.dart';

/// Contrato del repositorio de unidades de medida.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class UnidadMedidaRepository {
  Future<List<UnidadMedida>> findUnidades({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de unidades del listado con los mismos filtros (COUNT real).
  Future<int> countUnidades({String? estado, String? q});

  Future<UnidadMedida?> findUnidadById(int id);

  /// La unidad con ese código **y** en estado `ACTIVO` (`null` si no existe
  /// o está oculta): es la consulta con la que `Productos` valida la unidad
  /// de un producto antes de escribirla.
  Future<UnidadMedida?> findUnidadActivaByCodigo(String codigo);

  Future<UnidadMedida> insertUnidad({
    required String codigo,
    required String nombre,
    required String tipo,
    required int decimales,
    required String estado,
  });

  Future<UnidadMedida> updateUnidad(
    int id, {
    required String codigo,
    required String nombre,
    required String tipo,
    required int decimales,
    required String estado,
  });

  /// `true` si existía y se ocultó (borrado lógico).
  Future<bool> deleteUnidad(int id);
}
