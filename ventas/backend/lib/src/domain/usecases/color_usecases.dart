import '../../core/errors/app_exception.dart';
import '../entities/color.dart';
import '../repositories/color_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso del catálogo de colores: aquí vive la validación de negocio
/// (longitud del nombre, muestra hexadecimal, unicidad entre vivos...).
///
/// El índice único parcial de la 022 ya garantiza `LOWER(nombre)` entre
/// filas no `ELIMINADO`; la comprobación previa aquí es para responder con
/// un mensaje entendible (`color_duplicado`) en vez del error crudo de la BD.
final class Colores {
  const Colores({required this.repository});

  final ColorRepository repository;

  Future<List<Color>> listar({
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

  /// Total de colores con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countColores(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<Color> obtener(int id) async {
    final color = await repository.findColorById(id);
    if (color == null) {
      throw NotFoundException(
        'El color $id no existe.',
        code: 'color_no_encontrada',
      );
    }
    return color;
  }

  Future<Color> crear({
    required String nombre,
    String? codigoHex,
    String estado = 'ACTIVO',
  }) async {
    final limpio = ensureNombre(nombre, maximo: 50);
    final hex = ensureCodigoHex(codigoHex);
    await _asegurarNombreLibre(limpio);
    return repository.insertColor(
      nombre: limpio,
      codigoHex: hex,
      estado: ensureEstado(estado, estadosGenerales, 'estado'),
    );
  }

  /// Edición parcial: lo que no venga conserva su valor. `fijarCodigoHex`
  /// distingue «no se tocó» de «se mandó `null` para quitar la muestra».
  Future<Color> actualizar(
    int id, {
    String? nombre,
    String? codigoHex,
    bool fijarCodigoHex = false,
    String? estado,
  }) async {
    final actual = await obtener(id);
    final nombreFinal = nombre == null
        ? actual.nombre
        : ensureNombre(nombre, maximo: 50);
    final hexFinal = fijarCodigoHex
        ? ensureCodigoHex(codigoHex)
        : actual.codigoHex;
    final estadoFinal = ensureEstado(
      estado ?? actual.estado,
      estadosGenerales,
      'estado',
    );
    if (nombreFinal.toLowerCase() != actual.nombre.toLowerCase()) {
      await _asegurarNombreLibre(nombreFinal, exceptoId: id);
    }
    return repository.updateColor(
      id,
      nombre: nombreFinal,
      codigoHex: hexFinal,
      estado: estadoFinal,
    );
  }

  /// Ocultado lógico: el color sale de los listados y de los desplegables
  /// de asignación, pero las variantes existentes siguen mostrando su
  /// nombre congelado.
  Future<bool> eliminar(int id) async {
    await obtener(id);
    return repository.deleteColor(id);
  }

  /// El nombre entre colores vivos es único sin distinguir mayúsculas
  /// (índice parcial de la 022); ocultar un color libera su nombre.
  Future<void> _asegurarNombreLibre(String nombre, {int? exceptoId}) async {
    final existente = await repository.findColorVivoByNombre(nombre);
    if (existente != null && existente.id != exceptoId) {
      throw ConflictException(
        'Ya existe un color con el nombre "${existente.nombre}".',
        code: 'color_duplicado',
      );
    }
  }
}
