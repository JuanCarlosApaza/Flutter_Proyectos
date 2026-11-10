import '../../core/errors/app_exception.dart';
import '../entities/marca.dart';
import '../repositories/marca_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso del catálogo de marcas: aquí vive la validación de negocio
/// (longitud del nombre, unicidad entre vivos...). Es un catálogo de texto
/// puro: sin muestra hexadecimal ni variantes de stock.
///
/// El índice único parcial de la 023 ya garantiza `LOWER(nombre)` entre
/// filas no `ELIMINADO`; la comprobación previa aquí es para responder con
/// un mensaje entendible (`marca_duplicado`) en vez del error crudo de la BD.
final class Marcas {
  const Marcas({required this.repository});

  final MarcaRepository repository;

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
      throw NotFoundException(
        'La marca $id no existe.',
        code: 'marca_no_encontrada',
      );
    }
    return marca;
  }

  Future<Marca> crear({
    required String nombre,
    String estado = 'ACTIVO',
  }) async {
    final limpio = ensureNombre(nombre, maximo: 50);
    await _asegurarNombreLibre(limpio);
    return repository.insertMarca(
      nombre: limpio,
      estado: ensureEstado(estado, estadosGenerales, 'estado'),
    );
  }

  /// Edición parcial: lo que no venga conserva su valor.
  Future<Marca> actualizar(
    int id, {
    String? nombre,
    String? estado,
  }) async {
    final actual = await obtener(id);
    final nombreFinal = nombre == null
        ? actual.nombre
        : ensureNombre(nombre, maximo: 50);
    final estadoFinal = ensureEstado(
      estado ?? actual.estado,
      estadosGenerales,
      'estado',
    );
    if (nombreFinal.toLowerCase() != actual.nombre.toLowerCase()) {
      await _asegurarNombreLibre(nombreFinal, exceptoId: id);
    }
    return repository.updateMarca(
      id,
      nombre: nombreFinal,
      estado: estadoFinal,
    );
  }

  /// Ocultado lógico: la marca sale de los listados y de los desplegables
  /// de asignación, pero los productos que ya la llevan siguen mostrándola
  /// en su tabla e histórico (no se reescribe nada).
  Future<bool> eliminar(int id) async {
    await obtener(id);
    return repository.deleteMarca(id);
  }

  /// Devuelve el id de una marca que **existe**; `null` sigue siendo `null`
  /// (producto sin marca). Es la comprobación que hace `Productos` antes de
  /// escribir `productos.marca_id` — `400 marca_no_encontrada` si el id no
  /// apunta a ninguna fila del catálogo.
  Future<int?> asegurarMarcaVigente(int? id, {String campo = 'marcaId'}) async {
    if (id == null) return null;
    final marca = await repository.findMarcaById(id);
    if (marca == null) {
      throw BadRequestException(
        'El campo "$campo" no corresponde a una marca del catálogo '
        '(recibido: $id). Revisa la pestaña «Marcas».',
        code: 'marca_no_encontrada',
      );
    }
    return marca.id;
  }

  /// El nombre entre marcas vivas es único sin distinguir mayúsculas
  /// (índice parcial de la 023); ocultar una marca libera su nombre.
  Future<void> _asegurarNombreLibre(String nombre, {int? exceptoId}) async {
    final existente = await repository.findMarcaVivaByNombre(nombre);
    if (existente != null && existente.id != exceptoId) {
      throw ConflictException(
        'Ya existe una marca con el nombre "${existente.nombre}".',
        code: 'marca_duplicado',
      );
    }
  }
}
