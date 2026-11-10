import '../../core/errors/app_exception.dart';
import '../entities/unidad_medida.dart';
import '../repositories/unidad_medida_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso del catálogo de **unidades de medida**: la tabla que decide
/// qué se puede vender (`KG`, `UN`, `CAJA`...) y con cuántos decimales admite
/// la cantidad de cada unidad.
///
/// Todas las reglas de negocio (código bien formado, tipo admitido, decimales
/// entre 0 y 3, existencia del registro) viven aquí, antes de tocar la BD.
final class Unidades {
  const Unidades({required this.repository});

  final UnidadMedidaRepository repository;

  Future<List<UnidadMedida>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findUnidades(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  /// Total de unidades del listado con los mismos filtros (COUNT real).
  Future<int> contar({String? estado, String? q}) => repository.countUnidades(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosGenerales, 'estado'),
    q: q,
  );

  Future<UnidadMedida> obtener(int id) async {
    final unidad = await repository.findUnidadById(id);
    if (unidad == null) {
      throw NotFoundException(
        'La unidad $id no existe.',
        code: 'unidad_no_encontrada',
      );
    }
    return unidad;
  }

  Future<UnidadMedida> crear({
    required String codigo,
    required String nombre,
    String tipo = 'UNIDAD',
    int decimales = 0,
    String estado = 'ACTIVO',
  }) async => repository.insertUnidad(
    codigo: ensureUnidad(codigo, campo: 'codigo'),
    nombre: ensureNombre(nombre, maximo: 50),
    tipo: ensureTipoUnidad(tipo),
    decimales: ensureDecimalesUnidad(decimales),
    estado: ensureEstado(estado, estadosGenerales, 'estado'),
  );

  /// Actualización parcial: lo que no venga conserva su valor actual.
  ///
  /// El **código no se puede cambiar**: es la referencia que llevan escrita
  /// `productos.unidad` y las líneas ya emitidas; renombrarlo dejaría esos
  /// productos apuntando a una unidad que ya no existe. Para otro símbolo se
  /// crea una unidad nueva y se cambian los productos.
  Future<UnidadMedida> actualizar(
    int id, {
    String? codigo,
    String? nombre,
    String? tipo,
    int? decimales,
    String? estado,
  }) async {
    final actual = await obtener(id);
    final codigoFinal = codigo == null
        ? actual.codigo
        : ensureUnidad(codigo, campo: 'codigo');
    if (codigoFinal != actual.codigo) {
      throw BadRequestException(
        'El código "${actual.codigo}" no se puede modificar: es la '
        'referencia que usan los productos. Crea otra unidad si necesitas '
        'otro símbolo.',
        code: 'codigo_inmutable',
      );
    }
    return repository.updateUnidad(
      id,
      codigo: actual.codigo,
      nombre: nombre == null ? actual.nombre : ensureNombre(nombre, maximo: 50),
      tipo: tipo == null ? actual.tipo : ensureTipoUnidad(tipo),
      decimales: decimales == null
          ? actual.decimales
          : ensureDecimalesUnidad(decimales),
      estado: ensureEstado(estado ?? actual.estado, estadosGenerales, 'estado'),
    );
  }

  /// Oculta la unidad (borrado lógico: la fila sigue en la BD).
  ///
  /// No se comprueba si hay productos usándola: los que ya la tienen
  /// conservan su código y siguen vendiéndose; lo que deja de poder hacerse
  /// es **elegirla de nuevo** en un producto.
  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteUnidad(id);
    if (!removed) {
      throw NotFoundException(
        'La unidad $id no existe.',
        code: 'unidad_no_encontrada',
      );
    }
  }

  /// Devuelve el código normalizado de una unidad que **existe y está
  /// activa**; si no, `400 unidad_invalida`.
  ///
  /// Es la comprobación que hace `Productos` antes de escribir
  /// `productos.unidad`: la forma del código la valida `ensureUnidad`, la
  /// existencia aquí, contra `unidades_medida`.
  Future<String> asegurarUnidadVigente(
    String? valor, {
    String campo = 'unidad',
  }) async {
    final codigo = ensureUnidad(valor, campo: campo);
    final unidad = await repository.findUnidadActivaByCodigo(codigo);
    if (unidad == null) {
      throw BadRequestException(
        'El campo "$campo" no corresponde a una unidad de medida activa '
        '(recibido: "$codigo"). Revisa el catálogo «Unidades».',
        code: 'unidad_invalida',
      );
    }
    return unidad.codigo;
  }
}
