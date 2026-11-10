import 'package:flutter/foundation.dart';

import '../../core/validation/reglas.dart';
import '../../domain/entities/recurso.dart';
import 'recurso_controller.dart';

/// Variante vendible de un producto (una fila de `producto_variantes` tal
/// como la adjunta la API en `productos.variantes`).
///
/// El carrito agrega **la variante**, no el producto: mismo producto en dos
/// colores son dos líneas independientes con su propio stock.
final class VarianteVenta {
  const VarianteVenta({
    required this.varianteId,
    required this.nombre,
    required this.stock,
    this.codigoHex,
    this.vendible = true,
  });

  final int varianteId;

  /// Nombre del color congelado en la fila («Único» si es unidad simple).
  final String nombre;

  /// Muestra `#RRGGBB` del catálogo actual (solo el chip de la UI).
  final String? codigoHex;

  /// Stock de esta variante (el stock del producto es su suma).
  final double stock;

  final bool vendible;

  bool get agotada => stock <= 0;
}

/// Variantes vivas que la API adjunta al producto, en su orden.
///
/// Un producto sin `variantes` en el JSON (datos viejos en caché) devuelve
/// la lista vacía: el carrito lo trata como unidad simple.
List<VarianteVenta> variantesDe(Recurso producto) {
  final crudo = producto['variantes'];
  if (crudo is! List) return const [];
  return [
    for (final fila in crudo)
      if (fila is Map)
        VarianteVenta(
          varianteId: (fila['varianteId'] as num?)?.toInt() ?? 0,
          nombre: (fila['nombreColor'] ?? 'Único').toString(),
          codigoHex: fila['codigoHex'] as String?,
          stock: (fila['stock'] as num?)?.toDouble() ?? 0,
          vendible: fila['vendible'] as bool? ?? true,
        ),
  ];
}

/// Línea del carrito de compras.
///
/// Copia en el carrito de los datos de **la variante elegida** en el momento
/// de agregarla (nombre, precio, imagen, stock de la variante, unidad y sus
/// decimales): así el panel sigue pintándose aunque el catálogo se recargue,
/// el precio no cambia a mitad de compra y una cantidad escrita en `KG` no
/// se relee con las reglas de otra unidad.
final class LineaCarrito {
  LineaCarrito({
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.stock,
    this.varianteId,
    this.nombreColor,
    this.codigoHex,
    this.unidad = 'UN',
    this.decimales = 0,
    this.precioRebaja,
    this.imagen,
    this.cantidad = 1,
  });

  final int productoId;

  /// Variante concreta que se está vendiendo (`null` solo si el JSON del
  /// producto no trae variantes); es lo que viaja en `items[].varianteId`.
  final int? varianteId;

  /// Color congelado de la variante (para el chip del panel y del recibo).
  final String? nombreColor;

  /// Muestra `#RRGGBB` del catálogo actual (chip de la UI, nunca se imprime).
  final String? codigoHex;

  final String nombre;
  final double precio;
  final String? imagen;

  /// Unidad de venta copiada del producto al agregarlo (`KG`, `UN`...):
  /// la misma que viaja en `productos.unidad` y en la orden.
  final String unidad;

  /// Máximo de decimales que admite la cantidad de esta unidad
  /// (`unidades_medida.decimales`): `CAJA` solo enteros, `KG` hasta gramos.
  final int decimales;

  /// Tope del producto: máximo en Bs que se puede rebajar **por unidad**
  /// (`null` = sin límite).
  final double? precioRebaja;

  /// Stock disponible de **esta variante** al agregar: tope **exacto** para
  /// [cantidad] — es fraccionado, así que con `12.750 KG` en existencias se
  /// pueden llevar 12.750, no se trunca a 12.
  final double stock;

  double cantidad;

  /// Identidad de la línea en el carrito: mismo producto en dos colores
  /// conviven como dos claves distintas.
  String get clave => claveDeLinea(productoId, varianteId);

