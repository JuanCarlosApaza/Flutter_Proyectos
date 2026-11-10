/// Lectura y validación de las *formas* de las peticiones HTTP.
///
/// Esta capa solo se ocupa de la sintaxis (JSON válido, tipos, paginación);
/// las **reglas de negocio** viven en `domain/`. Cualquier problema de forma
/// se traduce en un `400 BadRequest` con el error estándar de la API.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/venta.dart';

/// Decodifica el cuerpo como un objeto JSON.
///
/// Lanza `400` si el cuerpo no es JSON válido o no es un objeto.
Future<Map<String, Object?>> readJsonObject(Request request) async {
  final raw = await request.readAsString();

  if (raw.trim().isEmpty) {
    throw const BadRequestException(
      'Se espera un cuerpo JSON.',
      code: 'body_missing',
    );
  }

  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw BadRequestException(
      'El cuerpo no es JSON válido: ${error.message}',
      code: 'body_invalid',
    );
  }

  if (decoded is! Map<String, Object?>) {
    throw const BadRequestException(
      'El cuerpo debe ser un objeto JSON.',
      code: 'body_not_object',
    );
  }
  return decoded;
}

/// Campo de texto obligatorio.
String requireText(
  Map<String, Object?> body,
  String field, {
  int maxLength = 0,
}) {
  final value = body[field];
  final text = value == null ? '' : value.toString().trim();
  if (text.isEmpty) {
    throw BadRequestException(
      'El campo "$field" es obligatorio.',
      code: 'field_required',
    );
  }
  if (maxLength > 0 && text.length > maxLength) {
    throw BadRequestException(
      'El campo "$field" no puede superar $maxLength caracteres.',
      code: 'field_too_long',
    );
  }
  return text;
}

/// Campo de texto opcional (`null` si falta o viene vacío).
String? textOrNull(
  Map<String, Object?> body,
  String field, {
  int maxLength = 0,
}) {
  final value = body[field];
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  if (maxLength > 0 && text.length > maxLength) {
    throw BadRequestException(
      'El campo "$field" no puede superar $maxLength caracteres.',
      code: 'field_too_long',
    );
  }
  return text;
}

/// Entero opcional (acepta `1`, `"1"` y `1.0`; rechaza texto no numérico y
/// decimales con parte fraccionaria: `categoriaId: 1.5` no es un número
/// entero).
int? intOrNull(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) {
    if (value != value.truncateToDouble()) {
      throw BadRequestException(
        'El campo "$field" debe ser un número entero (recibido: $value).',
        code: 'field_invalid',
      );
    }
    return value.toInt();
  }
  final parsed = int.tryParse(value.toString().trim());
  if (parsed == null) {
    throw BadRequestException(
      'El campo "$field" debe ser un número entero.',
      code: 'field_invalid',
    );
  }
  return parsed;
}

/// Número decimal opcional (acepta enteros, decimales y texto numérico).
double? doubleOrNull(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final parsed = double.tryParse(value.toString().trim());
  if (parsed == null || parsed.isNaN || parsed.isInfinite) {
    throw BadRequestException(
      'El campo "$field" debe ser un número.',
      code: 'field_invalid',
    );
  }
  return parsed;
}

/// Número decimal obligatorio.
double requireDouble(Map<String, Object?> body, String field) {
  if (body[field] == null) {
    throw BadRequestException(
      'El campo "$field" es obligatorio.',
      code: 'field_required',
    );
  }
  return doubleOrNull(body, field)!;
}

