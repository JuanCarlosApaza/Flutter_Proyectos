import 'dart:async';
import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../../core/log_asistente.dart';

/// Fases de la descarga del modelo, en el orden en que ocurren.
enum FaseDescarga { inactivo, descargando, creando, listo, error }

/// Estado global de la descarga, leído por la UI en cada sondeo.
class EstadoDescarga {
  const EstadoDescarga({
    this.fase = FaseDescarga.inactivo,
    this.porcentaje,
    this.bytes = 0,
    this.error,
  });

  final FaseDescarga fase;

  /// `0-100` solo mientras se descarga; `null` si no se conoce el total
  /// (HuggingFace puede responder sin `content-length` tras redireccionar).
  final int? porcentaje;

  /// Bytes descargados hasta ahora.
  final int bytes;

  /// Mensaje legible cuando [fase] es [FaseDescarga.error].
  final String? error;

  bool get activo =>
      fase == FaseDescarga.descargando || fase == FaseDescarga.creando;

  Map<String, Object?> toJson() => {
    'fase': fase.name,
    if (porcentaje != null) 'porcentaje': porcentaje,
    'bytes': bytes,
    if (error != null) 'error': error,
  };
}

/// Descarga de un fichero completo, inyectable para los tests (patrón
/// `PgDump` de los respaldos): el descargador solo conoce este typedef,
/// no la red.
///
/// [onProgreso] se invoca con los bytes recibidos y el total si se conoce
/// (`null` en caso contrario).
typedef DescargaFichero = Future<void> Function(
  Uri uri,
  File destino, {
  required void Function(int recibidos, int? total) onProgreso,
});

/// Ejecución de `ollama create`, inyectable de la misma manera.
typedef OllamaCreate = Future<({int codigo, String error})> Function(
  List<String> argumentos,
);

/// Descarga el GGUF de HuggingFace y lo registra en Ollama.
///
/// Flujo: `models/<f>.part` → renombrar a `models/<f>` →
/// `ollama create <CHAT_MODEL> -f Modelfile`. Sin reanudación: si falla a
/// mitad, la próxima empieza de cero (decidido en el plan). Si el fichero
/// ya está completo, se salta directo a la fase `creando`.
final class DescargadorModelo {
  DescargadorModelo({
    required this.url,
    required this.modelo,
    required this.directorio,
    this.local = false,
    DescargaFichero? descargar,
    OllamaCreate? crear,
  }) : _descargar = descargar ?? descargarFichero,
       _crear = crear ?? ollamaCreate;

  /// URL del GGUF (`CHAT_HF_URL`).
  final String url;

  /// Nombre del modelo a crear en Ollama (`CHAT_MODEL`).
  final String modelo;

  /// Carpeta destino (`MODELOS_DIR`).
  final String directorio;

  /// Motor local embebido (`CHAT_MOTOR=local`): el `.gguf` YA es el modelo,
  /// así que no hay `ollama create` que ejecutar ni binario que comprobar.
  final bool local;

  final DescargaFichero _descargar;
  final OllamaCreate _crear;

  EstadoDescarga _estado = const EstadoDescarga();

  /// Instantánea del progreso (la UI sondea cada 500 ms).
  EstadoDescarga get estado => _estado;

  /// ¿Se puede ejecutar `ollama` en esta máquina?
  ///
  /// Mira solo el binario, no la red: es lo único que hace falta para
  /// registrar el modelo con `ollama create`. Sirve para no ofrecer una
  /// descarga de un GB que no se podría completar (falla recién llegada al
  /// 100 %, justo el peor momento para el usuario).
  Future<bool> comandoDisponible() async {
    // Motor local: no hace falta ningún binario, la descarga ya es el final.
    if (local) return true;
    final resultado = await _crear(const ['--version']);
    if (resultado.codigo == 127) {
      // Sin esto la descarga solo podría fallar al llegar al 100 %.
      logAsistenteError(
        'no encuentro el comando ollama: '
        '${resultado.error.trim().isEmpty ? 'sin salida' : resultado.error.trim()}',
      );
    }
    return resultado.codigo != 127;
  }

  String get _nombreFichero {
    final ultimo = url.split('/').last.split('?').first;
    return ultimo.isEmpty ? 'modelo.gguf' : ultimo;
  }

  String get _rutaGguf => '$directorio${Platform.pathSeparator}$_nombreFichero';
  String get _rutaPart => '$_rutaGguf.part';

  /// Lanza la descarga en segundo plano. Si ya hay una en marcha, la
  /// segunda llamada se ignora (el botón queda deshabilitado igualmente).
  Future<void> iniciar() async {
    if (_estado.activo) return;
    _publicar(const EstadoDescarga(fase: FaseDescarga.descargando));
    // Sin `await`: la ruta responde 202 de inmediato y el progreso se lee
    // después con GET /chat/modelo/descarga.
    unawaited(_ejecutar());
  }

