import 'dart:convert';

import 'package:farmacia/core/network/api_client.dart';
import 'package:farmacia/presentation/controllers/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Respuesta JSON como la manda el backend: bytes UTF-8 con su `charset`.
///
/// `http.Response(cuerpo)` sin cabecera codifica en latin1, y ahí cualquier
/// acento («¿cuántos?») se convierte en bytes inválidos para el `utf8.decode`
/// del `ApiClient`. El servidor real sí manda la cabecera, así que el doble
/// tiene que reproducirla para que el test mida lo mismo que la calle.
http.Response _json(Object cuerpo, int codigo) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  codigo,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// Backend falso que responde por ruta y anota lo que se le manda, para
/// poder asertar tanto el historial como el progreso de la descarga.
class _FalsoBackend {
  /// Ruta de la última petición recibida.
  String? ultimaRuta;

  /// Cuerpo del último `POST /chat`.
  Map<String, Object?>? ultimoBody;

  /// Respuesta que devolverá `POST /chat`.
  String respuesta = 'Tienes 43 productos activos.';

  /// Si se fija, `POST /chat` incluye también el «PENSO» de la IA.
  String? pensamiento;

  /// JSON de `GET /chat/estado`.
  Map<String, Object?> estado = {
    'ollamaActivo': true,
    'modeloListo': true,
    'modelo': 'farmacia-qwen2.5-1.5b',
    'descarga': {'fase': 'inactivo', 'bytes': 0},
  };

  /// Si se fija, `POST /chat` responde con este error de la API.
  ({int codigo, String code, String mensaje})? falloChat;

  MockClient cliente() => MockClient((request) async {
    ultimaRuta = request.url.path;

    if (request.url.path == '/api/v1/chat/estado') {
      return _json(estado, 200);
    }
    if (request.url.path == '/api/v1/chat/modelo/descarga') {
      // Devuelve la misma fase que el estado: así un test puede moverla
      // entre sondeos (descargando → creando → error).
      return _json({'descarga': estado['descarga']}, 200);
    }
    if (request.url.path == '/api/v1/chat/modelo/descargar') {
      return _json({
        'descarga': {'fase': 'descargando', 'bytes': 10, 'porcentaje': 1},
      }, 202);
    }

    final fallo = falloChat;
    if (fallo != null) {
      return _json({
        'error': {'code': fallo.code, 'message': fallo.mensaje},
      }, fallo.codigo);
    }

    if (request.body.isNotEmpty) {
      ultimoBody = (jsonDecode(request.body) as Map).cast<String, Object?>();
    }
    return _json({
      'respuesta': respuesta,
      if (pensamiento != null) 'pensamiento': pensamiento,
    }, 200);
  });

  /// Fija la fase de descarga del próximo `GET /chat/estado`.
  void fase(String fase, {int bytes = 0, String? error, int? porcentaje}) {
    final descarga = <String, Object?>{'fase': fase, 'bytes': bytes};
    if (porcentaje != null) descarga['porcentaje'] = porcentaje;
    if (error != null) descarga['error'] = error;

    estado = {
      'ollamaActivo': true,
      'modeloListo': false,
      'modelo': 'farmacia-x',
      'descarga': descarga,
    };
  }
}

