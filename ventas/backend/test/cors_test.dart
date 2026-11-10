import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  /// `cors` montado sobre un handler que responde 200 'ok'.
  Handler montar({List<String> origenes = const ['*']}) => Pipeline()
      .addMiddleware(cors(origenesPermitidos: origenes))
      .addHandler((request) async => Response(200, body: 'ok'));

  group('CORS con comodín (desarrollo)', () {
    test('cualquier origin recibe access-control-allow-origin: *', () async {
      final respuesta = await montar()(
        Request(
          'GET',
          Uri.parse('http://localhost/x'),
          headers: {'origin': 'http://otro-dominio.test'},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(respuesta.headers['access-control-allow-origin'], '*');
    });

    test('el preflight OPTIONS responde 204 con los métodos', () async {
      final respuesta = await montar()(
        Request('OPTIONS', Uri.parse('http://localhost/x')),
      );

      expect(respuesta.statusCode, 204);
      expect(respuesta.headers['access-control-allow-origin'], '*');
      expect(
        respuesta.headers['access-control-allow-methods'],
        contains('POST'),
      );
    });
  });

  group('CORS con lista explícita (producción)', () {
    const origenes = ['http://localhost:8081', 'https://ventas.example.com'];

    test('origin permitido → eco exacto + Vary: origin', () async {
      final respuesta = await montar(origenes: origenes)(
        Request(
          'GET',
          Uri.parse('http://localhost/x'),
          headers: {'origin': 'https://ventas.example.com'},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(
        respuesta.headers['access-control-allow-origin'],
        'https://ventas.example.com',
      );
      expect(respuesta.headers['vary'], 'origin');
    });

    test('origin NO permitido → sin access-control-allow-origin', () async {
      final respuesta = await montar(origenes: origenes)(
        Request(
          'GET',
          Uri.parse('http://localhost/x'),
          headers: {'origin': 'http://atacante.test'},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(respuesta.headers['access-control-allow-origin'], isNull);
      expect(respuesta.headers['vary'], 'origin');
    });

    test('sin Origin (curl/smoke/<img>) → respuesta normal', () async {
      final respuesta = await montar(origenes: origenes)(
        Request('GET', Uri.parse('http://localhost/x')),
      );

      expect(respuesta.statusCode, 200);
      expect(await respuesta.readAsString(), 'ok');
    });

    test('preflight con origin permitido → 204 con eco', () async {
      final respuesta = await montar(origenes: origenes)(
        Request(
          'OPTIONS',
          Uri.parse('http://localhost/x'),
          headers: {'origin': 'http://localhost:8081'},
        ),
      );

      expect(respuesta.statusCode, 204);
      expect(
        respuesta.headers['access-control-allow-origin'],
        'http://localhost:8081',
      );
    });
  });
}
