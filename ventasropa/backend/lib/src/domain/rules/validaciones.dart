/// Reglas de negocio simples compartidas por varias entidades.
///
/// El dominio es quien decide qué valores son aceptables; si la petición los
/// incumple, la respuesta es `400 Bad Request` (nunca llega a la BD).
library;

import '../../core/errors/app_exception.dart';
import '../entities/product.dart';
import 'estados.dart';

/// Valores permitidos de `Clientes.Genero` (`CHAR(1)`).
const Set<String> generosPermitidos = {'M', 'F', 'O'};

/// Métodos de pago aceptados (espejo de `tiposPago` del frontend).
///
/// Una orden puede repartirse en varios de estos métodos (efectivo + QR):
/// la suma de montos de sus `Pago` debe cuadrar con el total.
const Set<String> metodosPago = {
  'EFECTIVO',
  'QR',
  'TARJETA',
  'YAPE',
  'PLIN',
  'TRANSFERENCIA',
};

/// Longitud máxima de la referencia/nº de operación de un pago.
const int referenciaMaxima = 100;

/// IVA de Bolivia: **14.94 %** (Ley 843 y modificaciones).
const double ivaBolivia = 0.1494;

/// IVA a cobrar sobre [base] cuando la venta es factura (2 decimales).
double ivaDe(double base) => base <= 0 ? 0 : dinero(base * ivaBolivia);

/// Valida que [valor] sea un método de pago conocido; devuelve el valor.
String ensureMetodoPago(String valor) {
  if (!metodosPago.contains(valor)) {
    throw BadRequestException(
      'El campo "metodoPago" debe ser uno de: ${metodosPago.join(', ')} '
      '(recibido: "$valor").',
      code: 'metodo_pago_invalido',
    );
  }
  return valor;
}

/// Valida una referencia opcional de pago (longitud máxima).
String? ensureReferencia(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.length > referenciaMaxima) {
    throw BadRequestException(
      'La referencia no puede superar $referenciaMaxima caracteres.',
      code: 'referencia_demasiado_larga',
    );
  }
  return limpio.isEmpty ? null : limpio;
}

/// Valida (y normaliza a mayúsculas) un género opcional.
String? ensureGenero(String? valor, {String campo = 'genero'}) {
  if (valor == null) return null;
  final normalized = valor.toUpperCase();
  if (!generosPermitidos.contains(normalized)) {
    throw BadRequestException(
      'El campo "$campo" debe ser uno de: ${generosPermitidos.join(', ')} '
      '(recibido: "$valor").',
      code: 'genero_invalido',
    );
  }
  return normalized;
}

/// Valida la edad mínima de un empleado (la BD exige `>= 18`).
int? ensureEdad(int? valor, {String campo = 'edad'}) {
  if (valor == null) return null;
  if (valor < 18 || valor > 120) {
    throw BadRequestException(
      'El campo "$campo" debe estar entre 18 y 120 (recibido: $valor).',
      code: 'edad_invalida',
    );
  }
  return valor;
}

/// Unidades de venta admitidas (columna `productos.unidad`).
///
/// En una tienda de ropa todo se vende **por unidad**: no hay pesos ni
/// cajas, así que `UN` es la única opción.
const Set<String> unidadesVenta = {'UN'};

/// Valida una unidad de venta (opcional en edición; `UN` si no viene).
String ensureUnidad(String? valor, {String campo = 'unidad'}) {
  final unidad = (valor ?? 'UN').trim().toUpperCase();
  if (!unidadesVenta.contains(unidad)) {
    throw BadRequestException(
      'El campo "$campo" debe ser uno de: ${unidadesVenta.join(', ')} '
      '(recibido: "${valor ?? ''}").',
      code: 'unidad_invalida',
    );
  }
  return unidad;
}

/// Longitud máxima del código interno / de barras (`productos.codigo`).
const int codigoMaximo = 60;

/// Valida un código de producto opcional: vacío = sin código (`NULL`).
///
/// La unicidad no se comprueba aquí sino en la BD (`idx_productos_codigo`),
/// que devuelve `409` como cualquier otro duplicado.
String? ensureCodigo(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length > codigoMaximo) {
    throw BadRequestException(
      'El campo "codigo" no puede superar $codigoMaximo caracteres.',
      code: 'field_too_long',
    );
  }
  return limpio;
}

