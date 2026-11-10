import 'package:flutter/foundation.dart';

import '../../domain/entities/recurso.dart';

/// Línea del carrito de compras.
///
/// Copia en el carrito de los datos del producto en el momento de agregarlo
/// (nombre, precio, imagen y stock disponible): así el panel sigue pintándose
/// aunque el catálogo se recargue y el precio no cambia a mitad de compra.
final class LineaCarrito {
  LineaCarrito({
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.stock,
    this.precioRebaja,
    this.imagen,
    this.cantidad = 1,
  });

  final int productoId;
  final String nombre;
  final double precio;
  final String? imagen;

  /// Tope del producto: máximo en Bs que se puede rebajar **por unidad**
  /// (`null` = sin límite).
  final double? precioRebaja;

  /// Stock disponible al agregar: tope para [cantidad].
  final int stock;

  int cantidad;

  double get subtotal => precio * cantidad;
}

/// Carrito de compras compartido por la app (patrón `ChangeNotifier`).
///
/// Vive en memoria durante la sesión: agregar, cambiar cantidades, quitar y
/// vaciar notifican a la UI (botón del carrito, catálogo y panel lateral).
/// La compra se concreta al final generando la orden en la API.
final class CarritoController extends ChangeNotifier {
  final Map<int, LineaCarrito> _lineas = {};

  /// Líneas en orden de inserción.
  List<LineaCarrito> get lineas => List.unmodifiable(_lineas.values);

  bool get vacio => _lineas.isEmpty;

  /// Unidades totales (badge del botón de carrito).
  int get unidades =>
      _lineas.values.fold(0, (suma, linea) => suma + linea.cantidad);

  /// Importe total del carrito.
  double get total =>
      _lineas.values.fold(0.0, (suma, linea) => suma + linea.subtotal);

  int cantidadDe(int productoId) => _lineas[productoId]?.cantidad ?? 0;

  bool contiene(int productoId) => _lineas.containsKey(productoId);

  /// Agrega [cantidad] unidades del producto; nunca supera su stock.
  void agregar(Recurso producto, {int cantidad = 1}) {
    final stock = (producto.numero('stock') ?? 0).round();
    if (stock <= 0) return;

    final existente = _lineas[producto.id];
    if (existente == null) {
      final imagen = producto.texto('imagen', vacio: '');
      _lineas[producto.id] = LineaCarrito(
        productoId: producto.id,
        nombre: producto.texto('nombre', vacio: 'Producto'),
        precio: producto.numero('precioVenta') ?? 0,
        precioRebaja: producto.numero('precioRebaja'),
        imagen: imagen.isEmpty ? null : imagen,
        stock: stock,
        cantidad: cantidad.clamp(1, stock).toInt(),
      );
    } else {
      existente.cantidad = (existente.cantidad + cantidad)
          .clamp(1, existente.stock)
          .toInt();
    }
    notifyListeners();
  }

  /// Suma o resta unidades; una cantidad que llega a 0 retira la línea.
  void cambiarCantidad(int productoId, int delta) {
    final linea = _lineas[productoId];
    if (linea == null) return;

    final nueva = linea.cantidad + delta;
    if (nueva <= 0) {
      _lineas.remove(productoId);
    } else {
      linea.cantidad = nueva.clamp(1, linea.stock).toInt();
    }
    notifyListeners();
  }

  void quitar(int productoId) {
    if (_lineas.remove(productoId) != null) notifyListeners();
  }

  void vaciar() {
    if (_lineas.isEmpty) return;
    _lineas.clear();
    notifyListeners();
  }
}
