import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
import '../repositories/product_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';
import 'marca_usecases.dart';
import 'unidad_medida_usecases.dart';

/// Casos de uso de productos.
///
/// Todas las reglas de negocio (estados permitidos, precios y stock no
/// negativos, existencia del registro) viven aquí, antes de tocar la BD.
///
/// La **unidad de venta** se valida en dos pasos: la forma del código con
/// `ensureUnidad` y la existencia en el catálogo con [unidades]
/// (`asegurarUnidadVigente`), porque desde la 017_unidades_medida qué se
/// puede vender lo decide la tabla `unidades_medida` y no una lista fija.
/// La **marca** sigue el mismo patrón con [marcas]
/// (`asegurarMarcaVigente`): el producto puede no tener marca, pero si la
/// trae tiene que existir en el catálogo.
final class Productos {
  const Productos({
    required this.repository,
    required this.unidades,
    required this.marcas,
  });

  final ProductRepository repository;

  /// Catálogo de unidades de medida (valida que la unidad exista y esté
  /// activa antes de escribir `productos.unidad`).
  final Unidades unidades;

  /// Catálogo de marcas (valida `productos.marca_id` antes de escribirlo).
  final Marcas marcas;

  Future<List<Product>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
    int? marcaId,
  }) => repository.findAll(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosProductos, 'estado'),
    q: q,
    marcaId: marcaId,
  );

  /// Total de productos del listado con los mismos filtros (para el
  /// paginado del frontend). El `q` no se valida: solo se pasa.
  Future<int> contar({String? estado, String? q, int? marcaId}) =>
      repository.count(
        estado: estado == null
            ? null
            : ensureEstado(estado, estadosProductos, 'estado'),
        q: q,
        marcaId: marcaId,
      );

  Future<Product> obtener(int id) async {
    final producto = await repository.findById(id);
    if (producto == null) {
      throw NotFoundException(
        'El producto $id no existe.',
        code: 'producto_no_encontrado',
      );
    }
    return producto;
  }

  /// ¿Ya existe un producto con esa clave de duplicado? Lo usa la
  /// importación masiva (`POST /products/importar`) para saltarse los
  /// repetidos con aviso: re-subir el mismo archivo no duplica nada.
  Future<bool> existe({
    String? codigo,
    String? nombre,
    int? categoriaId,
    int? presentacionId,
  }) => repository.existe(
    codigo: codigo,
    nombre: nombre,
    categoriaId: categoriaId,
    presentacionId: presentacionId,
  );

  Future<Product> crear({
    required String nombre,
    required double precioVenta,
    String? codigo,
    String? imagen,
    String? descripcion,
    String? unidad,
    double? precioCompra,
    double? precioRebaja,
    DateTime? fechaVencimiento,
    double stock = 0,
    double? stockMinimo,
    int? categoriaId,
    int? proveedorId,
    int? presentacionId,
    int? marcaId,
    int? garantiaMeses,
    String estado = 'DISPONIBLE',
    List<VarianteEntrada> variantes = const [],
  }) async {
    // El precio de venta debe ser > 0, caber en NUMERIC(10, 2) y no bajar
    // del precio de compra (todo en una sola regla, con redondeo a 2 decimales).
    final precioFinal = ensurePrecioVenta(precioVenta, precioCompra);
    // El tope de rebaja por unidad no puede superar el precio de venta.
    final rebajaFinal = ensurePrecioRebaja(precioRebaja, precioFinal);
    final stockFinal = ensureNoNegativo(stock, 'stock');
    final minimo = stockMinimo == null
        ? null
        : ensureNoNegativo(stockMinimo, 'stockMinimo');
    ensureFechaNoVencida(fechaVencimiento);
    // Unidad del catálogo (`unidades_medida` y activa); `null` → `UN`.
    final unidadFinal = await unidades.asegurarUnidadVigente(unidad);
    // Marca del catálogo (`null` = producto sin marca) y meses de garantía.
    final marcaFinal = await marcas.asegurarMarcaVigente(marcaId);
    final garantiaFinal = ensureGarantiaMeses(garantiaMeses);
    return repository.insert(
      Product(
        id: 0,
        nombre: ensureNombre(nombre),
        codigo: ensureCodigo(codigo),
        imagen: imagen,
        descripcion: ensureDescripcion(descripcion),
        unidad: unidadFinal,
        precioVenta: precioFinal,
        precioCompra: precioCompra == null ? null : dinero(precioCompra),
        precioRebaja: rebajaFinal,
        fechaVencimiento: fechaVencimiento,
        stock: stockFinal,
        stockMinimo: minimo,
        categoriaId: categoriaId,
        proveedorId: proveedorId,
        presentacionId: presentacionId,
        marcaId: marcaFinal,
        garantiaMeses: garantiaFinal,
        estado: ensureEstado(estado, estadosProductos, 'estado'),
      ),
      variantes: _asegurarVariantes(variantes),
    );
  }

  /// Actualización parcial: solo se escriben los campos de [campos] y cada
  /// regla se aplica únicamente si el campo correspondiente se envía.
  ///
  /// [versionEsperado] activa la guarda optimista (ver
  /// `ProductRepository.update`): `409 producto_desactualizado` si otra
  /// persona editó el producto primero.
  Future<Product> actualizar(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
    List<VarianteEntrada>? variantes,
  }) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    if (campos.contains('stock')) {
      ensureNoNegativo(datos.stock, 'stock');
    }
    if (campos.contains('stockMinimo') && datos.stockMinimo != null) {
      ensureNoNegativo(datos.stockMinimo!, 'stockMinimo');
    }

    // Se recupera primero el registro para poder validar con los valores
    // vigentes lo que no se envía en esta petición (actualización parcial).
    final actual = await obtener(id);
    final precioVenta = campos.contains('precioVenta')
        ? datos.precioVenta
        : actual.precioVenta;
    final precioCompra = campos.contains('precioCompra')
        ? datos.precioCompra
        : actual.precioCompra;
    final precioRebaja = campos.contains('precioRebaja')
        ? datos.precioRebaja
        : actual.precioRebaja;
    var rebajaValidada = precioRebaja;
    if (campos.contains('precioVenta') ||
        campos.contains('precioCompra') ||
        campos.contains('precioRebaja')) {
      // Regla cruzada: el par venta/compra debe seguir siendo coherente y el
      // tope de rebaja por debajo del precio de venta, aunque solo se haya
      // enviado uno de los campos.
      final precioFinal = ensurePrecioVenta(precioVenta, precioCompra);
      rebajaValidada = ensurePrecioRebaja(precioRebaja, precioFinal);
    }
    if (campos.contains('fechaVencimiento')) {
      ensureFechaNoVencida(datos.fechaVencimiento);
    }
    // Marca y garantía solo se validan si viajan en esta petición: `null`
    // explícito las limpia (producto sin marca / sin garantía).
    if (campos.contains('marcaId')) {
      await marcas.asegurarMarcaVigente(datos.marcaId);
    }
    if (campos.contains('garantiaMeses')) {
      ensureGarantiaMeses(datos.garantiaMeses);
    }

    // La unidad solo se valida si se envía en esta petición: si no, se
    // conserva la vigente (un producto puede seguir vendiéndose con una
    // unidad que ya no se pueda elegir en el catálogo).
    final unidadFinal = campos.contains('unidad')
        ? await unidades.asegurarUnidadVigente(datos.unidad)
        : actual.unidad;

    return repository.update(
      id,
      Product(
        id: id,
        nombre: campos.contains('nombre')
            ? ensureNombre(datos.nombre)
            : datos.nombre,
        codigo: campos.contains('codigo')
            ? ensureCodigo(datos.codigo)
            : actual.codigo,
        imagen: datos.imagen,
        descripcion: campos.contains('descripcion')
            ? ensureDescripcion(datos.descripcion)
            : actual.descripcion,
        unidad: unidadFinal,
        precioVenta: campos.contains('precioVenta')
            ? dinero(precioVenta)
            : datos.precioVenta,
        precioCompra:
            campos.contains('precioCompra') && datos.precioCompra != null
            ? dinero(datos.precioCompra!)
            : datos.precioCompra,
        precioRebaja: rebajaValidada,
        fechaVencimiento: datos.fechaVencimiento,
        stock: datos.stock,
        stockMinimo: campos.contains('stockMinimo')
            ? datos.stockMinimo
            : actual.stockMinimo,
        categoriaId: datos.categoriaId,
        proveedorId: datos.proveedorId,
        presentacionId: datos.presentacionId,
        marcaId: datos.marcaId,
        garantiaMeses: datos.garantiaMeses,
        estado: campos.contains('estado')
            ? ensureEstado(datos.estado, estadosProductos, 'estado')
            : actual.estado,
      ),
      campos,
      versionEsperado: versionEsperado,
      variantes: variantes == null ? null : _asegurarVariantes(variantes),
    );
  }

  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.delete(id);
    if (!removed) {
      throw NotFoundException(
        'El producto $id no existe.',
        code: 'producto_no_encontrado',
      );
    }
  }

  /// Valida las filas de `variantes` del cuerpo antes de tocar la BD:
  /// cada fila necesita un color (`colorId` o `color`), cantidad ≥ 0 y no
  /// puede repetirse el mismo color dos veces (`variante_duplicada`).
  ///
  /// La existencia/autocreación del color la resuelve el repositorio dentro
  /// de su transacción (dos altas simultáneas con el mismo color nuevo no
  /// pueden duplicarlo: lo impide el índice único parcial de la 022).
  List<VarianteEntrada> _asegurarVariantes(List<VarianteEntrada> entradas) {
    final filas = <VarianteEntrada>[];
    final vistos = <String>{};
    for (final fila in entradas) {
      final tieneId = fila.colorId != null;
      final tieneNombre = (fila.color ?? '').trim().isNotEmpty;
      if (!tieneId && !tieneNombre) {
        throw const BadRequestException(
          'Cada variante necesita un color ("colorId" o "color").',
          code: 'variante_invalida',
        );
      }
      if (tieneId && fila.colorId! <= 0) {
        throw BadRequestException(
          'El "colorId" ${fila.colorId} no es válido.',
          code: 'variante_invalida',
        );
      }
      // La misma clave de color dos veces en el cuerpo: el mismo producto
      // con dos filas del mismo color violaría la clave única de variantes.
      final clave = tieneId
          ? 'id:${fila.colorId}'
          : 'nom:${fila.color!.trim().toLowerCase()}';
      if (!vistos.add(clave)) {
        throw BadRequestException(
          'El color ${tieneId ? fila.colorId : '"${fila.color!.trim()}"'} '
          'aparece más de una vez en las variantes del producto.',
          code: 'variante_duplicada',
        );
      }
      filas.add(
        VarianteEntrada(
          colorId: fila.colorId,
          color: tieneNombre ? fila.color!.trim() : null,
          cantidad: ensureNoNegativo(fila.cantidad, 'cantidad'),
        ),
      );
    }
    return filas;
  }
}
