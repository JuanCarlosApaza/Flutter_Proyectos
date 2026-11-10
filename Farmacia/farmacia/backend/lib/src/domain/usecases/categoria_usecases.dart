import '../../core/errors/app_exception.dart';
import '../entities/categoria.dart';
import '../repositories/categoria_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso de categorías y presentaciones: aquí vive la validación de
/// negocio (estados permitidos, existencia del registro...).
///
/// Cada clase agrupa las operaciones de un recurso para mantener el número de
/// archivos acotado sin mezclar capas.
final class Categorias {
  const Categorias({required this.repository});

  final CategoriaRepository repository;

  Future<List<Categoria>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findCategorias(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de categorías con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) =>
      repository.countCategorias(
        estado: estado == null
            ? null
            : ensureEstado(estado, estadosGenerales, 'estado'),
        q: q,
      );

  Future<Categoria> obtener(int id) async {
    final categoria = await repository.findCategoriaById(id);
    if (categoria == null) {
      throw NotFoundException(
        'La categoría $id no existe.',
        code: 'categoria_no_encontrada',
      );
    }
    return categoria;
  }

  Future<Categoria> crear({required String nombre, String estado = 'ACTIVO'}) =>
      repository.insertCategoria(
        nombre: ensureNombre(nombre),
        estado: ensureEstado(estado, estadosGenerales, 'estado'),
      );

  /// Actualización parcial: lo que no venga conserva su valor actual.
  Future<Categoria> actualizar(int id, {String? nombre, String? estado}) async {
    final actual = await obtener(id);
    return repository.updateCategoria(
      id,
      nombre: nombre == null ? actual.nombre : ensureNombre(nombre),
      estado: ensureEstado(estado ?? actual.estado, estadosGenerales, 'estado'),
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteCategoria(id);
    if (!removed) {
      throw NotFoundException(
        'La categoría $id no existe.',
        code: 'categoria_no_encontrada',
      );
    }
  }
}

/// Casos de uso de presentaciones (comprimido, jarabe...).
final class Presentaciones {
  const Presentaciones({required this.repository});

  final CategoriaRepository repository;

  Future<List<Presentacion>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findPresentaciones(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de presentaciones con los mismos filtros que [listar] (COUNT).
  Future<int> contar({String? estado, String? q}) =>
      repository.countPresentaciones(
        estado: estado == null
            ? null
            : ensureEstado(estado, estadosGenerales, 'estado'),
        q: q,
      );

  Future<Presentacion> obtener(int id) async {
    final presentacion = await repository.findPresentacionById(id);
    if (presentacion == null) {
      throw NotFoundException(
        'La presentación $id no existe.',
        code: 'presentacion_no_encontrada',
      );
    }
    return presentacion;
  }

  Future<Presentacion> crear({
    required String nombre,
    String estado = 'ACTIVO',
  }) => repository.insertPresentacion(
    nombre: ensureNombre(nombre),
    estado: ensureEstado(estado, estadosGenerales, 'estado'),
  );

  /// Actualización parcial: lo que no venga conserva su valor actual.
  Future<Presentacion> actualizar(
    int id, {
    String? nombre,
    String? estado,
  }) async {
    final actual = await obtener(id);
    return repository.updatePresentacion(
      id,
      nombre: nombre == null ? actual.nombre : ensureNombre(nombre),
      estado: ensureEstado(estado ?? actual.estado, estadosGenerales, 'estado'),
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deletePresentacion(id);
    if (!removed) {
      throw NotFoundException(
        'La presentación $id no existe.',
        code: 'presentacion_no_encontrada',
      );
    }
  }
}
