import '../entities/marca.dart';

/// Contrato del repositorio de marcas.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class MarcaRepository {
  Future<List<Marca>> findMarcas({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de marcas del listado con los mismos filtros (COUNT real).
  Future<int> countMarcas({String? estado, String? q});

  Future<Marca?> findMarcaById(int id);

  /// Marca **viva** (no `ELIMINADO`) con ese nombre, sin distinguir
  /// mayúsculas: la misma comprobación que hace el índice único parcial de
  /// la migración 023 (entre vivas el nombre es único; ocultar lo libera).
  Future<Marca?> findMarcaVivaByNombre(String nombre);

  Future<Marca> insertMarca({required String nombre, required String estado});

  Future<Marca> updateMarca(
    int id, {
    required String nombre,
    required String estado,
  });

  /// `true` si existía y se ocultó (borrado lógico: `estado = ELIMINADO`).
  Future<bool> deleteMarca(int id);
}
