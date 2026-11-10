import '../entities/recurso.dart';

/// Contrato del acceso a los recursos de la API (`/api/v1/...`).
///
/// Todas las rutas son relativas a `/api/v1/`, p. ej. `clientes` o
/// `ordenes/12/estado`.
abstract interface class RecursoRepository {
  /// [filtros] son parámetros de query extra (`usuario`, `desde`, `hasta`…)
  /// que se envían tal cual a la API (p. ej. la auditoría).
  /// [q] es búsqueda libre server-side (`?q=`).
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  });

  /// `GET /api/v1/{ruta}` de **un** registro (p. ej. `ordenes/1`, que
  /// devuelve la cabecera más su campo `detalles`).
  Future<Recurso> obtener(String ruta);

  Future<Recurso> crear(String ruta, Map<String, Object?> body);

  Future<Recurso> editar(String ruta, Map<String, Object?> body);

  Future<void> eliminar(String ruta);
}