  /// Paso de los botones `+`/`−`: enteros para lo que se cuenta (UN, CAJA)
  /// y cuartos para lo que se fracciona (KG, LT).
  double get paso => decimales == 0 ? 1 : 0.25;

  double get subtotal => precio * cantidad;

  /// [valor] recortado al rango que la línea admite (nunca por encima del
  /// stock) y redondeado a los decimales de la unidad.
  double acotar(double valor) =>
      redondearCantidad(valor > stock ? stock : valor, decimales);
}

/// Clave interna de una línea: `producto:variante` (`0` = sin variante).
String claveDeLinea(int productoId, int? varianteId) =>
    '$productoId:${varianteId ?? 0}';

/// Carrito de compras compartido por la app (patrón `ChangeNotifier`).
///
/// Vive en memoria durante la sesión: agregar, cambiar cantidades, quitar y
/// vaciar notifican a la UI (botón del carrito, catálogo y panel lateral).
/// La compra se concreta al final generando la orden en la API, llevando el
/// `varianteId` de cada línea.
final class CarritoController extends ChangeNotifier {
  CarritoController({this.unidadesMedida});

  /// Catálogo de unidades de medida: de aquí sale, para cada producto, cuántos
  /// decimales admite su cantidad. Sin catálogo (p. ej. pantalla de prueba)
  /// se aplica el respaldo: enteros, salvo los códigos que se fraccionan.
  final UnidadesController? unidadesMedida;

  final Map<String, LineaCarrito> _lineas = {};

  /// Líneas en orden de inserción.
  List<LineaCarrito> get lineas => List.unmodifiable(_lineas.values);

  bool get vacio => _lineas.isEmpty;

  /// Cantidad total del carrito (badge del botón): `2.250` si entre todas
  /// las líneas hay 2,25 KG.
  double get unidades =>
      _lineas.values.fold(0.0, (suma, linea) => suma + linea.cantidad);

  /// Importe total del carrito.
  double get total =>
      _lineas.values.fold(0.0, (suma, linea) => suma + linea.subtotal);

  /// Línea exacta de producto + variante (`null` = no está en el carrito).
  LineaCarrito? lineaDe(int productoId, [int? varianteId]) =>
      _lineas[claveDeLinea(productoId, varianteId)];

  /// Cantidad de esa línea concreta (0 si no existe).
  double cantidadDe(int productoId, [int? varianteId]) =>
      lineaDe(productoId, varianteId)?.cantidad ?? 0;

  /// Suma de todas las líneas de ese producto (badge de la tarjeta del
  /// catálogo: con colores suma Rojo + Azul).
  double totalDe(int productoId) => _lineas.values
      .where((linea) => linea.productoId == productoId)
      .fold(0.0, (suma, linea) => suma + linea.cantidad);

  /// ¿Está esa línea en el carrito?
  bool contiene(int productoId, [int? varianteId]) =>
      _lineas.containsKey(claveDeLinea(productoId, varianteId));

  /// ¿Tiene el producto alguna línea en el carrito?
  bool contieneProducto(int productoId) =>
      _lineas.values.any((linea) => linea.productoId == productoId);

  /// Última línea agregada de ese producto (el `−` de la tarjeta descuenta
  /// de donde se agregó por última vez); `null` = el producto no está.
  LineaCarrito? ultimaDe(int productoId) {
    LineaCarrito? ultima;
    for (final linea in _lineas.values) {
      if (linea.productoId == productoId) ultima = linea;
    }
    return ultima;
  }

