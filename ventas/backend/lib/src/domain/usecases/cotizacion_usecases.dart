import '../../core/errors/app_exception.dart';
import '../entities/cotizacion.dart';
import '../entities/venta.dart';
import '../repositories/cotizacion_repository.dart';
import '../repositories/product_repository.dart';
import '../rules/estados.dart';
import '../rules/validaciones.dart';
import '../rules/variantes.dart';

/// Casos de uso de las cotizaciones (propuestas de precio).
///
/// Reglas de negocio:
///
/// * la cotización **no toca stock** ni lleva pagos: fija el precio vigente
///   de cada producto al momento de crearla;
/// * un producto oculto o `DESCONTINUADO` no se puede cotizar;
/// * estados: `VIGENTE` → `ACEPTADA` / `RECHAZADA` (más el borrado lógico
///   `ELIMINADO`, que no es un estado comercial);
/// * quién la creó lo decide la capa HTTP (empleado de la sesión), no el
///   cliente de la API.
final class Cotizaciones {
  const Cotizaciones({required this.repository, required this.productos});

  final CotizacionRepository repository;
  final ProductRepository productos;

  Future<List<Cotizacion>> listar({
    int limit = 50,
    int offset = 0,
    String? estado,
    String? q,
  }) => repository.findCotizaciones(
    limit: limit.clamp(1, 200),
    offset: offset.clamp(0, 100000),
    estado: estado == null
        ? null
        : ensureEstado(estado, estadosCotizaciones, 'estado'),
    q: q,
  );

  /// Total de cotizaciones con los mismos filtros que [listar] (COUNT real).
  Future<int> contar({String? estado, String? q}) =>
      repository.countCotizaciones(
        estado: estado == null
            ? null
            : ensureEstado(estado, estadosCotizaciones, 'estado'),
        q: q,
      );

  Future<Cotizacion> obtener(int id) async {
    final cotizacion = await repository.findCotizacionById(id);
    if (cotizacion == null) {
      throw NotFoundException(
        'La cotización $id no existe.',
        code: 'cotizacion_no_encontrada',
      );
    }
    return cotizacion;
  }

  /// Crea la cotización con sus líneas en **una transacción**.
  ///
  /// El cliente solo manda `productoId` y `cantidad`: los precios y el total
  /// se recalculan aquí con la BD, igual que en las órdenes.
  Future<Cotizacion> crear({
    int? clienteId,
    String? nombreCliente,
    int? empleadoId,
    required List<ItemOrden> items,
  }) async {
    if (items.isEmpty) {
      throw const BadRequestException(
        'La cotización debe incluir al menos un producto.',
        code: 'items_vacios',
      );
    }

    final lineas = <DetalleCotizacion>[];
    var total = 0.0;
    final vistos = <String>{};

    for (final item in items) {
      ensurePositivo(item.cantidad, 'cantidad');

      final producto = vendible(
        await productos.findById(item.productoId),
        item.productoId,
      );
      asegurarComprable(producto);
      // La variante concreta cotizada (por id, por color o la única viva):
      // la cotización no mueve stock pero sí fija la variante en la línea.
      final variante = resolverVarianteViva(producto, item);
      if (!vistos.add('${producto.id}:${variante.varianteId}')) {
        throw BadRequestException(
          'El producto ${item.productoId} (${variante.nombreColor}) aparece '
          'más de una vez en la cotización.',
          code: 'item_duplicado',
        );
      }

      // A diferencia de una orden, aquí NO se exige stock: una cotización
      // puede proyectar una compra futura.
      final monto = dinero(item.cantidad * producto.precioVenta);
      total += monto;
      lineas.add(
        DetalleCotizacion(
          productoId: producto.id,
          nombreProducto: producto.nombre,
          imagen: producto.imagen,
          cantidad: item.cantidad,
          precioVenta: producto.precioVenta,
          montoTotal: monto,
          unidad: producto.unidad,
          varianteId: variante.varianteId,
          nombreColor: variante.nombreColor,
        ),
      );
    }

    final ahora = DateTime.now().toUtc();
    return repository.insertCotizacion(
      Cotizacion(
        id: 0,
        fechaCotizacion: ahora,
        clienteId: clienteId,
        nombreCliente: nombreCliente,
        empleadoId: empleadoId,
        total: dinero(total),
        estado: 'VIGENTE',
        fechaCreacion: ahora,
        fechaActualizacion: ahora,
      ),
      lineas,
    );
  }

  /// Cambia el estado (`VIGENTE` <-> `ACEPTADA` <-> `RECHAZADA`).
  Future<Cotizacion> cambiarEstado(int id, String estado) async {
    final actual = await obtener(id);
    final nuevo = ensureEstado(estado, estadosCotizaciones, 'estado');
    if (nuevo == actual.estado) return actual;
    return repository.updateEstadoCotizacion(id, nuevo);
  }

  /// Borrado lógico: la fila se conserva con estado `ELIMINADO`.
  Future<void> eliminar(int id) async {
    await obtener(id);
    final removed = await repository.deleteCotizacion(id);
    if (!removed) {
      throw NotFoundException(
        'La cotización $id no existe.',
        code: 'cotizacion_no_encontrada',
      );
    }
  }
}
