import '../../core/errors/failure.dart';

/// Producto con sus ventas agregadas (ranking del dashboard).
///
/// Es lo que devuelve `GET /api/v1/reportes/productos-vendidos`: un resumen
/// calculado por el servidor agrupando las líneas de las órdenes, no una fila
/// de un CRUD (por eso tiene su propio camino en vez de usar `Recurso`).
final class VentaProducto {
  const VentaProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
  });

  factory VentaProducto.fromJson(Map<String, dynamic> json) {
    final productoId = json['productoId'];
    final unidades = json['unidades'];
    if (productoId is! num || unidades is! num) throw const ParsingFailure();
    return VentaProducto(
      productoId: productoId.toInt(),
      nombre: '${json['nombre'] ?? ''}',
      unidades: unidades.toInt(),
      monto: json['monto'] is num
          ? (json['monto'] as num).toDouble()
          : double.tryParse('${json['monto']}') ?? 0,
    );
  }

  final int productoId;
  final String nombre;

  /// Unidades vendidas (solo órdenes no anuladas).
  final int unidades;

  /// Importe generado, en soles.
  final double monto;
}