/// Valida que una cantidad sea un número finito, no negativo y que quepa en
/// `NUMERIC(12, 3)` (`stock`, `stock_minimo`...). Devuelve 3 decimales.
double ensureNoNegativo(double valor, String campo, {double? maximo}) {
  final tope = maximo ?? 999999.999;
  if (valor.isNaN || valor.isInfinite) {
    throw BadRequestException(
      'El campo "$campo" debe ser un número.',
      code: 'field_invalid',
    );
  }
  if (valor < 0) {
    throw BadRequestException(
      'El campo "$campo" no puede ser negativo (recibido: $valor).',
      code: 'valor_negativo',
    );
  }
  if (valor > tope) {
    throw BadRequestException(
      'El campo "$campo" no puede superar $tope (recibido: $valor).',
      code: 'valor_demasiado_grande',
    );
  }
  return cantidad(valor);
}

/// Límite superior de las columnas `NUMERIC(10, 2)`.
const double importeMaximo = 99999999.99;

/// Valida que un importe sea un número finito, mayor o igual que cero,
/// que quepa en `NUMERIC(10, 2)` y lo devuelve redondeado a 2 decimales.
double ensureImporteNoNegativo(double valor, String campo) =>
    ensureImportePositivo(valor, campo, admiteCero: true);

/// Como [ensureImporteNoNegativo] pero exige ser estrictamente mayor que cero
/// (precios de venta, totales...). Un producto a `Bs 0` no se puede vender.
double ensureImportePositivo(
  double valor,
  String campo, {
  bool admiteCero = false,
}) {
  if (valor.isNaN || valor.isInfinite) {
    throw BadRequestException(
      'El campo "$campo" debe ser un número.',
      code: 'field_invalid',
    );
  }
  if (admiteCero ? valor < 0 : valor <= 0) {
    throw BadRequestException(
      admiteCero
          ? 'El campo "$campo" no puede ser negativo (recibido: $valor).'
          : 'El campo "$campo" debe ser mayor que 0 (recibido: $valor).',
      code: admiteCero ? 'valor_negativo' : 'valor_no_positivo',
    );
  }
  if (valor > importeMaximo) {
    throw BadRequestException(
      'El campo "$campo" no puede superar $importeMaximo (recibido: $valor).',
      code: 'valor_demasiado_grande',
    );
  }
  return dinero(valor);
}

/// Regla de negocio: **el precio de venta nunca baja del precio de compra**.
///
/// Devuelve el precio de venta redondeado a 2 decimales. [precioCompra] es el
/// coste conocido (`null` si el producto no lo tiene); se compara ya redondeado
/// para no equivocarse por coma flotante.
double ensurePrecioVenta(double precioVenta, double? precioCompra) {
  final venta = ensureImportePositivo(precioVenta, 'precioVenta');
  final coste = precioCompra == null
      ? null
      : ensureImporteNoNegativo(precioCompra, 'precioCompra');
  if (coste != null && venta < coste) {
    throw BadRequestException(
      'El precio de venta ($venta) no puede ser menor al precio de compra '
      '($coste): se vendería con pérdida.',
      code: 'precio_venta_bajo_costo',
    );
  }
  return venta;
}

/// Máximo en Bs que se puede rebajar por unidad (columna `precio_rebaja`).
///
/// `null` = sin límite; en cualquier caso no puede superar [precioVenta]
/// (ni ser negativo). Devuelve el valor redondeado a 2 decimales.
double? ensurePrecioRebaja(double? valor, double precioVenta) {
  if (valor == null) return null;
  final limpio = ensureImporteNoNegativo(valor, 'precioRebaja');
  if (limpio > precioVenta) {
    throw BadRequestException(
      'El máximo a rebajar ($limpio) no puede superar el precio de venta '
      '($precioVenta).',
      code: 'precio_rebaja_excesivo',
    );
  }
  return dinero(limpio);
}

