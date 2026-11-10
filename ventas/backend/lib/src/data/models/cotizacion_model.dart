import '../../domain/entities/cotizacion.dart';
import 'row_utils.dart';

/// Modelo de datos: adapta filas de `cotizaciones` y
/// `detalles_cotizaciones` a sus entidades de dominio.
final class CotizacionModel {
  const CotizacionModel._();

  static Cotizacion cotizacion(
    Map<String, Object?> row, {
    List<DetalleCotizacion> detalles = const [],
  }) => Cotizacion(
    id: RowUtils.intValue(row['cotizacion_id']),
    fechaCotizacion: RowUtils.dateTime(row['fecha_cotizacion']),
    clienteId: RowUtils.intOrNull(row['cliente_id']),
    nombreCliente: RowUtils.textOrNull(row['nombre_cliente']),
    empleadoId: RowUtils.intOrNull(row['empleado_id']),
    total: RowUtils.doubleValue(row['total']),
    estado: RowUtils.text(row['estado'], fallback: 'VIGENTE'),
    fechaCreacion: RowUtils.dateTime(row['fecha_creacion']),
    fechaActualizacion: RowUtils.dateTime(row['fecha_actualizacion']),
    detalles: detalles,
  );

  static DetalleCotizacion detalle(Map<String, Object?> row) =>
      DetalleCotizacion(
        productoId: RowUtils.intValue(row['producto_id']),
        nombreProducto: RowUtils.text(row['nombre_producto']),
        imagen: RowUtils.textOrNull(row['imagen']),
        cantidad: RowUtils.doubleValue(row['cantidad']),
        precioVenta: RowUtils.doubleValue(row['precio_venta']),
        montoTotal: RowUtils.doubleValue(row['monto_total']),
        unidad: RowUtils.text(row['unidad'], fallback: 'UN'),
        varianteId: RowUtils.intOrNull(row['variante_id']),
        nombreColor: RowUtils.textOrNull(row['nombre_color']),
      );
}
