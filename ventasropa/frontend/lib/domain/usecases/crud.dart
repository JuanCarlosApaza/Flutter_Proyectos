import '../entities/recurso.dart';
import '../repositories/recurso_repository.dart';

/// Casos de uso del CRUD genérico.
///
/// Capa `domain`: un caso de uso por operación (listar/crear/editar/
/// eliminar) que delega en el repositorio. Los sub-recursos de venta
/// (`ordenes/{id}/estado`, `facturas`) se manejan pasando la ruta completa.
final class Crud {
  const Crud({required this.repository});

  final RecursoRepository repository;

  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) => repository.listar(
    recurso,
    limit: limit,
    offset: offset,
    estado: estado,
    q: q,
    filtros: filtros,
  );

  /// Lee **un** registro con sus sub-recursos (`ordenes/1` → cabecera +
  /// `detalles`).
  Future<Recurso> obtener(String ruta) => repository.obtener(ruta);

  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      repository.crear(ruta, body);

  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      repository.editar(ruta, body);

  Future<void> eliminar(String ruta) => repository.eliminar(ruta);
}