/// Valida un CI (Cédula de Identidad, el documento de Bolivia):
/// **obligatorio** en altas —entre 7 y 15 dígitos—.
String ensureCi(String? valor) {
  if (valor == null || valor.trim().isEmpty) {
    throw BadRequestException(
      'El campo "ci" es obligatorio.',
      code: 'field_required',
    );
  }
  final limpio = valor.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d{7,15}$').hasMatch(limpio)) {
    throw BadRequestException(
      'El campo "ci" debe tener entre 7 y 15 dígitos (recibido: "$valor").',
      code: 'ci_invalido',
    );
  }
  return limpio;
}

/// Valida un teléfono (opcional): entre 6 y 15 dígitos, admitiendo
/// `+`, espacios, guiones y paréntesis (p. ej. `+51 999 888 777`).
String? ensureTelefono(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (!RegExp(r'^\+?[\d\s\-()]{6,20}$').hasMatch(limpio)) {
    throw BadRequestException(
      'El campo "telefono" solo admite dígitos, espacios, guiones y '
      'paréntesis (recibido: "$valor").',
      code: 'telefono_invalido',
    );
  }
  final digitos = limpio.replaceAll(RegExp(r'\D'), '');
  if (digitos.length < 6 || digitos.length > 15) {
    throw BadRequestException(
      'El campo "telefono" debe tener entre 6 y 15 dígitos '
      '(recibido: ${digitos.length}).',
      code: 'telefono_invalido',
    );
  }
  return limpio;
}

/// Texto obligatorio con longitud mínima (nombres de personas, productos,
/// categorías...). Devuelve el valor recortado.
String ensureNombre(
  String valor, {
  String campo = 'nombre',
  int minimo = 2,
  int maximo = 150,
}) {
  final limpio = valor.trim();
  if (limpio.length < minimo) {
    throw BadRequestException(
      'El campo "$campo" debe tener al menos $minimo caracteres '
      '(recibido: ${limpio.length}).',
      code: 'field_too_short',
    );
  }
  if (limpio.length > maximo) {
    throw BadRequestException(
      'El campo "$campo" no puede superar $maximo caracteres.',
      code: 'field_too_long',
    );
  }
  return limpio;
}

/// Apellido de personas: **obligatorio** en altas y en ediciones que lo
/// traigan (2-100 caracteres). Devuelve el valor recortado.
String ensureApellido(String? valor) {
  if (valor == null || valor.trim().isEmpty) {
    throw BadRequestException(
      'El campo "apellido" es obligatorio.',
      code: 'field_required',
    );
  }
  return ensureNombre(valor, campo: 'apellido', maximo: 100);
}

/// Descripción libre del producto (migración `023_descripcion_producto`):
/// opcional, sin longitud mínima y con un tope generoso. El texto se
/// recorta; `null` o la cadena vacía se quedan sin valor.
String? ensureDescripcion(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length > 2000) {
    throw const BadRequestException(
      'El campo "descripcion" no puede superar 2000 caracteres.',
      code: 'field_too_long',
    );
  }
  return limpio;
}

/// Valida un nombre de talla (`S`, `M`, `XL`, `38`, `40.5`, `39-41`,
/// `S/M`, `Única`...): letras cortas de vestir, números de calzado o de
/// niño, rango o combinación con `-` o `/`, o «Única».
///
/// Rechaza frases: «un par de medias» no es una talla. Es espejo de
/// `tallaValida` del frontend para que ambas capas digan lo mismo.
String ensureNombreTalla(String valor) {
  final limpio = ensureNombre(valor, campo: 'nombre', minimo: 1, maximo: 30);
  final patron = RegExp(
    r'^([uú]nica|(?:[0-9]{1,3}(?:\.\d)?|[sxmlgcpu]{1,4})'
    r'(?:[/-](?:[0-9]{1,3}(?:\.\d)?|[sxmlgcpu]{1,4}))*)$',
    caseSensitive: false,
  );
  if (!patron.hasMatch(limpio)) {
    throw BadRequestException(
      'El campo "nombre" no es una talla válida: usa letras cortas '
      '(S, M, XL, G), un número (38, 40), un rango (39-41) o «Única» '
      '— sin frases (recibido: "$valor").',
      code: 'talla_invalida',
    );
  }
  return limpio;
}