/// Fecha opcional en formato `yyyy-MM-dd` (o ISO-8601 completo).
DateTime? dateOrNull(Map<String, Object?> body, String field) {
  final value = body[field];
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw BadRequestException(
      'El campo "$field" debe ser una fecha válida (yyyy-MM-dd).',
      code: 'field_invalid',
    );
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Convierte el segmento de ruta `<id>` en entero (`400` si no lo es).
int pathId(String raw) {
  final id = int.tryParse(raw.trim());
  if (id == null || id <= 0) {
    throw BadRequestException(
      'El identificador "$raw" no es válido.',
      code: 'id_invalid',
    );
  }
  return id;
}

/// Lee `items: [{productoId, cantidad}, ...]` del cuerpo (órdenes y
/// cotizaciones). La validación de negocio (duplicados, stock, precios) la
/// hace el caso de uso; aquí solo se exige la forma.
List<ItemOrden> itemsDesdeBody(Map<String, Object?> body) {
  final raw = body['items'];
  if (raw is! List || raw.isEmpty) {
    throw const BadRequestException(
      'El campo "items" debe ser una lista no vacía de '
      '{productoId, varianteId?, cantidad}.',
      code: 'items_invalidos',
    );
  }

  final items = <ItemOrden>[];
  for (final element in raw) {
    if (element is! Map) {
      throw const BadRequestException(
        'Cada item debe ser un objeto con "productoId" y "cantidad".',
        code: 'item_invalido',
      );
    }
    final item = element.cast<String, Object?>();
    items.add(
      ItemOrden(
        productoId:
            intOrNull(item, 'productoId') ??
            (throw const BadRequestException(
              'Cada item necesita "productoId".',
              code: 'producto_requerido',
            )),
        // Talla + color de la prenda; si no viene y el producto tiene una
        // sola variante, el dominio la resuelve solo.
        varianteId: intOrNull(item, 'varianteId'),
        cantidad:
            doubleOrNull(item, 'cantidad') ??
            (throw const BadRequestException(
              'Cada item necesita "cantidad".',
              code: 'cantidad_requerida',
            )),
      ),
    );
  }
  return items;
}

/// Parámetros de paginación comunes (`limit`, `offset`) con sus límites.
({int limit, int offset}) paginationOf(Request request) {
  final query = request.url.queryParameters;
  final limit = int.tryParse(query['limit'] ?? '') ?? 50;
  final offset = int.tryParse(query['offset'] ?? '') ?? 0;
  if (limit < 1 || limit > 200) {
    throw const BadRequestException(
      '"limit" debe estar entre 1 y 200.',
      code: 'limit_invalid',
    );
  }
  if (offset < 0) {
    throw const BadRequestException(
      '"offset" no puede ser negativo.',
      code: 'offset_invalid',
    );
  }
  return (limit: limit, offset: offset);
}

/// Valor de un parámetro de consulta (`null` si no viene o está vacío).
///
/// Con [maxLength] > 0 se **recorta** el valor a ese número de caracteres
/// (mismo patrón de parámetro que [requireText], pero sin lanzar error: en
/// un `?q=` de búsqueda un texto larguísimo solo se truncaría).
String? queryOrNull(Request request, String name, {int maxLength = 0}) {
  var value = request.url.queryParameters[name]?.trim();
  if (value == null || value.isEmpty) return null;
  if (maxLength > 0 && value.length > maxLength) {
    value = value.substring(0, maxLength);
  }
  return value;
}

/// `204 No Content` (respuestas sin cuerpo, p. ej. DELETE).
Response noContent() => Response(204);

/// Extrae `nombre` + `estado` de un cuerpo de **creación**.
///
/// `nombre` es obligatorio; `estado` opcional (por defecto [estadoPorDefecto],
/// que la capa `domain/` volverá a validar contra el enum correspondiente).
({String nombre, String estado}) readNombreEstado(
  Map<String, Object?> body, {
  String estadoPorDefecto = 'ACTIVO',
  int maxNombre = 150,
}) => (
  nombre: requireText(body, 'nombre', maxLength: maxNombre),
  estado: textOrNull(body, 'estado') ?? estadoPorDefecto,
);

/// Extrae `nombre` + `estado` de un cuerpo de **actualización parcial**:
/// lo que no venga en el cuerpo no se modifica.
({String? nombre, String? estado}) readNombreEstadoParcial(
  Map<String, Object?> body, {
  int maxNombre = 150,
}) {
  final nombre = body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: maxNombre)
      : null;
  final estado = textOrNull(body, 'estado');
  if (nombre == null && estado == null) {
    throw const BadRequestException(
      'Indica al menos un campo a actualizar ("nombre" o "estado").',
      code: 'fields_required',
    );
  }
  return (nombre: nombre, estado: estado);
}

/// Subconjunto de [permitidos] que aparece en el cuerpo de la petición.
///
/// Permite distinguir *campo ausente* (no se toca) de *campo enviado* (se
/// escribe, aunque su valor sea `null`).
Set<String> camposEnviados(
  Map<String, Object?> body,
  List<String> permitidos,
) => permitidos.where(body.containsKey).toSet();

/// `400` si un cuerpo de actualización no trae ningún campo.
void ensureHayCampos(Set<String> campos) {
  if (campos.isEmpty) {
    throw const BadRequestException(
      'Indica al menos un campo a actualizar.',
      code: 'fields_required',
    );
  }
}
