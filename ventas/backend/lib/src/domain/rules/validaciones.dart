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

/// Tipos de unidad de medida (`unidades_medida.tipo`).
///
/// `PESO` y `VOLUMEN` se fraccionan (kg, gramos, litros); `UNIDAD` agrupa lo
/// que se cuenta o se sirve por envase (unidad, caja, paquete, blister...).
const Set<String> tiposUnidad = {'PESO', 'VOLUMEN', 'UNIDAD'};

/// Máximo de decimales que admite la cantidad en una unidad: las columnas
/// de stock y de cantidad son `NUMERIC(12, 3)`.
const int decimalesUnidadMaximos = 3;

/// Longitud máxima del símbolo de una unidad (columna `productos.unidad`).
const int unidadCodigoMaximo = 10;

/// Valida el **símbolo** de una unidad de venta (`KG`, `ONZA`, `CAJA`...),
/// en mayúsculas y con 1 a 10 caracteres alfanuméricos.
///
/// Si [valor] viene vacío o no se envía se usa `UN`, porque la unidad de un
/// producto es opcional en la petición. Comprueba únicamente la **forma**:
/// que el código exista en el catálogo `unidades_medida` y esté activo lo
/// resuelve el caso de uso contra la BD (`asegurarUnidadVigente`), ya que la
/// lista fija `unidadesVenta` de la migración 016 la sustituyó la tabla
/// `unidades_medida` (017).
String ensureUnidad(String? valor, {String campo = 'unidad'}) {
  final texto = valor?.trim() ?? '';
  // `null`, vacío o en blanco = «sin unidad»: se usa la por defecto.
  final unidad = texto.isEmpty ? 'UN' : texto.toUpperCase();
  if (unidad.length > unidadCodigoMaximo ||
      !RegExp(r'^[A-Z0-9]+$').hasMatch(unidad)) {
    throw BadRequestException(
      'El campo "$campo" debe tener de 1 a $unidadCodigoMaximo caracteres '
      'alfanuméricos en mayúsculas, p. ej. KG o ONZA '
      '(recibido: "${valor ?? ''}").',
      code: 'unidad_invalida',
    );
  }
  return unidad;
}

/// Valida el `tipo` de una unidad de medida (`PESO`, `VOLUMEN`, `UNIDAD`).
String ensureTipoUnidad(String valor, {String campo = 'tipo'}) {
  final tipo = valor.trim().toUpperCase();
  if (!tiposUnidad.contains(tipo)) {
    throw BadRequestException(
      'El campo "$campo" debe ser uno de: ${tiposUnidad.join(', ')} '
      '(recibido: "$valor").',
      code: 'tipo_unidad_invalido',
    );
  }
  return tipo;
}

/// Valida cuántos decimales admite la cantidad de una unidad (0 a 3).
int ensureDecimalesUnidad(int valor, {String campo = 'decimales'}) {
  if (valor < 0 || valor > decimalesUnidadMaximos) {
    throw BadRequestException(
      'El campo "$campo" debe estar entre 0 y $decimalesUnidadMaximos '
      '(recibido: $valor).',
      code: 'decimales_invalidos',
    );
  }
  return valor;
}

/// Longitud máxima del código interno / de barras (`productos.codigo`).
const int codigoMaximo = 60;

/// Longitud máxima de la descripción libre (`productos.descripcion`).
const int descripcionMaxima = 255;

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

/// Descripción libre del producto: **opcional**, recortada y hasta
/// [descripcionMaxima] caracteres. Vacío o `null` → `null` («sin
/// descripción»); lo que sobrepasa → `400 field_too_long`.
String? ensureDescripcion(String? valor, {String campo = 'descripcion'}) {
  final limpio = valor?.trim() ?? '';
  if (limpio.isEmpty) return null;
  if (limpio.length > descripcionMaxima) {
    throw BadRequestException(
      'El campo "$campo" no puede superar $descripcionMaxima caracteres '
      '(recibido: ${limpio.length}).',
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

/// Las fechas de vencimiento no pueden quedar por detrás de hoy.
void ensureFechaNoVencida(
  DateTime? fecha, {
  String campo = 'fechaVencimiento',
  DateTime? hoy,
}) {
  if (fecha == null) return;
  final ahora = hoy ?? DateTime.now();
  final inicioDeHoy = DateTime(ahora.year, ahora.month, ahora.day);
  if (fecha.isBefore(inicioDeHoy)) {
    throw BadRequestException(
      'El campo "$campo" no puede ser anterior a hoy '
      '(${_fechaCorta(inicioDeHoy)}); recibido: ${_fechaCorta(fecha)}.',
      code: 'fecha_vencida',
    );
  }
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

/// Muestra de color hexadecimal `#RRGGBB` (opcional: solo el chip de la UI,
/// nunca se imprime). Devuelve `null` cuando no hay muestra y el valor con
/// `#` garantizado cuando sí la hay.
String? ensureCodigoHex(String? valor) {
  final limpio = (valor ?? '').trim();
  if (limpio.isEmpty) return null;
  final normalizado = limpio.startsWith('#') ? limpio : '#$limpio';
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(normalizado)) {
    throw BadRequestException(
      'El campo "codigoHex" debe ser un color hexadecimal #RRGGBB '
      '(recibido: "$valor").',
      code: 'codigo_hex_invalido',
    );
  }
  return normalizado;
}

/// Meses de garantía del producto (`null` = sin garantía). La UI ofrece
/// presets (3/6/12/18/24/36/48/60 meses) pero se acepta cualquier entero
/// entre 1 y 120; no hay tabla de garantías, series ni reclamos: es un dato
/// que solo se muestra en la ficha de detalle del producto.
int? ensureGarantiaMeses(int? valor) {
  if (valor == null) return null;
  if (valor < 1 || valor > 120) {
    throw BadRequestException(
      'El campo "garantiaMeses" debe estar entre 1 y 120 meses '
      '(recibido: $valor).',
      code: 'garantia_invalida',
    );
  }
  return valor;
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

String _fechaCorta(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

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