  Future<void> _ejecutar() async {
    try {
      Directory(directorio).createSync(recursive: true);
      final destino = File(_rutaGguf);

      if (destino.existsSync() && destino.lengthSync() > 0) {
        // Ya se descargó antes: el GB no se vuelve a bajar.
        logAsistente(
          'GGUF ya presente (${bytesLegibles(destino.lengthSync())}): '
          'se salta la descarga',
        );
        _publicar(
          EstadoDescarga(
            fase: FaseDescarga.creando,
            bytes: destino.lengthSync(),
          ),
        );
      } else {
        logAsistente('descargando el GGUF desde $url');
        await _bajar(destino);
        // El `.part` ya es `.gguf`: este tamaño es el del fichero bueno.
        logAsistente(
          'descarga completa: ${bytesLegibles(destino.lengthSync())}',
        );
      }

      await _crearEnOllama(destino);
      _publicar(
        EstadoDescarga(fase: FaseDescarga.listo, bytes: destino.lengthSync()),
      );
      logAsistente('modelo «$modelo» listo en Ollama');
    } on AppException catch (error) {
      _borrarPart();
      logAsistenteError(
        '${error.code ?? 'descarga_fallida'}: ${error.message}',
      );
      _publicar(EstadoDescarga(fase: FaseDescarga.error, error: error.message));
    } catch (error) {
      _borrarPart();
      logAsistenteError('descarga abortada: $error');
      _publicar(
        EstadoDescarga(
          fase: FaseDescarga.error,
          error: 'No se pudo completar la descarga: $error',
        ),
      );
    }
  }

  Future<void> _bajar(File destino) async {
    final parcial = File(_rutaPart);
    await _descargar(
      Uri.parse(url),
      parcial,
      onProgreso: (recibidos, total) {
        _publicar(
          EstadoDescarga(
            fase: FaseDescarga.descargando,
            bytes: recibidos,
            // Sin total no hay porcentaje: la barra pasa a indeterminada
            // (la UI lo trata distinto).
            porcentaje: total == null || total <= 0
                ? null
                : ((recibidos / total) * 100).clamp(0, 100).round(),
          ),
        );
      },
    );

    if (!parcial.existsSync() || parcial.lengthSync() == 0) {
      throw const AppException(
        'La descarga no dejó ningún dato.',
        code: 'descarga_incompleta',
      );
    }
    // Renombra `.part` → `.gguf` solo si llegó entera (el renombrado es el
    // que garantiza que un `.gguf` a secas siempre está completo).
    parcial.renameSync(_rutaGguf);
  }

  Future<void> _crearEnOllama(File gguf) async {
    _publicar(
      EstadoDescarga(fase: FaseDescarga.creando, bytes: gguf.lengthSync()),
    );
    if (local) {
      // Motor local (APK): no se registra en Ollama — el motor llama.cpp
      // carga el `.gguf` directamente desde el disco.
      logAsistente('modelo local listo (sin ollama create): $_nombreFichero');
      return;
    }
    // Modelfile local: la ruta va absoluta para que `ollama create` lo
    // encuentre aunque se lance desde otro directorio.
    final modelfile = File('$directorio${Platform.pathSeparator}Modelfile');
    modelfile.writeAsStringSync(
      'FROM ${gguf.absolute.path}\n'
      // 8192 es la ventana del GGUF de Qwen2.5-1.5B: suficiente para el
      // contexto (esquema + snapshot + historia) sin quedarse corta.
      'PARAMETER num_ctx 8192\n'
      'PARAMETER temperature 0.3\n',
    );

    final resultado = await _crear(['create', modelo, '-f', modelfile.path]);
    if (resultado.codigo != 0) {
      final detalle = resultado.error.trim();
      // El mensaje que ve el usuario es corto y amable; la salida entera del
      // subproceso (stdout+stderr) solo puede vivir aquí, y es justo lo que
      // hace falta para saber por qué no se creó.
      logAsistenteError(
        'ollama create devolvió ${resultado.codigo}'
        '${resultado.codigo == 127 ? ' (binario no encontrado)' : ''}: '
        '${resumirLog(detalle)}',
      );
      // Solo el 127 (proceso no ejecutable) es «no tengo el binario»; un
      // «not found» dentro del create casi siempre es que `ollama` no
      // encuentra el `FROM` del Modelfile, y ahí lo útil es el detalle.
      final sinOllama = resultado.codigo == 127;
      throw AppException(
        sinOllama
            ? 'No encuentro el comando `ollama`. Instálalo desde ollama.com '
                  'y vuelve a intentarlo.'
            : 'Ollama no pudo crear el modelo: $detalle',
        code: sinOllama ? 'ollama_no_instalado' : 'modelo_create_fallido',
      );
    }
  }