void main() {
  late _FalsoBackend backend;
  late ChatController chat;

  /// Controlador contra un backend que siempre falla a nivel de red.
  ChatController conRedRota() {
    final roto = ChatController(
      ApiClient(
        baseUrl: 'http://test',
        client: MockClient((_) async => throw http.ClientException('x')),
      ),
    );
    addTearDown(roto.dispose);
    return roto;
  }

  setUp(() {
    backend = _FalsoBackend();
    chat = ChatController(
      ApiClient(baseUrl: 'http://test', client: backend.cliente())
        ..token = 'token',
    );
    addTearDown(chat.dispose);
  });

  group('cargarEstado', () {
    test('lee Ollama, modelo y fase de descarga', () async {
      await chat.cargarEstado();

      expect(chat.estado.ollamaActivo, isTrue);
      expect(chat.estado.modeloListo, isTrue);
      expect(chat.estado.modelo, 'farmacia-qwen2.5-1.5b');
      expect(chat.estado.fase, 'inactivo');
      expect(chat.estado.listo, isTrue);
      expect(chat.estado.descargando, isFalse);
    });

    test('si Ollama está caído lo refleja sin lanzar', () async {
      backend.estado = {
        'ollamaActivo': false,
        'modeloListo': false,
        'modelo': 'farmacia-x',
        'descarga': {'fase': 'inactivo', 'bytes': 0},
      };

      await chat.cargarEstado();

      expect(chat.estado.ollamaActivo, isFalse);
      expect(chat.estado.listo, isFalse);
      expect(chat.error, isNull);
    });

    test('lee la fase de descarga con porcentaje y error', () async {
      backend.fase('descargando', bytes: 512, porcentaje: 40);

      await chat.cargarEstado();

      expect(chat.estado.fase, 'descargando');
      expect(chat.estado.porcentaje, 40);
      expect(chat.estado.bytes, 512);
      expect(chat.estado.descargando, isTrue);
    });

    test('la fase de error conserva el mensaje legible', () async {
      backend.fase('error', error: 'Se cortó la conexión');

      await chat.cargarEstado();

      expect(chat.estado.fase, 'error');
      expect(chat.estado.descargaError, 'Se cortó la conexión');
      expect(chat.estado.descargando, isFalse);
    });

    test('un fallo de red no lanza (la burbuja sigue usable)', () async {
      final roto = conRedRota();

      await roto.cargarEstado();

      expect(roto.estado, EstadoChat.desconocido);
      expect(roto.error, isNull);
    });
  });

  group('enviar', () {
    test('el pensamiento de la IA se muestra como mensaje previo', () async {
      backend.pensamiento = 'Quiere saber el stock del ibuprofeno.';
      await chat.enviar('cuanto tengo de ibuprofeno');

      expect(chat.conversacion, hasLength(3));
      expect(chat.conversacion[1].esUsuario, isFalse);
      expect(chat.conversacion[1].texto, startsWith('Pienso:'));
      expect(chat.conversacion.last.texto, 'Tienes 43 productos activos.');
      backend.pensamiento = null;
    });

    test('monta el historial completo y añade la respuesta', () async {
      await chat.enviar('¿Cuántos medicamentos tengo?');
      backend.respuesta = 'Ahora hay 40.';
      await chat.enviar('¿Y de ibuprofeno?');

      expect(backend.ultimaRuta, '/api/v1/chat');
      // El cuerpo de la 2.ª llamada lleva los tres turnos previos: el que
      // acaba de escribirse no puede estar en el payload que lo contiene.
      final enviados = backend.ultimoBody!['mensajes'] as List;
      expect(enviados, hasLength(3));
      expect((enviados.first as Map)['role'], 'user');
      expect(
        (enviados.first as Map)['content'],
        '¿Cuántos medicamentos tengo?',
      );
      expect((enviados[1] as Map)['role'], 'assistant');
      expect((enviados[1] as Map)['content'], 'Tienes 43 productos activos.');
      expect((enviados.last as Map)['content'], '¿Y de ibuprofeno?');

      expect(chat.conversacion, hasLength(4));
      expect(chat.conversacion.last.texto, 'Ahora hay 40.');
      expect(chat.enviando, isFalse);
      expect(chat.error, isNull);
    });

    test('una pregunta vacía o en blanco no envía nada', () async {
      await chat.enviar('    ');

      expect(backend.ultimaRuta, isNull);
      expect(chat.conversacion, isEmpty);
      expect(chat.enviando, isFalse);
    });

    test('un 503 de Ollama caído se traduce a un mensaje accionable', () async {
      backend.falloChat = (
        codigo: 503,
        code: 'ollama_no_disponible',
        mensaje: 'No detecto Ollama.',
      );

      await chat.enviar('¿Cuántos tengo?');

      expect(chat.error, contains('ollama.com'));
      expect(chat.enviando, isFalse);
      // El turno del usuario se queda para poder reintentar.
      expect(chat.conversacion, hasLength(1));
      expect(chat.conversacion.first.esUsuario, isTrue);
    });

    test('falta el modelo → el error apunta a Ajustes', () async {
      backend.falloChat = (
        codigo: 503,
        code: 'modelo_faltante',
        mensaje: 'El modelo no está instalado.',
      );

      await chat.enviar('hola');

      expect(chat.error, contains('Ajustes'));
    });

    test('un error genérico conserva el mensaje del servidor', () async {
      backend.falloChat = (
        codigo: 400,
        code: 'mensajes_invalidos',
        mensaje: 'El campo mensajes debe ser una lista no vacía.',
      );

      await chat.enviar('hola');

      expect(chat.error, contains('mensajes'));
      expect(chat.error, contains('vacía'));
    });

    test('no se envía dos veces mientras la primera va en vuelo', () async {
      // `enviando` bloquea el segundo: el payload no debe crecer por ello.
      final primero = chat.enviar('hola');
      final segundo = chat.enviar('otra');
      await Future.wait([primero, segundo]);

      expect(chat.conversacion.first.texto, 'hola');
      expect(chat.conversacion.map((m) => m.texto), isNot(contains('otra')));
    });

    test('limpiarError borra el aviso sin tocar la conversación', () async {
      backend.falloChat = (codigo: 503, code: 'x', mensaje: 'y');
      await chat.enviar('hola');
      expect(chat.error, isNotNull);

      chat.limpiarError();

      expect(chat.error, isNull);
      expect(chat.conversacion, hasLength(1));
    });

    test('una respuesta sin texto se trata como fallo, no como mensaje',
        () async {
      backend.respuesta = '';

      await chat.enviar('hola');

      expect(chat.error, isNotNull);
      expect(chat.conversacion, hasLength(1));
    });
  });

  group('descarga del modelo', () {
    test('descargarModelo lanza la descarga y refresca el estado', () async {
      backend.fase('descargando', bytes: 100, porcentaje: 2);

      await chat.descargarModelo();

      expect(backend.ultimaRuta, '/api/v1/chat/estado');
      expect(chat.estado.descargando, isTrue);
      expect(chat.estado.porcentaje, 2);
    });

    test('sondearDescarga avanza la fase y mantiene el aviso limpio', () async {
      backend.fase('descargando', bytes: 100, porcentaje: 2);
      await chat.cargarEstado();
      backend.fase('creando', bytes: 1048576);

      await chat.sondearDescarga();

      expect(backend.ultimaRuta, '/api/v1/chat/modelo/descarga');
      expect(chat.estado.fase, 'creando');
      expect(chat.estado.bytes, 1048576);
      expect(chat.estado.descargando, isTrue);
    });

    test('sondearDescarga sin descarga en marcha no pide nada', () async {
      await chat.cargarEstado();
      final rutaTrasEstado = backend.ultimaRuta;

      await chat.sondearDescarga();

      expect(backend.ultimaRuta, rutaTrasEstado);
    });

    test('la fase de error del sondeo deja el mensaje legible', () async {
      backend.fase('descargando', bytes: 10);
      await chat.cargarEstado();
      backend.fase('error', bytes: 50, error: 'Sin conexión');

      await chat.sondearDescarga();

      expect(chat.estado.fase, 'error');
      expect(chat.estado.bytes, 50);
      expect(chat.estado.descargaError, 'Sin conexión');
      expect(chat.estado.descargando, isFalse);
    });
  });

  test('limpiar vacía la conversación y el aviso', () async {
    await chat.enviar('hola');
    chat.limpiar();

    expect(chat.conversacion, isEmpty);
    expect(chat.error, isNull);
  });

  test('reiniciar borra todo: la cuenta siguiente no hereda nada', () async {
    await chat.cargarEstado();
    await chat.enviar('hola');
    expect(chat.conversacion, isNotEmpty);
    expect(chat.estado.listo, isTrue);

    chat.reiniciar();

    expect(chat.conversacion, isEmpty);
    expect(chat.error, isNull);
    expect(chat.estado, EstadoChat.desconocido);
  });

  test('los errores de red quedan en el aviso, nunca lanzan', () async {
    final roto = conRedRota();

    await roto.enviar('hola');

    expect(roto.error, isA<String>());
    expect(roto.error, isNotEmpty);
    expect(roto.enviando, isFalse);
  });

  test('una respuesta que no es JSON se traduce a un aviso', () async {
    final chat2 = ChatController(
      ApiClient(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('no es json', 200)),
      ),
    );
    addTearDown(chat2.dispose);

    await chat2.enviar('hola');

    expect(chat2.error, isNotNull);
    expect(chat2.conversacion, hasLength(1));
  });
}
