import '../../domain/entities/recurso.dart';
import '../../domain/repositories/recurso_repository.dart';
import '../datasources/recurso_remote_datasource.dart';

/// Implementación del contrato [RecursoRepository] contra la API real.
final class RecursoRepositoryImpl implements RecursoRepository {
  RecursoRepositoryImpl(this._dataSource);

  final RecursoRemoteDataSource _dataSource;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) => _dataSource.listar(
    recurso,
    limit: limit,
    offset: offset,
    estado: estado,
    q: q,
    filtros: filtros,
  );

  @override
  Future<Recurso> obtener(String ruta) => _dataSource.obtener(ruta);

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      _dataSource.crear(ruta, body);

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      _dataSource.editar(ruta, body);

  @override
  Future<void> eliminar(String ruta) => _dataSource.eliminar(ruta);
}
