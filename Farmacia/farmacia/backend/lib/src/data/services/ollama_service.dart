import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../../core/log_asistente.dart';

/// Respuesta cruda de una petición HTTP saliente.
typedef RespuestaHttp = ({int codigo, String cuerpo});

/// Petición HTTP saliente, inyectable para los tests (mismo patrón que el
/// `PgDump` de los respaldos): el servicio solo conoce este typedef.
typedef PeticionHttp = Future<RespuestaHttp> Function(
  String metodo,
  Uri uri, {
  Object? cuerpo,
  Duration? timeout,
});

/// Mínimo que el pipeline del chat (clasificador + narrador) necesita de un
/// motor de lenguaje. Hay dos implementaciones:
///
/// * [OllamaService] → servidor Ollama en la PC (por defecto);
/// * `MotorLocalLlm` → llama.cpp embebido en la APK (`CHAT_MOTOR=local`).
abstract interface class ModeloConversacion {
  /// Nombre del modelo configurado (`CHAT_MODEL`).
  String get modelo;

  /// Conversa con el modelo: [contexto] viaja como mensaje `system` y
  /// [mensajes] como conversación, sin streaming.
  Future<String> chat({
    required String contexto,
    required List<({String rol, String contenido})> mensajes,
  });

  /// Nombres de los modelos disponibles (para la ruta de estado).
  Future<List<String>> modelos();

  /// ¿Está el modelo [modelo] listo para usarse?
  Future<bool> modeloListo();
}

/// Cliente mínimo contra un servidor Ollama (`/api/chat`, `/api/tags`).
///
/// Ollama es un servicio local sin autenticación; lo que puede fallar es
/// que no esté instalado, no arranque o le falte el modelo, y eso se
/// traduce en errores tipados:
///
/// * `ollama_no_disponible` (503) → nadie escucha en `OLLAMA_URL`.
/// * `modelo_faltante` (503)      → Ollama vive pero no tiene el modelo.
///
/// El timeout de [chat] es generoso (180 s): un 1.5B en CPU tarda 5-30 s y
/// con un contexto largo puede pasar de un minuto.
final class OllamaService implements ModeloConversacion {
  OllamaService({
    required this.url,
    required this.modelo,
    PeticionHttp? peticion,
    this.timeoutChat = const Duration(seconds: 180),
  }) : _peticion = peticion ?? peticionHttp;

  /// Base del servidor (`OLLAMA_URL`, p. ej. `http://localhost:11434`).
  final String url;

  /// Modelo a usar (`CHAT_MODEL`, p. ej. `farmacia-qwen2.5-1.5b`).
  @override
  final String modelo;

  final Duration timeoutChat;
  final PeticionHttp _peticion;

  Uri _ruta(String path) => Uri.parse('$url$path');

  @override
  Future<String> chat({
    required String contexto,
    required List<({String rol, String contenido})> mensajes,
  }) async {
    final reloj = Stopwatch()..start();
    final cuerpo = await _pedir(
      'POST',
      _ruta('/api/chat'),
      cuerpo: {
        'model': modelo,
        'stream': false,
        // Baja a propósito: con datos del negocio hace falta fidelidad, no
        // creatividad. Reduce las invenciones de cifras en un modelo pequeño.
        'options': {'temperature': 0.3, 'num_ctx': 8192},
        'messages': [
          {'role': 'system', 'content': contexto},
          for (final m in mensajes) {'role': m.rol, 'content': m.contenido},
        ],
      },
      timeout: timeoutChat,
    );

    Object? decodificado;
    try {
      decodificado = jsonDecode(cuerpo);
    } on FormatException catch (error) {
      logAsistenteError(
        'respuesta ilegible de $modelo (${cuerpo.length} caracteres) → '
        '$error',
      );
      throw const InfrastructureException(
        'Ollama respondió algo que no entiendo.',
        code: 'ollama_respuesta_invalida',
      );
    }
    final mensaje = decodificado is Map<String, Object?>
        ? decodificado['message']
        : null;
    final texto = mensaje is Map<String, Object?> ? mensaje['content'] : null;
    if (texto is! String || texto.isEmpty) {
      logAsistenteError(
        '«$modelo» no devolvió nada en ${mensajes.length} mensajes: '
        '${_resumir(cuerpo)}',
      );
      throw const InfrastructureException(
        'El modelo no devolvió ninguna respuesta.',
        code: 'modelo_sin_respuesta',
      );
    }
    // Una respuesta sin streaming tarda 5-30 s; medirla de vez en cuando
    // sirve para saber si el modelo va lento de verdad o es otro el cuello.
    logAsistente(
      '«$modelo» respondió en ${reloj.elapsed.inSeconds}s '
      '(${mensajes.length} mensajes → ${texto.length} caracteres)',
    );
    return texto;
  }

