/// Ventas de la farmacia: órdenes de pedido, sus detalles y las facturas.
///
/// Dominio puro: las reglas de transiciones de estado y de stock viven en
/// `domain/usecases/venta_usecases.dart`.
library;

import '../rules/estados.dart';
import '../rules/validaciones.dart';

/// Línea que se pide en una orden (`{productoId, cantidad}`).
final class ItemOrden {
  const ItemOrden({required this.productoId, required this.cantidad});

  final int productoId;
  final int cantidad;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'cantidad': cantidad,
  };
}

/// Pago de una orden (una orden puede tener **varias** líneas de pago:
/// efectivo + Yape, tarjeta + Plin...). La suma de montos cuadra con el total.
final class Pago {
  const Pago({
    required this.metodoPago,
    required this.monto,
    this.referencia,
    this.id,
    this.estado = 'ACTIVO',
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int? id;

  /// Método de pago (`EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`, `TRANSFERENCIA`).
  final String metodoPago;

  /// Importe pagado con [metodoPago].
  final double monto;

  /// Número de operación/referencia de pagos por QR o transferencia (opcional).
  final String? referencia;

  /// Valor del enum `estado_general` (borrado lógico).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  Pago conId(int valor) => Pago(
    id: valor,
    metodoPago: metodoPago,
    monto: monto,
    referencia: referencia,
    estado: estado,
    fechaCreacion: fechaCreacion,
    fechaActualizacion: fechaActualizacion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'metodoPago': metodoPago,
    'monto': monto,
    'referencia': referencia,
    'estado': estado,
  };
}

/// Orden de pedido (cabecera).
final class OrdenPedido {
  const OrdenPedido({
    required this.id,
    required this.fechaOrden,
    this.clienteId,
    this.nombreCliente,
    this.empleadoId,
    this.pagos = const [],
    required this.total,
    this.rebaja = 0,
    this.factura = false,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  final int id;
  final DateTime fechaOrden;
  final int? clienteId;

  /// Copia del nombre del cliente en el momento de crear la orden.
  final String? nombreCliente;
  final int? empleadoId;

  /// Desglose de pagos (`EFECTIVO + YAPE`, etc.); la suma cuadra con
  /// [totalPagar].
  final List<Pago> pagos;

  /// Suma de los detalles; la BD lo recalcula al modificar la orden.
  final double total;

  /// Rebaja hecha al cobrar (se descuenta del total).
  final double rebaja;

  /// ¿Se cobra con factura? Activa el IVA boliviano sobre la base.
  final bool factura;

  /// Valor del enum `estado_orden`
  /// (`PENDIENTE`, `PAGADO`, `CANCELADO`, `DEVUELTO`).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  /// Base imponible: total menos la rebaja (nunca negativa).
  double get base => total > rebaja ? total - rebaja : 0;

  /// IVA cobrado (14.94 % de la base) cuando la venta es factura.
  double get iva => factura ? ivaDe(base) : 0;

  /// Lo que se cobra realmente: `base + iva`; los pagos cuadran contra esto.
  double get totalPagar => base + iva;

  /// Edita la orden solo si todavía no está cobrada ni cancelada.
  bool get editable => esOrdenEditable(estado);

  /// Copia de la orden con el desglose de pagos adjunto (se rellena al leer).
  OrdenPedido conPagos(List<Pago> valor) => OrdenPedido(
    id: id,
    fechaOrden: fechaOrden,
    clienteId: clienteId,
    nombreCliente: nombreCliente,
    empleadoId: empleadoId,
    pagos: valor,
    total: total,
    rebaja: rebaja,
    factura: factura,
    estado: estado,
    fechaCreacion: fechaCreacion,
    fechaActualizacion: fechaActualizacion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'fechaOrden': fechaOrden.toUtc().toIso8601String(),
    'clienteId': clienteId,
    'nombreCliente': nombreCliente,
    'empleadoId': empleadoId,
    'pagos': pagos.map((p) => p.toJson()).toList(),
    'total': total,
    'rebaja': rebaja,
    'iva': iva,
    'factura': factura,
    'totalPagar': totalPagar,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}

/// Línea de una orden de pedido.
final class DetalleOrden {
  const DetalleOrden({
    required this.productoId,
    required this.ordenId,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioVenta,
    required this.montoTotal,
  });

  final int productoId;
  final int ordenId;
  final String nombreProducto;
  final int cantidad;
  final double precioVenta;
  final double montoTotal;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'ordenId': ordenId,
    'nombreProducto': nombreProducto,
    'cantidad': cantidad,
    'precioVenta': precioVenta,
    'montoTotal': montoTotal,
  };
}

/// Factura emitida por una orden (una por orden, `UNIQUE`).
///
/// Los importes son **instantánea** de la orden al momento de emitir:
/// `subtotal` (total de líneas), `rebaja` hecha al cobrar e `iva` cobrado.
final class Factura {
  const Factura({
    required this.id,
    required this.fechaFactura,
    this.empleadoId,
    this.clienteId,
    this.ordenId,
    required this.subtotal,
    required this.rebaja,
    required this.iva,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  /// Número de factura (`Factura_Numero`, identity).
  final int id;
  final DateTime fechaFactura;
  final int? empleadoId;
  final int? clienteId;
  final int? ordenId;
  final double subtotal;
  final double rebaja;
  final double iva;

  /// Valor del enum `estado_factura` (`EMITIDA`, `ANULADA`).
  final String estado;
  final DateTime fechaCreacion;
  final DateTime fechaActualizacion;

  /// Total cobrado: `subtotal - rebaja + iva`.
  double get total => subtotal - rebaja + iva;

  Map<String, Object?> toJson() => {
    'id': id,
    'fechaFactura': fechaFactura.toUtc().toIso8601String(),
    'empleadoId': empleadoId,
    'clienteId': clienteId,
    'ordenId': ordenId,
    'subtotal': subtotal,
    'rebaja': rebaja,
    'iva': iva,
    'total': total,
    'estado': estado,
    'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
    'fechaActualizacion': fechaActualizacion.toUtc().toIso8601String(),
  };
}
