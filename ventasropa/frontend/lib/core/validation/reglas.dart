/// Validaciones de formulario en espejo de las reglas del backend
/// (`backend/lib/src/domain/rules/validaciones.dart`).
///
/// Cada función devuelve `null` cuando el valor es válido o, si no, el
/// mensaje que se muestra en rojo bajo el campo. Así el usuario ve el
/// problema **antes** de enviar y no se gana un `400` de la API.
library;

/// IVA de Bolivia: **14.94 %** (espejo de `ivaBolivia` del backend).
const double ivaBolivia = 0.1494;

/// Nombre de usuario: 4-50 caracteres con solo letras, números, punto,
/// guion bajo o guion (p. ej. `ana.lucia.torres3`).
String? usuarioValido(String valor) {
  if (!RegExp(r'^[\w.\-]{4,50}$').hasMatch(valor)) {
    return 'Solo letras, números, punto, guion o guion bajo (mínimo 4)';
  }
  return null;
}

/// CI (Cédula de Identidad): entre 7 y 15 dígitos.
String? ciValido(String valor) {
  final limpio = valor.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d{7,15}$').hasMatch(limpio)) {
    return 'Debe tener entre 7 y 15 dígitos';
  }
  return null;
}

/// Teléfono: admite `+`, dígitos, espacios, guiones y paréntesis,
/// con entre 6 y 15 dígitos en total (p. ej. `+51 999 888 777`).
String? telefonoValido(String valor) {
  final limpio = valor.trim();
  if (!RegExp(r'^\+?[\d\s\-()]*$').hasMatch(limpio)) {
    return 'Solo dígitos, espacios, guiones y paréntesis';
  }
  if (limpio.length > 20) return 'No puede superar 20 caracteres';
  final digitos = limpio.replaceAll(RegExp(r'\D'), '');
  if (digitos.length < 6 || digitos.length > 15) {
    return 'Debe tener entre 6 y 15 dígitos';
  }
  return null;
}

/// Correo de contacto: forma `algo@dominio.tld` (espejo de `ensureEmail` del
/// backend). El campo es opcional: el formulario no llama al validador con
/// el valor vacío, y aun así un vacío se acepta.
String? emailValido(String valor) {
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length > 150) return 'No puede superar 150 caracteres';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(limpio)) {
    return 'Introduce un correo válido (ej. ventas@acme.com)';
  }
  return null;
}

/// NIT fiscal: 4-20 caracteres con letras, dígitos, punto o guion (espejo de
/// `ensureNit` del backend), p. ej. `1023456027` o `1023456027-01`.
String? nitValido(String valor) {
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length < 4 || limpio.length > 20) {
    return 'Debe tener entre 4 y 20 caracteres';
  }
  if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z.\-]*[0-9A-Za-z]$').hasMatch(limpio)) {
    return 'Solo letras, dígitos, punto o guion';
  }
  return null;
}

/// Talla: letras cortas de vestir (`S`, `M`, `XL`, `G`...), número de
/// calzado o de niño (`38`, `40.5`, `110`), rango o combinación
/// (`39-41`, `S/M` — típico de medias) o «Única» (espejo de
/// `ensureNombreTalla` del backend).
///
/// Las frases no son tallas: «un par de medias» se queda fuera del
/// catálogo.
String? tallaValida(String valor) {
  final patron = RegExp(
    r'^([uú]nica|(?:[0-9]{1,3}(?:\.\d)?|[sxmlgcpu]{1,4})'
    r'(?:[/-](?:[0-9]{1,3}(?:\.\d)?|[sxmlgcpu]{1,4}))*)$',
    caseSensitive: false,
  );
  if (!patron.hasMatch(valor)) {
    return 'Talla no válida: S, M, XL · 38 · 39-41 · «Única»';
  }
  return null;
}

/// Regla entre campos: **el precio de venta no puede quedar por debajo del
/// precio de compra** (el producto se vendería con pérdida).
///
/// Acepta `num` o `String` (o `null` si el campo está vacío); si alguno de
/// los dos no es un número no hay nada que comparar.
String? ventaNoMenorQueCoste(Object? precioVenta, Object? precioCompra) {
  final venta = _numero(precioVenta);
  final coste = _numero(precioCompra);
  if (venta == null || coste == null) return null;
  if (venta < coste) {
    return 'El precio de venta (Bs ${venta.toStringAsFixed(2)}) no puede ser '
        'menor al precio de compra (Bs ${coste.toStringAsFixed(2)}): se '
        'vendería con pérdida.';
  }
  return null;
}

/// Regla entre campos: el máximo a rebajar por unidad no puede superar el
/// precio de venta del producto.
String? rebajaNoMayorQueVenta(Object? precioRebaja, Object? precioVenta) {
  final rebaja = _numero(precioRebaja);
  final venta = _numero(precioVenta);
  if (rebaja == null || venta == null) return null;
  if (rebaja > venta) {
    return 'El máximo a rebajar (Bs ${rebaja.toStringAsFixed(2)}) no puede '
        'superar el precio de venta';
  }
  return null;
}

double? _numero(Object? valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  if (valor is String) return double.tryParse(valor.trim());
  return null;
}

/// Cantidad o stock como texto sin ceros de relleno (`12.75`, `15`).
///
/// Cantidades y existencias van en columnas `NUMERIC(12, 3)`, así que sin
/// este recorte un campo o una tabla pintarían «12.0» o «12.750».
String cantidadTexto(double valor) {
  final texto = valor.toStringAsFixed(3);
  if (texto.endsWith('.000')) return texto.substring(0, texto.length - 4);
  return texto.replaceFirst(RegExp(r'0+$'), '');
}