/// Valida un color de chip en hexadecimal (`#101010`); vacío = sin color.
String? ensureCodigoHex(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(limpio)) {
    throw BadRequestException(
      'El campo "codigoHex" debe tener el formato #RRGGBB '
      '(recibido: "$valor").',
      code: 'codigo_hex_invalido',
    );
  }
  return limpio.toUpperCase();
}

/// Valida un correo de contacto (opcional): forma `algo@dominio.tld` y
/// máximo 150 caracteres. `null` o vacío = sin correo.
String? ensureEmail(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length > 150) {
    throw BadRequestException(
      'El campo "email" no puede superar 150 caracteres.',
      code: 'field_too_long',
    );
  }
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(limpio)) {
    throw BadRequestException(
      'El campo "email" no tiene un formato válido (recibido: "$valor").',
      code: 'email_invalido',
    );
  }
  return limpio;
}

/// Valida el NIT de un proveedor (opcional): 4-20 caracteres con letras,
/// dígitos, punto o guion (`1234567018`, `1023456027-01`...).
String? ensureNit(String? valor) {
  if (valor == null) return null;
  final limpio = valor.trim();
  if (limpio.isEmpty) return null;
  if (limpio.length < 4 || limpio.length > 20) {
    throw BadRequestException(
      'El campo "nit" debe tener entre 4 y 20 caracteres '
      '(recibido: ${limpio.length}).',
      code: 'nit_invalido',
    );
  }
  if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z.\-]*[0-9A-Za-z]$').hasMatch(limpio)) {
    throw BadRequestException(
      'El campo "nit" solo admite letras, dígitos, punto y guion '
      '(recibido: "$valor").',
      code: 'nit_invalido',
    );
  }
  return limpio;
}

/// Valida un identificador de catálogo (tallaId, colorId): entero > 0.
int ensureIdDeCatalogo(int valor, String campo) {
  if (valor <= 0) {
    throw BadRequestException(
      'El campo "$campo" debe ser un identificador válido (recibido: $valor).',
      code: 'field_invalid',
    );
  }
  return valor;
}

/// Valida que una cantidad sea un número finito **mayor que cero** y lo
/// devuelve con 3 decimales (`cantidad` de un detalle de pedido o de una
/// cotización: se puede pedir 1.450 KG).
double ensurePositivo(double valor, String campo) {
  if (valor.isNaN || valor.isInfinite) {
    throw BadRequestException(
      'El campo "$campo" debe ser un número.',
      code: 'field_invalid',
    );
  }
  if (valor <= 0) {
    throw BadRequestException(
      'El campo "$campo" debe ser mayor que cero (recibido: $valor).',
      code: 'valor_no_positivo',
    );
  }
  if (valor > 999999.999) {
    throw BadRequestException(
      'El campo "$campo" no puede superar 999999.999 (recibido: $valor).',
      code: 'valor_demasiado_grande',
    );
  }
  return cantidad(valor);
}

/// Redondea a 2 decimales: los importes se calculan en Dart pero se guardan
/// en columnas `NUMERIC(10, 2)`, así evitamos desajustes por coma flotante.
double dinero(double valor) => double.parse(valor.toStringAsFixed(2));

/// Redondea a 3 decimales: cantidades y stock se guardan en columnas
/// `NUMERIC(12, 3)` (`12.750` kg), y el redondeo evita desajustes por coma
/// flotante al sumar líneas o descontar existencias.
double cantidad(double valor) => double.parse(valor.toStringAsFixed(3));

/// Un producto **oculto** (borrado lógico) es inexistente para nuevas
/// ventas o cotizaciones: no aparece en los listados, así que tampoco debe
/// poder colarse en una operación por API.
Product vendible(Product? producto, int id) {
  if (producto == null || producto.estado == estadoEliminado) {
    throw NotFoundException(
      producto == null
          ? 'El producto $id no existe.'
          : 'El producto $id no existe o está oculto.',
      code: 'producto_no_encontrado',
    );
  }
  return producto;
}

/// Un producto `DESCONTINUADO` no se puede vender ni cotizar.
void asegurarComprable(Product producto) {
  if (producto.estado == 'DESCONTINUADO') {
    throw ConflictException(
      'El producto "${producto.nombre}" está DESCONTINUADO.',
      code: 'producto_descontinuado',
    );
  }
}
