import 'dart:async';
import 'dart:io';

import 'package:farmacia_backend/src/core/errors/app_exception.dart';
import 'package:farmacia_backend/src/core/log_asistente.dart';
import 'package:farmacia_backend/src/data/services/ollama_service.dart';
import 'package:test/test.dart';

/// Falla el test si [futuro] acaba bien; si no, devuelve la [AppException].
Future<AppException> errorDe(Future<Object?> futuro) async {
  try {
    await futuro;
    fail('Se esperaba una AppException y la operación terminó bien.');
  } on AppException catch (error) {
    return error;
  }
}

void main() {
  logAsistenteActivo = false;

  /// Servicio con la red sustituida por [peticion].
  OllamaService servicio(PeticionHttp peticion) => OllamaService(
    url: 'http://localhost:11434',
    modelo: 'farmacia-x',
    peticion: peticion,
  );

  final mensajes = [(rol: 'user', contenido: '¿cuántos medicamentos tengo?')];

  group('chat', () {
    test('monta el system y devuelve el texto del modelo', () async {
      String? metodo;
      Uri? uri;
      Object? enviado;

      final respuesta = await servicio((m, u, {cuerpo, timeout}) async {
        metodo = m;
        uri = u;
        enviado = cuerpo;
        return (
          codigo: 200,
          cuerpo: '{"message":{"role":"assistant","content":"Tienes 43."}}',
        );
      }).chat(contexto: 'SISTEMA', mensajes: mensajes);

      expect(respuesta, 'Tienes 43.');
      expect(metodo, 'POST');
      expect(uri.toString(), 'http://localhost:11434/api/chat');

      final mapa = enviado as Map<String, Object?>;
      expect(mapa['model'], 'farmacia-x');
      expect(mapa['stream'], false);
      final system = (mapa['messages'] as List).first as Map;
      expect(system['role'], 'system');
      expect(system['content'], 'SISTEMA');
      expect((mapa['messages'] as List).length, 2);
    });

    test(
      'Ollama caído (conexión rechazada) → 503 ollama_no_disponible',
      () async {
        final app = await errorDe(
          servicio(
            (m, u, {cuerpo, timeout}) async =>
                throw const SocketException('nada'),
          ).chat(contexto: 'x', mensajes: mensajes),
        );

        expect(app.statusCode, 503);
        expect(app.code, 'ollama_no_disponible');
        expect(app.message, contains('ollama.com'));
      },
    );

    test('timeout → 503 ollama_no_disponible', () async {
      final app = await errorDe(
        servicio(
          (m, u, {cuerpo, timeout}) async => throw TimeoutException('tarde'),
        ).chat(contexto: 'x', mensajes: mensajes),
      );

      expect(app.code, 'ollama_no_disponible');
      expect(app.message, contains('arrancado'));
    });

    test('404 → 503 modelo_faltante', () async {
      final app = await errorDe(
        servicio(
          (m, u, {cuerpo, timeout}) async => (codigo: 404, cuerpo: 'not found'),
        ).chat(contexto: 'x', mensajes: mensajes),
      );

      expect(app.code, 'modelo_faltante');
      expect(app.message, contains('descárgalo'));
    });

    test(
      '4xx con «no such model» también se traduce a modelo_faltante',
      () async {
        final app = await errorDe(
          servicio(
            (m, u, {cuerpo, timeout}) async =>
                (codigo: 400, cuerpo: 'model "x" no such model'),
          ).chat(contexto: 'x', mensajes: mensajes),
        );

        expect(app.code, 'modelo_faltante');
      },
    );

    test('respuesta sin contenido → modelo_sin_respuesta', () async {
      final app = await errorDe(
        servicio(
          (m, u, {cuerpo, timeout}) async =>
              (codigo: 200, cuerpo: '{"message":{"content":""}}'),
        ).chat(contexto: 'x', mensajes: mensajes),
      );

      expect(app.code, 'modelo_sin_respuesta');
    });
  });

  group('modelos', () {
    test('lee los names de /api/tags', () async {
      final lista = await servicio(
        (m, u, {cuerpo, timeout}) async => (
          codigo: 200,
          cuerpo: '{"models":[{"name":"farmacia-x:latest"},{"name":"otro"}]}',
        ),
      ).modelos();

      expect(lista, ['farmacia-x:latest', 'otro']);
    });

    test('modeloListo casa por prefijo (con y sin etiqueta)', () async {
      Future<bool> listo(String cuerpoJson) => servicio(
        (m, u, {cuerpo, timeout}) async => (codigo: 200, cuerpo: cuerpoJson),
      ).modeloListo();

      expect(await listo('{"models":[{"name":"farmacia-x:latest"}]}'), isTrue);
      expect(await listo('{"models":[{"name":"farmacia-x"}]}'), isTrue);
      expect(await listo('{"models":[{"name":"otro"}]}'), isFalse);
    });

    test(
      'si Ollama no está, modeloListo es false y modelos propaga 503',
      () async {
        final caido = servicio(
          (m, u, {cuerpo, timeout}) async =>
              throw const SocketException('nada'),
        );

        expect(await caido.modeloListo(), isFalse);

        final app = await errorDe(caido.modelos());
        expect(app.code, 'ollama_no_disponible');
      },
    );
  });
}
