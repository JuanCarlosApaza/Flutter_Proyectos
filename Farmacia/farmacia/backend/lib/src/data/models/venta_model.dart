import '../../domain/entities/venta.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `ordenes_pedidos`,
/// `detalles_ordenes_pedidos` y `facturas` a sus entidades de dominio.
final class VentaModel {
  const VentaModel._();

  static OrdenPedido orden(
    Map<String, Object?> row, {
    List<Pago> pagos = const [],
  }) => OrdenPedido(
    id: RowUtils.intValue(row['orden_id']),
    fechaOrden: RowUtils.dateTime(row['fecha_orden']),
    clienteId: RowUtils.intOrNull(row['cliente_id']),
    nombreCliente: RowUtils.textOrNull(row['nombre_cliente']),
    empleadoId: RowUtils.intOrNull(row['empleado_id']),
    pagos: pagos,
    total: RowUtils.doubleValue(row['total']),
    rebaja: RowUtils.doubleValue(row['rebaja']),
    factura: RowUtils.boolValue(row['factura']),
    estado: RowUtils.text(row['estado'], fallback: 'PENDIENTE'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );

  static Pago pago(Map<String, Object?> row) => Pago(
    id: RowUtils.intValue(row['pago_id']),
    metodoPago: RowUtils.text(row['metodo_pago']),
    monto: RowUtils.doubleValue(row['monto']),
    referencia: RowUtils.textOrNull(row['referencia']),
    estado: RowUtils.text(row['estado'], fallback: 'ACTIVO'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );

  static DetalleOrden detalle(Map<String, Object?> row) => DetalleOrden(
    productoId: RowUtils.intValue(row['producto_id']),
    ordenId: RowUtils.intValue(row['orden_id']),
    nombreProducto: RowUtils.text(row['nombre_producto']),
    cantidad: RowUtils.intValue(row['cantidad']),
    precioVenta: RowUtils.doubleValue(row['precio_venta']),
    montoTotal: RowUtils.doubleValue(row['monto_total']),
  );

  static Factura factura(Map<String, Object?> row) => Factura(
    id: RowUtils.intValue(row['factura_numero']),
    fechaFactura: RowUtils.dateTime(row['fecha_factura']),
    empleadoId: RowUtils.intOrNull(row['empleado_id']),
    clienteId: RowUtils.intOrNull(row['cliente_id']),
    ordenId: RowUtils.intOrNull(row['orden_id']),
    subtotal: RowUtils.doubleValue(row['subtotal']),
    rebaja: RowUtils.doubleValue(row['rebaja']),
    iva: RowUtils.doubleValue(row['iva']),
    estado: RowUtils.text(row['estado'], fallback: 'EMITIDA'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
  );
}
