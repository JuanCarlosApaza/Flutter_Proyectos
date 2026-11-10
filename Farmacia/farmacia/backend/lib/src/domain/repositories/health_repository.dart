/// Contrato (puerto) que la capa de dominio exige a la infraestructura.
///
/// El dominio **solo** conoce esta interfaz: la implementación concreta vive
/// en `data/`. Esto permite cambiar de BD o doblar el repositorio en tests.
abstract interface class HealthRepository {
  /// Devuelve `true` si la base de datos responde.
  Future<bool> isDatabaseAvailable();
}