  /// Nombres de los modelos instalados en Ollama (`/api/tags`).
  ///
  /// Si Ollama no responde **propaga** el `AppException` (`activo: false` en
  /// la ruta de estado); una respuesta ilegible sí devuelve lista vacía.
  @override
  Future<List<String>> modelos() async {
    try {
      final cuerpo = await _pedir('GET', _ruta('/api/tags'));
      final decodificado = jsonDecode(cuerpo);
      final lista = decodificado is Map<String, Object?>
          ? decodificado['models']
          : null;
      if (lista is! List) return const [];
      return [
        for (final item in lista)
          if (item is Map<String, Object?> && item['name'] is String)
            item['name'] as String,
      ];
    } on FormatException {
      return const [];
    }
  }

  /// ¿Está instalado el modelo [modelo]? Devuelve `false` también si Ollama
  /// no está (no distingue «caído» de «sin modelo»; eso lo hace [modelos]).
  @override
  Future<bool> modeloListo() async {
    try {
      final nombres = await modelos();
      return nombres.any((n) => n == modelo || n.startsWith('$modelo:'));
    } on AppException {
      return false;
    }
  }

  /// Ejecuta la petición y traduce los fallos de Ollama a [AppException].
  Future<String> _pedir(
    String metodo,
    Uri uri, {
    Object? cuerpo,
    Duration? timeout,
  }) async {
    final RespuestaHttp respuesta;
    try {
      respuesta = await _peticion(
        metodo,
        uri,
        cuerpo: cuerpo,
        timeout: timeout ?? const Duration(seconds: 15),
      );
    } on AppException {
      rethrow;
    } on TimeoutException catch (error) {
      _sinOllama(uri, error);
      throw const InfrastructureException(
        'Ollama tarda demasiado en responder: ¿está arrancado?',
        code: 'ollama_no_disponible',
      );
    } on SocketException catch (error) {
      _sinOllama(uri, error);
      throw const InfrastructureException(
        'No detecto Ollama. Instálalo desde ollama.com, arráncalo '
        '(«ollama serve») y vuelve a intentarlo.',
        code: 'ollama_no_disponible',
      );
    } on HttpException catch (error) {
      _sinOllama(uri, error);
      throw const InfrastructureException(
        'No detecto Ollama. Instálalo desde ollama.com, arráncalo '
        '(«ollama serve») y vuelve a intentarlo.',
        code: 'ollama_no_disponible',
      );
    } on IOException catch (error) {
      _sinOllama(uri, error);
      throw const InfrastructureException(
        'No se pudo hablar con Ollama: comprueba que esté arrancado.',
        code: 'ollama_no_disponible',
      );
    }

    if (respuesta.codigo == 404) {
      // 404 con `/api/chat` casi siempre es «modelo no instalado».
      logAsistenteError(
        '$metodo $uri → 404: no existe el modelo «$modelo» en Ollama',
      );
      throw const InfrastructureException(
        'El modelo no está instalado: descárgalo desde Ajustes.',
        code: 'modelo_faltante',
      );
    }
    if (respuesta.codigo >= 400) {
      // Algunas versiones responden el modelo ausente como error genérico.
      final cuerpoError = respuesta.cuerpo.toLowerCase();
      if (cuerpoError.contains('not found') ||
          cuerpoError.contains('no such model')) {
        logAsistenteError(
          '$metodo $uri → ${respuesta.codigo}: modelo «$modelo» no encontrado',
        );
        throw const InfrastructureException(
          'El modelo no está instalado: descárgalo desde Ajustes.',
          code: 'modelo_faltante',
        );
      }
      logAsistenteError(
        '$metodo $uri → ${respuesta.codigo}: ${_resumir(respuesta.cuerpo)}',
      );
      throw InfrastructureException(
        'Ollama respondió con un error (${respuesta.codigo}).',
        code: 'ollama_error',
      );
    }
    return respuesta.cuerpo;
  }

  /// Deja constancia del motivo real de «Ollama no disponible».
  ///
  /// Es el fallo que más se ve y el que menos rastro dejaba: el usuario solo
  /// lee un aviso en la burbuja y en el log solo aparecía `[503] /estado`.
  void _sinOllama(Uri uri, Object error) {
    logAsistenteError(
      'no responde $uri → ${error.runtimeType}: $error '
      '(código enviado: ollama_no_disponible)',
    );
  }

  /// Primeras ~200 letras de un cuerpo de error, para no inundar el log.
  static String _resumir(String cuerpo) => resumirLog(cuerpo);
}

/// Implementación real con `HttpClient` de `dart:io`.
Future<RespuestaHttp> peticionHttp(
  String metodo,
  Uri uri, {
  Object? cuerpo,
  Duration? timeout,
}) async {
  final cliente = HttpClient()..autoUncompress = false;
  try {
    final limite = timeout ?? const Duration(seconds: 15);
    final peticion = await cliente.openUrl(metodo, uri).timeout(limite);
    if (cuerpo != null) {
      peticion.headers.contentType = ContentType.json;
      peticion.write(jsonEncode(cuerpo));
    }
    final respuesta = await peticion.close().timeout(limite);
    final bytes = await respuesta.fold<List<int>>(
      <int>[],
      (acumulado, trozo) => acumulado..addAll(trozo),
    );
    return (codigo: respuesta.statusCode, cuerpo: utf8.decode(bytes));
  } finally {
    cliente.close(force: true);
  }
}
