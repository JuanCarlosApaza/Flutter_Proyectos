/// Cotizaciones: propuestas de precio para un cliente.
///
/// Dominio puro: quién la creó (empleado de la sesión), para quién (cliente)
/// y sus líneas con el precio vigente de la BD. No toca stock ni lleva
/// pagos; la traducción snake_case -> camelCase ocurre en `data/`.
library;

/// Línea de una cotización (nombre, imagen, cantidad y precio fijados al
/// crearla: la hoja muestra lo que se ofreció aunque el producto cambie).
final class DetalleCotizacion {
  const DetalleCotizacion({
    required this.productoId,
    required this.varianteId,
    required this.nombreProducto,
    this.imagen,
    this.talla,
    this.color,
    required this.cantidad,
    required this.precioVenta,
    required this.montoTotal,
    this.unidad = 'UN',
  });

  final int productoId;

  /// Variante (talla + color) cotizada: clave de la línea junto con la
  /// cotización, igual que en las órdenes.
  final int varianteId;

  final String nombreProducto;

  /// Ruta de la imagen del producto en el momento de cotizar.
  final String? imagen;

  /// Talla y color leídos de la variante al recuperar la línea.
  final String? talla;
  final String? color;

  /// Cantidad en unidades, como en una orden.
  final double cantidad;
  final double precioVenta;
  final double montoTotal;

  /// Unidad congelada al cotizar (columna `unidad`).
  final String unidad;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'varianteId': varianteId,
    'nombreProducto': nombreProducto,
    'imagen': imagen,
    'talla': talla,
    'color': color,
    'cantidad': cantidad,
    'precioVenta': precioVenta,
    'montoTotal': montoTotal,
    'unidad': unidad,
  };
}

/// Cabecera de la cotización (tabla `cotizaciones`).
final class Cotizacion {
  const Cotizacion({
    required this.id,
    required this.fechaCotizacion,
    this.clienteId,
    this.nombreCliente,
    this.empleadoId,
    required this.total,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    this.detalles = const [],
  });

  final int id;
  final DateTime fechaCotizacion;

  /// Cliente al que va dirigida (`null` = mostrador, se usa `nombreCliente`).
  final int? clienteId;
  final String? nombreCliente;

  /// Quien la creó (empleado de la sesión en el momento de crearla).
  final int? empleadoId;

  final double total;

  /// `VIGENTE`, `ACEPTADA`, `RECHAZADA` o `ELIMINADO` (borrado lógico).
  final String estado;

  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  /// Líneas: solo se rellenan al abrir el detalle
  /// (`GET /cotizaciones/{id}`); el listado va sin ellas.
  final List<DetalleCotizacion> detalles;

  Map<String, Object?> toJson() => {
    'id': id,
    'fechaCotizacion': fechaCotizacion.toUtc().toIso8601String(),
    'clienteId': clienteId,
    'nombreCliente': nombreCliente,
    'empleadoId': empleadoId,
    'total': total,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
    'detalles': detalles.map((d) => d.toJson()).toList(),
  };

  /// Copia con las líneas adjuntas (se rellena al leer el detalle).
  Cotizacion conDetalles(List<DetalleCotizacion> valor) => Cotizacion(
    id: id,
    fechaCotizacion: fechaCotizacion,
    clienteId: clienteId,
    nombreCliente: nombreCliente,
    empleadoId: empleadoId,
    total: total,
    estado: estado,
    fechaCreacion: fechaCreacion,
    fechaActualizacion: fechaActualizacion,
    detalles: valor,
  );
}
