import '../../core/errors/app_exception.dart';
import '../entities/categoria.dart';
import '../entities/marca.dart';
import '../entities/talla.dart';
import '../repositories/categoria_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso de categorías: aquí vive la validación de negocio (estados
/// permitidos, existencia del registro...).
///
/// Cada clase agrupa las operaciones de un recurso para mantener el número de
/// archivos acotado sin mezclar capas; tallas, colores y marcas viven en las
/// clases [Tallas], [Colores] y [Marcas] de este mismo fichero.
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

/// Casos de uso de las tallas (`S`, `M`, `3`, `Única`...).
final class Tallas {
  const Tallas({required this.repository});

  final CategoriaRepository repository;

  Future<List<Talla>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findTallas(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de tallas con los mismos filtros que [listar] (COUNT).
  Future<int> contar({String? estado, String? q}) => repository.countTallas(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<Talla> obtener(int id) async {
    final talla = await repository.findTallaById(id);
    if (talla == null) {
      throw NotFoundException('La talla $id no existe.', code: 'talla_no_encontrada');
    }
    return talla;
  }

  Future<Talla> crear({
    required String nombre,
    int orden = 0,
    String estado = 'ACTIVO',
  }) => repository.insertTalla(
    nombre: ensureNombreTalla(nombre),
    orden: orden.clamp(0, 9999),
    estado: ensureEstado(estado, estadosGenerales, 'estado'),
  );

  /// Actualización parcial: lo que no venga conserva su valor actual.
  Future<Talla> actualizar(
    int id, {
    String? nombre,
    int? orden,
    String? estado,
  }) async {
    final actual = await obtener(id);
    return repository.updateTalla(
      id,
      nombre: nombre == null ? actual.nombre : ensureNombreTalla(nombre),
      orden: (orden ?? actual.orden).clamp(0, 9999),
      estado: ensureEstado(estado ?? actual.estado, estadosGenerales, 'estado'),
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteTalla(id);
    if (!removed) {
      throw NotFoundException('La talla $id no existe.', code: 'talla_no_encontrada');
    }
  }
}

/// Casos de uso de los colores (`Negro`, `Azul marino`...).
final class Colores {
  const Colores({required this.repository});

  final CategoriaRepository repository;

  Future<List<ColorRopa>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findColores(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de colores con los mismos filtros que [listar] (COUNT).
  Future<int> contar({String? estado, String? q}) => repository.countColores(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<ColorRopa> obtener(int id) async {
    final color = await repository.findColorById(id);
    if (color == null) {
      throw NotFoundException('El color $id no existe.', code: 'color_no_encontrado');
    }
    return color;
  }

  Future<ColorRopa> crear({
    required String nombre,
    String? codigoHex,
    String estado = 'ACTIVO',
  }) => repository.insertColor(
    nombre: ensureNombre(nombre, maximo: 50),
    codigoHex: ensureCodigoHex(codigoHex),
    estado: ensureEstado(estado, estadosGenerales, 'estado'),
  );

  /// Actualización parcial: lo que no venga conserva su valor actual.
  Future<ColorRopa> actualizar(
    int id, {
    String? nombre,
    String? codigoHex,
    String? estado,
  }) async {
    final actual = await obtener(id);
    return repository.updateColor(
      id,
      nombre: nombre == null ? actual.nombre : ensureNombre(nombre, maximo: 50),
      codigoHex: codigoHex == null ? actual.codigoHex : ensureCodigoHex(codigoHex),
      estado: ensureEstado(estado ?? actual.estado, estadosGenerales, 'estado'),
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteColor(id);
    if (!removed) {
      throw NotFoundException('El color $id no existe.', code: 'color_no_encontrado');
    }
  }
}

/// Casos de uso de las marcas (`Nike`, `Adidas`...).
///
/// Catálogo opcional: los productos pueden quedar sin marca (`marcaId`
/// anulable), de modo que aquí no hay reglas de dependencia con `productos`.
final class Marcas {
  const Marcas({required this.repository});

  final CategoriaRepository repository;

  Future<List<Marca>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findMarcas(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de marcas con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countMarcas(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<Marca> obtener(int id) async {
    final marca = await repository.findMarcaById(id);
    if (marca == null) {
      throw NotFoundException('La marca $id no existe.', code: 'marca_no_encontrada');
    }
    return marca;
  }

  Future<Marca> crear({required String nombre, String estado = 'ACTIVO'}) =>
      repository.insertMarca(
        nombre: ensureNombre(nombre),
        estado: ensureEstado(estado, estadosGenerales, 'estado'),
      );

  /// Actualización parcial: lo que no venga conserva su valor actual.
  Future<Marca> actualizar(int id, {String? nombre, String? estado}) async {
    final actual = await obtener(id);
    return repository.updateMarca(
      id,
      nombre: nombre == null ? actual.nombre : ensureNombre(nombre),
      estado: ensureEstado(estado ?? actual.estado, estadosGenerales, 'estado'),
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteMarca(id);
    if (!removed) {
      throw NotFoundException('La marca $id no existe.', code: 'marca_no_encontrada');
    }
  }
}
