import 'package:flutter/foundation.dart';

import '../../domain/entities/recurso.dart';

/// Línea del carrito de compras: una variante concreta (talla + color) de
/// una prenda.
///
/// Copia en el carrito de los datos en el momento de agregarla (nombre,
/// precio del producto, imagen y talla/color): así el panel sigue pintándose
/// aunque el catálogo se recargue y el precio no cambie a mitad de compra.
final class LineaCarrito {
  LineaCarrito({
    required this.productoId,
    required this.varianteId,
    required this.nombre,
    required this.talla,
    required this.color,
    required this.precio,
    required this.stock,
    this.precioRebaja,
    this.imagen,
    this.cantidad = 1,
  });

  final int productoId;

  /// Variante (talla + color): clave única de la línea.
  final int varianteId;

  final String nombre;

  /// Talla y color de la prenda (`'Única'`/`'Único'` en prendas sin talla).
  final String talla;
  final String color;

  final double precio;
  final String? imagen;

  /// Tope del producto: máximo en Bs que se puede rebajar **por unidad**
  /// (`null` = sin límite).
  final double? precioRebaja;

  /// Stock de la variante al agregar: tope para [cantidad].
  final int stock;

  int cantidad;

  /// «Polo · M · Negro»: etiqueta de la línea para listados y PDFs.
  String get etiqueta => '$nombre · $talla · $color';

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

  int cantidadDe(int varianteId) => _lineas[varianteId]?.cantidad ?? 0;

  bool contiene(int varianteId) => _lineas.containsKey(varianteId);

  /// Agrega [cantidad] unidades de la variante; nunca supera su stock.
  void agregar(Recurso producto, Recurso variante, {int cantidad = 1}) {
    final stock = (variante.numero('stock') ?? 0).floor();
    if (stock < 1) return;

    final existente = _lineas[variante.id];
    if (existente == null) {
      final imagen = producto.texto('imagen', vacio: '');
      _lineas[variante.id] = LineaCarrito(
        productoId: producto.id,
        varianteId: variante.id,
        nombre: producto.texto('nombre', vacio: 'Producto'),
        talla: variante.texto('talla', vacio: 'Única'),
        color: variante.texto('color', vacio: 'Único'),
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
  void cambiarCantidad(int varianteId, int delta) {
    final linea = _lineas[varianteId];
    if (linea == null) return;

    final nueva = linea.cantidad + delta;
    if (nueva <= 0) {
      _lineas.remove(varianteId);
    } else {
      linea.cantidad = nueva.clamp(1, linea.stock).toInt();
    }
    notifyListeners();
  }

  void quitar(int varianteId) {
    if (_lineas.remove(varianteId) != null) notifyListeners();
  }

  void vaciar() {
    if (_lineas.isEmpty) return;
    _lineas.clear();
    notifyListeners();
  }
}
