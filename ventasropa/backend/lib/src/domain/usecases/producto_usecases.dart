import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
import '../entities/variante.dart';
import '../repositories/product_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Casos de uso de productos.
///
/// Todas las reglas de negocio (estados permitidos, precios y stock no
/// negativos, existencia del registro) viven aquí, antes de tocar la BD.
final class Productos {
  const Productos({required this.repository});

  final ProductRepository repository;

  Future<List<Product>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findAll(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosProductos, 'estado'),
    q: q,
  );

  /// Total de productos del listado con los mismos filtros (para el
  /// paginado del frontend). El `q` no se valida: solo se pasa.
  Future<int> contar({String? estado, String? q}) => repository.count(
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosProductos, 'estado'),
    q: q,
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

  /// Crea el producto con sus variantes en una transacción.
  ///
  /// Si [variantes] viene vacío (producto «sin talla»), el repositorio crea
  /// una variante única (talla «Única» / color «Único») con [stock]; si sí
  /// viene, el stock de cada combinación se toma de [variantes] y [stock]
  /// se ignora (el stock real siempre es por variante).
  Future<Product> crear({
    required String nombre,
    required double precioVenta,
    String? codigo,
    String? imagen,
    String? descripcion,
    String? unidad,
    double? precioCompra,
    double? precioRebaja,
    double stock = 0,
    double? stockMinimo,
    int? categoriaId,
    int? marcaId,
    int? proveedorId,
    String estado = 'DISPONIBLE',
    List<DatoVariante> variantes = const [],
  }) {
    // El precio de venta debe ser > 0, caber en NUMERIC(10, 2) y no bajar
    // del precio de compra (todo en una sola regla, con redondeo a 2 decimales).
    final precioFinal = ensurePrecioVenta(precioVenta, precioCompra);
    // El tope de rebaja por unidad no puede superar el precio de venta.
    final rebajaFinal = ensurePrecioRebaja(precioRebaja, precioFinal);
    final stockFinal = ensureNoNegativo(stock, 'stock');
    final minimo = stockMinimo == null
        ? null
        : ensureNoNegativo(stockMinimo, 'stockMinimo');
    final variantesFinales = variantes.map(_asegurarVariante).toList();
    return repository.insert(
      Product(
        id: 0,
        nombre: ensureNombre(nombre),
        codigo: ensureCodigo(codigo),
        imagen: imagen,
        descripcion: ensureDescripcion(descripcion),
        unidad: ensureUnidad(unidad),
        precioVenta: precioFinal,
        precioCompra: precioCompra == null ? null : dinero(precioCompra),
        precioRebaja: rebajaFinal,
        stock: stockFinal,
        stockMinimo: minimo,
        categoriaId: categoriaId,
        marcaId: marcaId,
        proveedorId: proveedorId,
        estado: ensureEstado(estado, estadosProductos, 'estado'),
      ),
      variantes: variantesFinales,
    );
  }

  /// Actualización parcial: solo se escriben los campos de [campos] y cada
  /// regla se aplica únicamente si el campo correspondiente se envía.
  ///
  /// [versionEsperado] activa la guarda optimista (ver
  /// `ProductRepository.update`): `409 producto_desactualizado` si otra
  /// persona editó el producto primero.
  ///
  /// El `stock` **no** se puede editar aquí: usa [actualizarVariante].
  Future<Product> actualizar(
    int id,
    Product datos,
    Set<String> campos, {
    int? versionEsperado,
  }) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    if (campos.contains('stock')) {
      throw const BadRequestException(
        'El stock no se edita en el producto: edita sus variantes '
        '(talla + color) con PUT /api/v1/variantes/{id}.',
        code: 'stock_por_variante',
      );
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

    return repository.update(
      id,
      Product(
        id: id,
        nombre: campos.contains('nombre')
            ? ensureNombre(datos.nombre)
            : datos.nombre,
        codigo: campos.contains('codigo') ? ensureCodigo(datos.codigo) : actual.codigo,
        imagen: datos.imagen,
        descripcion: campos.contains('descripcion')
            ? ensureDescripcion(datos.descripcion)
            : datos.descripcion,
        unidad: campos.contains('unidad')
            ? ensureUnidad(datos.unidad)
            : actual.unidad,
        precioVenta: campos.contains('precioVenta')
            ? dinero(precioVenta)
            : datos.precioVenta,
        precioCompra:
            campos.contains('precioCompra') && datos.precioCompra != null
            ? dinero(datos.precioCompra!)
            : datos.precioCompra,
        precioRebaja: rebajaValidada,
        stock: actual.stock,
        stockMinimo: campos.contains('stockMinimo')
            ? datos.stockMinimo
            : actual.stockMinimo,
        categoriaId: datos.categoriaId,
        marcaId: datos.marcaId,
        proveedorId: datos.proveedorId,
        estado: campos.contains('estado')
            ? ensureEstado(datos.estado, estadosProductos, 'estado')
            : actual.estado,
      ),
      campos,
      versionEsperado: versionEsperado,
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

  // --- Variantes (talla + color: el stock real) ------------------------------

  /// Variantes del producto, visibles y ocultas (el editor de admin las
  /// muestra todas).
  Future<List<ProductoVariante>> listarVariantes(int productoId) async {
    await obtener(productoId);
    return repository.findVariantes(productoId);
  }

  /// Crea una variante; el stock del producto se recalcula en la BD.
  ///
  /// La combinación llega por id (`tallaId`/`colorId`) o por nombre
  /// (`talla`/`color`), igual que en el alta de producto.
  Future<ProductoVariante> crearVariante(
    int productoId, {
    int tallaId = 0,
    int colorId = 0,
    String? talla,
    String? color,
    double stock = 0,
    String? codigo,
  }) async {
    await obtener(productoId);
    return repository.insertVariante(
      productoId,
      // `_asegurarVariante` valida stock y código.
      _asegurarVariante(
        DatoVariante(
          tallaId: tallaId,
          colorId: colorId,
          talla: talla,
          color: color,
          stock: stock,
          codigo: codigo,
        ),
      ),
    );
  }

  /// Actualiza una variante (normalmente su `stock`); el agregado del
  /// producto y el kardex se actualizan en la BD.
  Future<ProductoVariante> actualizarVariante(
    int id,
    DatoVariante datos,
    Set<String> campos,
  ) async {
    if (campos.isEmpty) {
      throw const BadRequestException(
        'Indica al menos un campo a actualizar.',
        code: 'fields_required',
      );
    }
    final actual = await repository.findVarianteById(id);
    if (actual == null) {
      throw NotFoundException(
        'La variante $id no existe.',
        code: 'variante_no_encontrada',
      );
    }
    return repository.updateVariante(
      id,
      DatoVariante(
        tallaId: campos.contains('tallaId')
            ? ensureIdDeCatalogo(datos.tallaId, 'tallaId')
            : actual.tallaId,
        colorId: campos.contains('colorId')
            ? ensureIdDeCatalogo(datos.colorId, 'colorId')
            : actual.colorId,
        stock: campos.contains('stock')
            ? ensureNoNegativo(datos.stock, 'stock')
            : actual.stock,
        codigo: campos.contains('codigo') ? ensureCodigo(datos.codigo) : actual.codigo,
      ),
      campos,
    );
  }

  /// Borrado lógico de la variante (409 si todavía tiene stock).
  Future<void> eliminarVariante(int id) async {
    final removed = await repository.deleteVariante(id);
    if (!removed) {
      throw NotFoundException(
        'La variante $id no existe.',
        code: 'variante_no_encontrada',
      );
    }
  }

  /// Valida una variante antes de tocar la BD.
  ///
  /// Cada combinación se declara por **id** (`tallaId`/`colorId`) o por
  /// **nombre** (`talla`/`color`, texto libre que la BD buscará y creará si
  /// hace falta): nunca los dos a la vez ni ninguno de los dos.
  DatoVariante _asegurarVariante(DatoVariante datos) {
    final talla = _catalogoDeVariante(
      id: datos.tallaId,
      nombre: datos.talla,
      idCampo: 'tallaId',
      nombreCampo: 'talla',
      maximoNombre: 30,
    );
    final color = _catalogoDeVariante(
      id: datos.colorId,
      nombre: datos.color,
      idCampo: 'colorId',
      nombreCampo: 'color',
      maximoNombre: 50,
    );
    return DatoVariante(
      tallaId: talla.id,
      colorId: color.id,
      talla: talla.nombre,
      color: color.nombre,
      stock: ensureNoNegativo(datos.stock, 'stock'),
      codigo: ensureCodigo(datos.codigo),
    );
  }

  /// Reglas de un lado de la combinación (la talla o el color): id > 0 **o**
  /// nombre no vacío. Devuelve el id (`0` = viene por nombre) y el nombre
  /// recortado (`null` = viene por id).
  ({int id, String? nombre}) _catalogoDeVariante({
    required int id,
    required String? nombre,
    required String idCampo,
    required String nombreCampo,
    required int maximoNombre,
  }) {
    final texto = nombre?.trim() ?? '';
    if (id > 0 && texto.isNotEmpty) {
      throw BadRequestException(
        'Envía "$idCampo" o "$nombreCampo", no los dos a la vez.',
        code: 'field_invalid',
      );
    }
    if (id > 0) return (id: ensureIdDeCatalogo(id, idCampo), nombre: null);
    if (texto.isEmpty) {
      throw const BadRequestException(
        'Cada variante necesita su talla y su color: indica el id o el '
        'nombre (por ejemplo «S» o «Negro»).',
        code: 'fields_required',
      );
    }
    return (
      id: 0,
      nombre: ensureNombre(
        texto,
        campo: nombreCampo,
        minimo: 1,
        maximo: maximoNombre,
      ),
    );
  }
}
