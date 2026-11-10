import '../entities/ajuste.dart';

/// Contrato del repositorio de ajustes globales.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, transacciones).
abstract interface class AjusteRepository {
  /// Todos los ajustes guardados, ordenados por clave.
  Future<List<Ajuste>> findAjustes({int limit = 200, int offset = 0});

  /// Inserta o actualiza cada ajuste del lote (upsert por la clave natural
  /// `clave`) en **una sola transacción**: si algo falla a mitad, no queda
  /// el lote guardado a medias.
  Future<void> upsertAjustes(Map<String, String> valores);
}
