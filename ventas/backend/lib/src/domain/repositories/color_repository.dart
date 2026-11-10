import '../entities/color.dart';

/// Contrato del repositorio de colores.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class ColorRepository {
  Future<List<Color>> findColores({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  });

  /// Total de colores del listado con los mismos filtros (COUNT real).
  Future<int> countColores({String? estado, String? q});

  Future<Color?> findColorById(int id);

  /// Color **vivo** (no `ELIMINADO`) con ese nombre, sin distinguir
  /// mayúsculas: la misma comprobación que hace el índice único parcial de
  /// la migración 022 (entre vivos el nombre es único; ocultar lo libera).
  Future<Color?> findColorVivoByNombre(String nombre);

  Future<Color> insertColor({
    required String nombre,
    String? codigoHex,
    required String estado,
  });

  Future<Color> updateColor(
    int id, {
    required String nombre,
    String? codigoHex,
    required String estado,
  });

  /// `true` si existía y se ocultó (borrado lógico: `estado = ELIMINADO`).
  Future<bool> deleteColor(int id);
}
