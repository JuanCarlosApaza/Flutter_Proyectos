import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../errors/failure.dart';

/// Cliente HTTP mínimo que solo devuelve JSON ya decodificado.
///
/// Único punto del frontend que conoce `package:http`; las fuentes de datos
/// trabajan con `Map`/`List` y traducen cualquier error a [Failure].
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
    : _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  /// Token de sesión; se envía en todas las peticiones como
  /// `Authorization: Bearer <token>`. `null` = sin sesión (p. ej. en login).
  String? token;

  /// Se invoca cuando el servidor responde `401` **habiendo** enviado un
  /// token: la sesión ya no vale y hay que volver al login. Lo conecta el
  /// `AuthController`; no se dispara en el propio login (todavía no hay
  /// token, así que un fallo de credenciales no lo provoca).
  void Function()? onUnauthorized;

  /// Se invoca cuando la API responde `403 suscripcion_vencida`: el
  /// `AuthController` levanta la pantalla de bloqueo (con el campo de la
  /// clave) y congela el resto de la app.
  void Function(String motivo)? onSuscripcionVencida;

  /// GET `[path]` y devuelve el cuerpo JSON (objeto o lista).
  Future<Object> get(String path, {Map<String, String>? query}) =>
      _enviar('GET', path, query: query);

  /// POST `[path]` con [body] JSON y devuelve la respuesta decodificada.
  ///
  /// [timeout] solo lo necesita el chat del asistente: sin streaming, una
  /// respuesta del modelo local puede tardar 30 s o más, y los 8 s por
  /// defecto cortarían la petición.
  Future<Object> post(
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration? timeout,
  }) => _enviar('POST', path, query: query, body: body, timeout: timeout);

  /// PUT `[path]` con [body] JSON (actualización parcial en esta API).
  Future<Object> put(String path, {Object? body, Map<String, String>? query}) =>
      _enviar('PUT', path, query: query, body: body);

  /// DELETE `[path]` (204 sin cuerpo -> se devuelve `{}`).
  Future<Object> delete(String path, {Map<String, String>? query}) =>
      _enviar('DELETE', path, query: query);

  /// GET `[path]` y devuelve el **cuerpo en bytes** (descargas: `.dump`,
  /// binarios…). A diferencia de los demás métodos no intenta decodificar
  /// JSON; los errores de la API (`4xx/5xx`) sí se traducen a [Failure].
  Future<List<int>> getBytes(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: headers)
          .timeout(ApiConfig.connectTimeout);
    } on TimeoutException {
      throw const NetworkFailure('El servidor tardó demasiado en responder');
    } on Exception {
      throw const NetworkFailure();
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call();
      }
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        decoded = null;
      }
      throw ServerFailure(
        _messageFrom(decoded) ?? 'No se pudo descargar el fichero',
        statusCode: response.statusCode,
        code: _codeFrom(decoded),
      );
    }
    return response.bodyBytes;
  }

  Future<Object> _enviar(
    String metodo,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);

    final headers = <String, String>{
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      if (token != null && token!.isNotEmpty) 'authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = await _peticion(
        metodo,
        uri,
        headers,
        body,
      ).timeout(timeout ?? ApiConfig.connectTimeout);
    } on TimeoutException {
      throw const NetworkFailure('El servidor tardó demasiado en responder');
    } on Exception {
      // Errores de red/tls/dns del cliente HTTP.
      throw const NetworkFailure();
    }

    if (response.bodyBytes.isEmpty) return <String, Object?>{};

    Object decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes)) ?? <String, Object?>{};
    } on FormatException {
      throw const ParsingFailure();
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && token != null) {
        onUnauthorized?.call();
      }
      final fallo = ServerFailure(
        _messageFrom(decoded) ?? 'Error del servidor',
        statusCode: response.statusCode,
        code: _codeFrom(decoded),
      );
      if (fallo.code == 'suscripcion_vencida') {
        onSuscripcionVencida?.call(fallo.message);
      }
      throw fallo;
    }
    return decoded;
  }

  Future<http.Response> _peticion(
    String metodo,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    switch (metodo) {
      case 'POST':
        return _client.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        return _client.put(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return _client.delete(uri, headers: headers);
      default:
        return _client.get(uri, headers: headers);
    }
  }

  static String? _messageFrom(Object? body) {
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) return error['message'] as String?;
      if (error is String) return error;
    }
    return null;
  }

  /// `error.code` del cuerpo de error de la API (`{'error': {code, message}}`).
  static String? _codeFrom(Object? body) {
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) return error['code'] as String?;
    }
    return null;
  }
}
