import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
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

  Future<Product> crear({
    required String nombre,
    required double precioVenta,
    String? imagen,
    double? precioCompra,
    double? precioRebaja,
    DateTime? fechaVencimiento,
    int stock = 0,
    int? categoriaId,
    int? proveedorId,
    int? presentacionId,
    String estado = 'DISPONIBLE',
  }) {
    // El precio de venta debe ser > 0, caber en NUMERIC(10, 2) y no bajar
    // del precio de compra (todo en una sola regla, con redondeo a 2 decimales).
    final precioFinal = ensurePrecioVenta(precioVenta, precioCompra);
    // El tope de rebaja por unidad no puede superar el precio de venta.
    final rebajaFinal = ensurePrecioRebaja(precioRebaja, precioFinal);
    ensureNoNegativo(stock, 'stock');
    ensureFechaNoVencida(fechaVencimiento);
    return repository.insert(
      Product(
        id: 0,
        nombre: ensureNombre(nombre),
        imagen: imagen,
        precioVenta: precioFinal,
        precioCompra: precioCompra == null ? null : dinero(precioCompra),
        precioRebaja: rebajaFinal,
        fechaVencimiento: fechaVencimiento,
        stock: stock,
        categoriaId: categoriaId,
        proveedorId: proveedorId,
        presentacionId: presentacionId,
        estado: ensureEstado(estado, estadosProductos, 'estado'),
      ),
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

    return repository.update(
      id,
      Product(
        id: id,
        nombre: campos.contains('nombre')
            ? ensureNombre(datos.nombre)
            : datos.nombre,
        imagen: datos.imagen,
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
        categoriaId: datos.categoriaId,
        proveedorId: datos.proveedorId,
        presentacionId: datos.presentacionId,
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
}
