import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Respuesta JSON con el content-type correcto.
Response jsonResponse(int statusCode, Object? body) => Response(
  statusCode,
  body: jsonEncode(body),
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// Respuesta de listado paginado.
///
/// Con [total] real (COUNT con los mismos filtros) añade `limit`/`offset`
/// de eco; sin él se comporta como antes (`total` = filas devueltas), que
/// es lo que usan reportes, respaldos y detalles.
Response listJsonResponse(
  List<Map<String, Object?>> items, {
  int? total,
  int? limit,
  int? offset,
}) => jsonResponse(200, {
  'total': total ?? items.length,
  if (total != null) ...{'limit': limit, 'offset': offset},
  'items': items,
});

/// Cuerpo JSON de error estándar de la API.
Response errorResponse(int statusCode, String message, {String? code}) =>
    jsonResponse(statusCode, {
      'error': {'code': code ?? 'error', 'message': message},
    });
