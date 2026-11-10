import 'dart:convert';
import 'dart:io';

import 'package:ventas_backend/src/data/storage/almacenamiento_imagenes.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/archivo_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

void main() {
  late Directory carpeta;
  late Handler handler;

  /// PNG mínimo: la API valida los magic bytes, no la extensión.
  final png = base64Encode([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...List.filled(32, 0),
  ]);

  Future<Response> subir(Handler destino, String datos) async => await destino(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/archivos/imagenes'),
      body: jsonEncode({'nombre': 'prueba.png', 'datos': datos}),
    ),
  );

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('archivo_routes_test');
    final router = Router();
    addArchivoRoutes(
      router,
      almacen: AlmacenamientoImagenes(rutaDirectorio: carpeta.path),
    );
    handler = errorHandler()(router.call);
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  test('POST con PNG válido → 201 con la ruta pública', () async {
    final respuesta = await subir(handler, png);

    expect(respuesta.statusCode, 201);
    final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;
    expect(cuerpo['ruta'], contains('/api/v1/archivos/imagenes/'));
  });

  test('POST con binario que no es imagen → 400 formato_invalido', () async {
    final respuesta = await subir(handler, base64Encode([1, 2, 3]));

    expect(respuesta.statusCode, 400);
    expect(await respuesta.readAsString(), contains('formato_invalido'));
  });

  test('POST sin datos → 400 field_required', () async {
    final respuesta = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1/archivos/imagenes'),
        body: '{"nombre":"x.png"}',
      ),
    );

    expect(respuesta.statusCode, 400);
    expect(await respuesta.readAsString(), contains('field_required'));
  });

  test('POST con "datos" colosal → 400 sin decodificarlo', () async {
    // Por encima del maxLength del campo: corta antes de base64.decode.
    final gigante = 'A' * 4600001;
    final respuesta = await subir(handler, gigante);

    expect(respuesta.statusCode, 400);
    expect(await respuesta.readAsString(), contains('field_too_long'));
  });

  test('limiteCuerpo rechaza content-length por encima del tope → 413', () async {
    final conTope = errorHandler()(
      limiteCuerpo(maxBytes: 1)((request) async => Response(200, body: 'ok')),
    );

    // Shelf calcula content-length del cuerpo real (2 bytes > 1).
    final respuesta = await conTope(
      Request('POST', Uri.parse('http://localhost/x'), body: '{}'),
    );

    expect(respuesta.statusCode, 413);
    expect(await respuesta.readAsString(), contains('cuerpo_grande'));
  });

  test('limiteCuerpo deja pasar cuerpos dentro del tope', () async {
    final conTope = errorHandler()(
      limiteCuerpo(maxBytes: 1000)((request) async => Response(200, body: 'ok')),
    );

    final respuesta = await conTope(
      Request('POST', Uri.parse('http://localhost/x'), body: '{"a":1}'),
    );

    expect(respuesta.statusCode, 200);
  });
}
