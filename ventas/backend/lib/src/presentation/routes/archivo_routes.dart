import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../data/storage/almacenamiento_imagenes.dart';
import '../http/api_request.dart';
import '../http/json_response.dart';

/// Endpoints de imágenes:
///
///  - `POST /api/v1/archivos/imagenes` — sube una imagen en base64 y guarda
///    el fichero en local. Devuelve la **ruta** que hay que persistir
///    (`productos.imagen`, etc.).
///  - `GET  /api/v1/archivos/imagenes/{nombre}` — sirve el fichero con su
///    content-type y cachas largas (el nombre es inmutable).
///
/// El cuerpo de subida es JSON y no multipart para no introducir un parser
/// extra: el cliente manda `{"nombre": "foto.png", "datos": "<base64>"}`.
void addArchivoRoutes(
  Router router, {
  required AlmacenamientoImagenes almacen,
}) {
  router.post('/api/v1/archivos/imagenes', (Request request) async {
    final body = await readJsonObject(request);

    final nombre = requireText(body, 'nombre', maxLength: 255);
    // ~3 MB decodificados caben en ~4 MB de base64: el tope corta el campo
    // aunque el cliente pase un `content-length` engañoso o nulo (chunked).
    final datos = requireText(body, 'datos', maxLength: 4600000);

    // Acepta también el formato data URL (`data:image/png;base64,....`).
    final base64Limpio = datos.replaceFirst(
      RegExp(r'^data:image/[a-z0-9.+-]+;base64,', caseSensitive: false),
      '',
    );

    final List<int> bytes;
    try {
      bytes = base64.decode(base64Limpio.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const BadRequestException(
        'El campo "datos" no es base64 válido.',
        code: 'base64_invalido',
      );
    }

    final guardada = await almacen.guardar(
      nombreOriginal: nombre,
      bytes: bytes,
    );
    return jsonResponse(201, {
      'ruta': guardada.ruta,
      'nombre': guardada.nombre,
      'bytes': bytes.length,
    });
  });

  router.get('/api/v1/archivos/imagenes/<nombre>', (
    Request request,
    String nombre,
  ) async {
    final archivo = await almacen.leer(nombre);

    // Ficheros con nombre inmutable -> cachas agresivas con ETag.
    final etag = '"${archivo.nombre}"';
    if (request.headers['if-none-match'] == etag) {
      return Response(
        304,
        headers: {
          'etag': etag,
          'cache-control': 'public, max-age=31536000, immutable',
        },
      );
    }

    return Response(
      200,
      body: archivo.bytes,
      headers: {
        'content-type': archivo.contentType,
        'content-length': '${archivo.bytes.length}',
        'cache-control': 'public, max-age=31536000, immutable',
        'etag': etag,
      },
    );
  });
}
