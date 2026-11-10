import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';

import '../../core/errors/app_exception.dart';
import '../../core/log_asistente.dart';
import 'ollama_service.dart';

/// Motor de lenguaje embebido (llama.cpp vía `llamadart`) para la APK.
///
/// Mismo contrato que [OllamaService] — clasificador y narrador no notan el
/// cambio — pero sin servidor: el GGUF se carga desde [rutaModelo] (el que
/// baja `DescargadorModelo`) y la inferencia corre en un **isolate propio**
/// para que la generación (segundos a minutos) nunca congele la API HTTP.
///
/// Si el isolate muere (crash nativo, p. ej. driver de GPU roto), las
/// peticiones pendientes fallan de inmediato y el siguiente mensaje lo
/// relanza — nunca deja al usuario esperando sin respuesta.
final class MotorLocalLlm implements ModeloConversacion {
  MotorLocalLlm({
    required this.modelo,
    required this.rutaModelo,
    this.timeoutChat = const Duration(seconds: 300),
    this.contextoTokens = 8192,
    this.maxTokens = 450,
  });

  @override
  final String modelo;

  /// Ruta absoluta del fichero `.gguf`.
  final String rutaModelo;

  /// Techo por petición: en un celular de 4 GB la inferencia en CPU puede
  /// tardar varios minutos con contexto largo; 300 s cubre el clasificador
  /// (con su reintento) más la narración.
  final Duration timeoutChat;

  /// Ventana de contexto (la del GGUF de Qwen2.5 es 8192).
  final int contextoTokens;

  /// Techo de tokens de respuesta: PENSO+JSON y la narración son cortos;
  /// limitarlo evita que el modelo divague y dispare el timeout.
  final int maxTokens;

  ReceivePort? _entrada;
  ReceivePort? _errores;
  Completer<SendPort>? _saludo;
  SendPort? _salida;
  Isolate? _aislante;
  Future<void>? _cola;
  int _proximoId = 0;
  final Map<int, Completer<String>> _esperas = <int, Completer<String>>{};

  bool get _archivoListo => File(rutaModelo).existsSync();

  @override
  Future<List<String>> modelos() async => _archivoListo ? [modelo] : const [];

  @override
  Future<bool> modeloListo() async => _archivoListo;

  /// Una generación a la vez: el motor es único y el pipeline del chat ya
  /// encadena clasificación → narración de forma secuencial.
  @override
  Future<String> chat({
    required String contexto,
    required List<({String rol, String contenido})> mensajes,
  }) {
    final anterior = _cola ?? Future<void>.value();
    final siguiente = anterior.then((_) => _generar(contexto, mensajes));
    _cola = siguiente.then((_) {}, onError: (_) {});
    return siguiente;
  }

  Future<String> _generar(
    String contexto,
    List<({String rol, String contenido})> mensajes,
  ) async {
    if (!_archivoListo) {
      throw const InfrastructureException(
        'El modelo no está instalado: descárgalo desde Ajustes.',
        code: 'modelo_faltante',
      );
    }
    final reloj = Stopwatch()..start();
    final texto = await _pedirAlMotor(contexto, mensajes);
    logAsistente(
      '«$modelo» local respondió en ${reloj.elapsed.inSeconds}s '
      '(${mensajes.length} mensajes → ${texto.length} caracteres)',
    );
    return texto;
  }

  Future<String> _pedirAlMotor(
    String contexto,
    List<({String rol, String contenido})> mensajes,
  ) async {
    await _asegurarMotor();
    final id = ++_proximoId;
    final esperado = Completer<String>();
    _esperas[id] = esperado;
    _salida!.send({
      'op': 'chat',
      'id': id,
      'ruta': rutaModelo,
      'contexto': contexto,
      'contextoTokens': contextoTokens,
      'maxTokens': maxTokens,
      'mensajes': [
        for (final m in mensajes) [m.rol, m.contenido],
      ],
    });
    try {
      return await esperado.future.timeout(timeoutChat);
    } on TimeoutException {
      _esperas.remove(id);
      logAsistenteError(
        'motor local sin respuesta en ${timeoutChat.inSeconds}s '
        '(¿isolate colgado o modelo muy lento?)',
      );
      throw const InfrastructureException(
        'El modelo local tardó demasiado en responder: inténtalo de nuevo.',
        code: 'ollama_no_disponible',
      );
    }
  }

