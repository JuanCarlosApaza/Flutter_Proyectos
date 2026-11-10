import 'dart:developer' as developer;
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../core/errors/app_exception.dart';
import 'json_response.dart';

/// Middleware global de errores.
///
/// Cualquier [AppException] lanzada por una ruta se convierte en su código
/// HTTP; cualquier otro error se oculta y responde 500 (sin filtrar detalles
/// internos al cliente).
Middleware errorHandler({bool exposeDetails = false}) =>
    (Handler innerHandler) => (Request request) async {
      try {
        return await innerHandler(request);
      } on AppException catch (error) {
        developer.log(
          '${error.statusCode} ${request.method} ${request.requestedUri.path} '
          '-> ${error.message}',
          name: 'api.error',
        );
        return errorResponse(error.statusCode, error.message, code: error.code);
      } catch (error, stackTrace) {
        developer.log(
          'Error no controlado en ${request.method} '
          '${request.requestedUri.path}: $error\n$stackTrace',
          name: 'api.error',
          level: 1000,
        );
        return errorResponse(
          500,
          exposeDetails ? error.toString() : 'Error interno del servidor',
          code: 'internal_error',
        );
      }
    };

/// Cabeceras CORS + respuesta a las peticiones `OPTIONS` (preflight).
///
/// Sin esto, el frontend web (otro origen/puerto) no puede llamar a la API.
/// [origenesPermitidos] acepta `'*'` (desarrollo, cualquier origen) o una
/// lista explícita de orígenes; en producción conviene fijar la URL exacta
/// del frontend con la variable `CORS_ORIGINS`. Con lista explícita solo se
/// responde con `access-control-allow-origin` si el `Origin` de la petición
/// está permitido, y se añade `Vary: origin` para que ninguna caché mezcle
/// respuestas entre orígenes.
Middleware cors({List<String> origenesPermitidos = const ['*']}) =>
    (Handler innerHandler) => (Request request) async {
      const metodos = 'GET, POST, PUT, DELETE, OPTIONS';
      // `authorization` es imprescindible: sin él el navegador bloquea la
      // cabecera `Bearer <token>` del preflight y la web no podría llamar
      // a la API ya autenticada.
      const cabeceras = 'content-type, accept, authorization, x-request-id';

      final comodin = origenesPermitidos.contains('*');
      final origen = request.headers['origin'];
      final permitido = comodin
          ? '*'
          : (origen != null && origenesPermitidos.contains(origen))
          ? origen
          : null;

      Map<String, String> conCors(Map<String, String> headers) => {
        ...headers,
        // Null-aware: sin `Origin` permitido no se emite la cabecera.
        'access-control-allow-origin': ?permitido,
        // Con comodín la respuesta no depende del origen: sin `Vary` de
        // más para no fragmentar la caché.
        if (!comodin) 'vary': 'origin',
        'access-control-allow-methods': metodos,
        'access-control-allow-headers': cabeceras,
        'access-control-max-age': '86400',
      };

      if (request.method == 'OPTIONS') {
        return Response(204, headers: conCors(const {}));
      }

      final response = await innerHandler(request);
      return response.change(headers: conCors(const {}));
    };

/// Rechaza cuerpos con `content-length` por encima de [maxBytes] (413).
///
/// Corta el ataque de cuerpo gigante **antes** de que se lea un solo byte:
/// `readJsonObject` decodifica el cuerpo completo en memoria, así que sin
/// este tope un JSON de GB agotaría la RAM. No cubre transferencias
/// *chunked* sin cabecera, para las que está el `maxLength` de campos como
/// `datos` en la subida de imágenes.
Middleware limiteCuerpo({required int maxBytes}) =>
    (Handler innerHandler) => (Request request) {
      final largo = int.tryParse(request.headers['content-length'] ?? '');
      if (largo != null && largo > maxBytes) {
        throw PayloadTooLargeException(
          'El cuerpo de la petición supera el máximo de '
          '${maxBytes ~/ (1024 * 1024)} MB.',
        );
      }
      return innerHandler(request);
    };

/// IP del cliente: proxy (`x-forwarded-for`) o conexión directa.
///
/// La usan el rate-limit de login y la auditoría de eventos.
String? ipCliente(Request request) {
  final proxied = request.headers['x-forwarded-for'];
  if (proxied != null && proxied.trim().isNotEmpty) {
    return proxied.split(',').first.trim();
  }
  final info = request.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return null;
}

/// Añade un id a cada request y lo expone como cabecera `x-request-id`.
Middleware requestId() {
  var counter = 0;
  return (Handler innerHandler) => (Request request) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}-${counter++}';
    final response = await innerHandler(
      request.change(headers: {'x-request-id': id}),
    );
    return response.change(headers: {'x-request-id': id});
  };
}
