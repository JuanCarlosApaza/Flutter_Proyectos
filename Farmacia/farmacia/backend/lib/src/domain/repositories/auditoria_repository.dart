import '../entities/auditoria.dart';

/// Contrato del repositorio de auditoría.
///
/// El dominio define el *qué*; `data/` decide el *cómo* (SQL, caché...).
abstract interface class AuditoriaRepository {
  /// Inserta un evento (la fecha la pone quien lo construye).
  Future<void> registrar(AuditoriaEvento evento);

  /// Eventos ordenados del más reciente al más antiguo, con filtros opcionales:
  /// [usuario] por búsqueda parcial (ILIKE), [desde]/[hasta] por fecha
  /// (ambos días **incluidos**), [entidad] y [accion] por igualdad exacta,
  /// y [q] como búsqueda libre sobre todas las columnas de la fila.
  Future<List<AuditoriaEvento>> listar({
    int limit = 50,
    int offset = 0,
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  });

  /// Total de eventos con **los mismos filtros** que [listar] (COUNT real).
  Future<int> count({
    String? usuario,
    DateTime? desde,
    DateTime? hasta,
    String? entidad,
    String? accion,
    String? q,
  });

  /// Borra los eventos anteriores a [fecha] y devuelve cuántos se borraron.
  Future<int> eliminarAntesDe(DateTime fecha);

  /// Vacía la tabla y devuelve cuántos eventos se borraron.
  Future<int> eliminarTodo();
}