  /// Lanza el isolate (o lo relanza tras una caída) y espera su saludo.
  Future<void> _asegurarMotor() async {
    if (_salida != null) return;
    if (_saludo == null) _escuchar();
    final errores = _errores;
    final saludo = _saludo!;
    await Isolate.spawn<Map<String, Object>>(
      _aislanteMotor,
      {'salida': _entrada!.sendPort},
      errorsAreFatal: true,
      onError: errores?.sendPort,
    );
    _salida = await saludo.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _motorCayo();
        throw const InfrastructureException(
          'No se pudo arrancar el motor local del asistente.',
          code: 'motor_local_fallido',
        );
      },
    );
  }

  /// Único listener de resultados y de errores del isolate (una sola vez
  /// por lanzamiento; se recrea si el isolate cae).
  void _escuchar() {
    final entrada = ReceivePort();
    final errores = ReceivePort();
    final saludo = Completer<SendPort>();
    _entrada = entrada;
    _errores = errores;
    _saludo = saludo;

    entrada.listen((dynamic mensaje) {
      if (mensaje is SendPort) {
        if (!saludo.isCompleted) saludo.complete(mensaje);
        return;
      }
      _alRecibir(mensaje);
    });
    errores.listen((_) => _motorCayo());
  }

  /// El isolate murió: se fallan las peticiones en vuelo y se prepara un
  /// relanzamiento limpio para el siguiente mensaje.
  void _motorCayo() {
    final pendientes = Map<int, Completer<String>>.from(_esperas);
    _esperas.clear();
    for (final esperado in pendientes.values) {
      if (!esperado.isCompleted) {
        esperado.completeError(
          const InfrastructureException(
            'El motor local terminó inesperadamente: vuelve a intentarlo.',
            code: 'motor_local_fallido',
          ),
        );
      }
    }
    _aislante?.kill(priority: Isolate.beforeNextEvent);
    _aislante = null;
    _salida = null;
    _saludo = null;
    _entrada?.close();
    _errores?.close();
    _entrada = null;
    _errores = null;
  }

  void _alRecibir(dynamic mensaje) {
    if (mensaje is! Map) return;
    final id = mensaje['id'];
    final esperado = id is int ? _esperas.remove(id) : null;
    if (esperado == null || esperado.isCompleted) return;
    if (mensaje['ok'] == true && mensaje['texto'] is String) {
      esperado.complete(mensaje['texto'] as String);
    } else {
      esperado.completeError(
        InfrastructureException(
          mensaje['error']?.toString() ?? 'El modelo local falló.',
          code: 'motor_local_fallido',
        ),
      );
    }
  }

  /// Detiene el isolate (uso de pruebas / apagado ordenado).
  Future<void> cerrar() async {
    try {
      _salida?.send({'op': 'cerrar'});
    } catch (_) {
      // El isolate ya puede haber terminado.
    }
    _motorCayo();
  }
}

/// Cuerpo del isolate de inferencia: posee el [LlamaEngine] (carga perezosa
/// del GGUF) y atiende peticiones `chat` en serie.
@pragma('vm:entry-point')
void _aislanteMotor(Map<String, Object> args) {
  final salida = args['salida'] as SendPort;
  final peticiones = ReceivePort();
  // Saludo: este es el puerto al que el padre debe mandar las peticiones.
  salida.send(peticiones.sendPort);

  LlamaEngine? motor;
  var rutaCargada = '';

  Future<void> atender(Map<dynamic, dynamic> mensaje) async {
    final id = mensaje['id'] as int;
    try {
      final ruta = mensaje['ruta'] as String;
      motor ??= LlamaEngine(LlamaBackend());
      if (rutaCargada != ruta) {
        if (rutaCargada.isNotEmpty) await motor!.unloadModel();
        final contexto = mensaje['contextoTokens'] as int;
        try {
          await motor!.loadModelSource(
            ModelSource.path(ruta),
            modelParams: ModelParams(contextSize: contexto),
          );
        } catch (_) {
          // Sin Vulkan (o driver roto) el fallo es al cargar con GPU:
          // se reintenta en CPU, más lento pero universal.
          await motor!.unloadModel();
          await motor!.loadModelSource(
            ModelSource.path(ruta),
            modelParams: ModelParams(contextSize: contexto, gpuLayers: 0),
          );
        }
        rutaCargada = ruta;
      }

      LlamaChatRole rolDe(String rol) =>
          rol == 'assistant' ? LlamaChatRole.assistant : LlamaChatRole.user;
      final mensajes = <LlamaChatMessage>[
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: mensaje['contexto'] as String,
        ),
        for (final par in (mensaje['mensajes'] as List))
          LlamaChatMessage.fromText(
            role: rolDe(par[0] as String),
            text: par[1] as String,
          ),
      ];

      final buffer = StringBuffer();
      await for (final chunk in motor!.create(
        mensajes,
        params: GenerationParams(
          maxTokens: mensaje['maxTokens'] as int,
          // Misma temperatura que el Modelfile de Ollama (0.3): datos del
          // negocio, fidelidad antes que creatividad.
          temp: 0.3,
        ),
      )) {
        if (chunk.choices.isEmpty) continue;
        final delta = chunk.choices.first.delta.content;
        if (delta != null) buffer.write(delta);
      }
      final texto = buffer.toString().trim();
      if (texto.isEmpty) {
        throw StateError('el modelo no devolvió nada');
      }
      salida.send({'id': id, 'ok': true, 'texto': texto});
    } catch (error) {
      salida.send({'id': id, 'ok': false, 'error': '$error'});
    }
  }

  peticiones.listen((dynamic mensaje) {
    if (mensaje is! Map) return;
    final op = mensaje['op'];
    if (op == 'cerrar') {
      peticiones.close();
      return;
    }
    if (op == 'chat') unawaited(atender(mensaje));
  });
}
