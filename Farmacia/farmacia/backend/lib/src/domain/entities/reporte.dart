/// Ventas agregadas de un producto (modelo puro de dominio).
///
/// Es lo que devuelve el reporte del dashboard al agrupar
/// `detalles_ordenes_pedidos` por producto: cuántas unidades se han vendido y
/// qué monto han generado.
///
/// Solo cuentan las líneas de órdenes **no anuladas** (`PENDIENTE` y
/// `PAGADO`): las canceladas o devueltas no son ventas.
final class VentaProducto {
  const VentaProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
  });

  /// Fila `{"productoId": 7, ...}` -> entidad.
  factory VentaProducto.fromJson(Map<String, Object?> json) => VentaProducto(
    productoId: json['productoId'] is int
        ? json['productoId'] as int
        : int.tryParse('${json['productoId']}') ?? 0,
    nombre: '${json['nombre'] ?? ''}',
    unidades: json['unidades'] is int
        ? json['unidades'] as int
        : int.tryParse('${json['unidades']}') ?? 0,
    monto: json['monto'] is num
        ? (json['monto'] as num).toDouble()
        : double.tryParse('${json['monto']}') ?? 0,
  );

  final int productoId;

  /// Nombre del producto tal y como lo muestra el dashboard.
  final String nombre;

  /// Unidades vendidas (suma de `cantidad`).
  final int unidades;

  /// Importe generado (suma de `monto_total`), en soles.
  final double monto;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'nombre': nombre,
    'unidades': unidades,
    'monto': monto,
  };
}