  /// Agrega [cantidad] de **la variante elegida**; nunca supera su stock
  /// fraccionado (una variante con `0.750 KG` sí se puede agregar, con esa
  /// cantidad).
  ///
  /// Sin [variante] y con un producto de una sola variante se selecciona
  /// esa automáticamente (regla de «auto-selección»); con varias variantes y
  /// sin elegir no se agrega nada — la UI debe abrir la hoja «Elige el
  /// color».
  void agregar(Recurso producto, {VarianteVenta? variante, double cantidad = 1}) {
    var elegida = variante;
    if (elegida == null) {
      final variantes = variantesDe(producto);
      if (variantes.length > 1) return;
      if (variantes.length == 1) elegida = variantes.single;
    }

    final stock = elegida?.stock ?? (producto.numero('stock') ?? 0);
    if (stock <= 0) return;

    final unidad = producto.texto('unidad', vacio: 'UN');
    final decimales =
        unidadesMedida?.decimalesDe(unidad) ??
        UnidadesController.respaldo(unidad);
    final clave = claveDeLinea(producto.id, elegida?.varianteId);
    final existente = _lineas[clave];
    if (existente == null) {
      final imagen = producto.texto('imagen', vacio: '');
      final linea = LineaCarrito(
        productoId: producto.id,
        varianteId: elegida?.varianteId,
        nombreColor: elegida?.nombre,
        codigoHex: elegida?.codigoHex,
        nombre: producto.texto('nombre', vacio: 'Producto'),
        precio: producto.numero('precioVenta') ?? 0,
        precioRebaja: producto.numero('precioRebaja'),
        imagen: imagen.isEmpty ? null : imagen,
        stock: stock,
        unidad: unidad,
        decimales: decimales,
      );
      linea.cantidad = linea.acotar(cantidad);
      _lineas[clave] = linea;
    } else {
      existente.cantidad = existente.acotar(existente.cantidad + cantidad);
    }
    notifyListeners();
  }

  /// Suma o resta el [paso] de la línea (entero o 0.250); una cantidad que
  /// llega a 0 retira la línea. Sin `varianteId` opera sobre la línea de un
  /// producto sin variantes (`…:0`).
  void cambiarCantidad(int productoId, double delta, [int? varianteId]) {
    final clave = claveDeLinea(productoId, varianteId);
    final linea = _lineas[clave];
    if (linea == null) return;

    final nueva = redondearCantidad(linea.cantidad + delta, linea.decimales);
    if (nueva <= 0) {
      _lineas.remove(clave);
    } else {
      linea.cantidad = linea.acotar(nueva);
    }
    notifyListeners();
  }

  /// Botón `−`: baja un [LineaCarrito.paso] (una unidad en lo que se
  /// cuenta, 0.250 en lo que se fracciona). Sin `varianteId` actúa sobre la
  /// última línea de ese producto (el `−` de la tarjeta del catálogo).
  void restar(int productoId, [int? varianteId]) {
    final linea = lineaDe(productoId, varianteId) ?? ultimaDe(productoId);
    if (linea == null) return;
    cambiarCantidad(linea.productoId, -linea.paso, linea.varianteId);
  }

  /// Botón `+`: sube un [LineaCarrito.paso] y nunca pasa del stock
  /// disponible.
  void sumar(int productoId, [int? varianteId]) {
    final linea = lineaDe(productoId, varianteId) ?? ultimaDe(productoId);
    if (linea == null) return;
    cambiarCantidad(linea.productoId, linea.paso, linea.varianteId);
  }

  /// Fija la cantidad escrita a mano en el campo del carrito: se recorta al
  /// stock y a los decimales de la unidad; 0 o menos retira la línea.
  void definirCantidad(int productoId, double cantidad, [int? varianteId]) {
    final clave = claveDeLinea(productoId, varianteId);
    final linea = _lineas[clave];
    if (linea == null) return;

    if (cantidad <= 0) {
      _lineas.remove(clave);
    } else {
      linea.cantidad = linea.acotar(cantidad);
    }
    notifyListeners();
  }

  void quitar(int productoId, [int? varianteId]) {
    if (_lineas.remove(claveDeLinea(productoId, varianteId)) != null) {
      notifyListeners();
    }
  }

  void vaciar() {
    if (_lineas.isEmpty) return;
    _lineas.clear();
    notifyListeners();
  }
}