  void _borrarPart() {
    final part = File(_rutaPart);
    if (part.existsSync()) {
      try {
        part.deleteSync();
      } catch (_) {
        // Si no se puede borrar, no es lo importante: el error real ya
        // está publicado en el estado.
      }
    }
  }

  void _publicar(EstadoDescarga nuevo) => _estado = nuevo;

  /// Reinicia el estado (lo usan los tests).
  void reiniciar() => _publicar(const EstadoDescarga());

  /// Marca el estado como `listo` sin crear nada: si el modelo ya estaba
  /// instalado, la ruta de estado no debe ofrecer la descarga.
  void marcarListo() =>
      _publicar(const EstadoDescarga(fase: FaseDescarga.listo));

  /// Implementación real de la descarga con `HttpClient`: sigue las
  /// redirecciones (HuggingFace las usa a menudo) y escribe por trozos en
  /// [destino] para no cargar el GB en memoria.
  static Future<void> descargarFichero(
    Uri uri,
    File destino, {
    required void Function(int recibidos, int? total) onProgreso,
  }) async {
    final cliente = HttpClient()..autoUncompress = false;
    try {
      final peticion = await cliente.getUrl(uri);
      // HuggingFace redirige al CDN; se sube el tope por si es larga.
      peticion.maxRedirects = 10;
      peticion.headers.set(HttpHeaders.acceptHeader, '*/*');

      final respuesta = await peticion.close();
      if (respuesta.statusCode >= 400) {
        throw AppException(
          'HuggingFace respondió ${respuesta.statusCode}. '
          'Comprueba la URL del modelo.',
          code: 'descarga_fallida',
        );
      }

      final total = respuesta.contentLength;
      final salida = destino.openSync(mode: FileMode.write);
      var recibidos = 0;
      try {
        await for (final trozo in respuesta) {
          salida.writeFromSync(trozo);
          recibidos += trozo.length;
          onProgreso(recibidos, total);
        }
      } finally {
        await salida.close();
      }

      if (total > 0 && recibidos != total) {
        throw AppException(
          'La descarga quedó incompleta ($recibidos de $total bytes).',
          code: 'descarga_incompleta',
        );
      }
    } finally {
      cliente.close(force: true);
    }
  }

  /// `ollama create <modelo> -f <modelfile>` en un subproceso.
  ///
  /// Prueba varios emplazamientos del binario ([_candidatos]) y solo da por
  /// no encontrado el 127 cuando fallan todos.
  static Future<({int codigo, String error})> ollamaCreate(
    List<String> argumentos,
  ) async {
    Object? ultimoError;
    for (final binario in _candidatos()) {
      try {
        final proceso = await Process.run(
          binario,
          argumentos,
        ).timeout(const Duration(minutes: 5));
        return (
          codigo: proceso.exitCode,
          error: '${proceso.stdout}\n${proceso.stderr}',
        );
      } on ProcessException catch (error) {
        // No está en este emplazamiento: se prueba el siguiente.
        ultimoError = error.message;
      } on TimeoutException {
        return (
          codigo: 124,
          error: 'ollama create tardó demasiado y se cortó.',
        );
      }
    }
    return (codigo: 127, error: 'No se pudo ejecutar "ollama": $ultimoError');
  }

  /// Emplazamientos del binario de Ollama, en orden de preferencia.
  ///
  /// El PATH va primero porque es lo normal, pero **no basta**: Windows no
  /// actualiza el PATH de un proceso ya arrancado, así que si Ollama se
  /// instala con la API en marcha el binario no se ve y el fallo parecería
  /// «no está instalado». Por eso se prueban también las rutas fijas.
  static List<String> _candidatos() {
    final rutas = <String>['ollama'];
    final local = Platform.environment['LOCALAPPDATA'];
    if (Platform.isWindows) {
      rutas.addAll([
        if (local != null && local.isNotEmpty)
          '$local\\Programs\\Ollama\\ollama.exe',
        'C:\\Program Files\\Ollama\\ollama.exe',
      ]);
    } else if (Platform.isMacOS) {
      rutas.addAll(const [
        '/usr/local/bin/ollama',
        '/Applications/Ollama.app/Contents/Resources/ollama',
      ]);
    } else {
      rutas.addAll(const ['/usr/local/bin/ollama', '/usr/bin/ollama']);
    }
    return rutas;
  }
}

/// Tamaño en bytes como texto legible (`1.2 GB`, `512.0 MB`…).
String bytesLegibles(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
