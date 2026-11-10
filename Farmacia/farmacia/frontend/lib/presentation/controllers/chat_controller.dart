import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/errors/failure.dart';

/// Mensaje de la conversación (rol `user`/`assistant`).
class MensajeChat {
  const MensajeChat({required this.esUsuario, required this.texto});

  final bool esUsuario;
  final String texto;

  /// Forma que viaja a la API.
  Map<String, Object?> toJson() => {
    'role': esUsuario ? 'user' : 'assistant',
    'content': texto,
  };
}

/// Estado del asistente leído de `GET /chat/estado`.
class EstadoChat {
  const EstadoChat({
    required this.ollamaActivo,
    required this.modeloListo,
    required this.modelo,
    this.fase = 'inactivo',
    this.porcentaje,
    this.bytes = 0,
    this.descargaError,
    this.permitido = true,
  });

  static const EstadoChat desconocido = EstadoChat(
    ollamaActivo: false,
    modeloListo: false,
    modelo: '',
  );

  /// Lee `GET /chat/estado` (`{ollamaActivo, modeloListo, modelo, descarga}`).
  factory EstadoChat.fromJson(Map<String, Object?> json) {
    final descarga = json['descarga'];
    return EstadoChat(
      ollamaActivo: json['ollamaActivo'] == true,
      modeloListo: json['modeloListo'] == true,
      modelo: json['modelo']?.toString() ?? '',
      fase: descarga is Map
          ? descarga['fase']?.toString() ?? 'inactivo'
          : 'inactivo',
      porcentaje: descarga is Map ? descarga['porcentaje'] as int? : null,
      bytes: descarga is Map ? descarga['bytes'] as int? ?? 0 : 0,
      descargaError: descarga is Map ? descarga['error'] as String? : null,
      // Si el backend no lo manda (versión vieja), se permite: el 403 del
      // envío sigue llegando como red de seguridad.
      permitido: json['permitido'] != false,
    );
  }

  final bool ollamaActivo;
  final bool modeloListo;
  final String modelo;

  /// `inactivo`/`descargando`/`creando`/`listo`/`error`.
  final String fase;
  final int? porcentaje;
  final int bytes;
  final String? descargaError;

  /// ¿Puede esta cuenta usar la IA? (ajuste `iaRoles`); `false` oculta la
  /// burbuja.
  final bool permitido;

  bool get descargando => fase == 'descargando' || fase == 'creando';
  bool get listo => ollamaActivo && modeloListo;

  EstadoChat copiarCon({
    bool? ollamaActivo,
    bool? modeloListo,
    String? modelo,
    String? fase,
    int? porcentaje,
    int? bytes,
    String? descargaError,
    bool? permitido,
  }) => EstadoChat(
    ollamaActivo: ollamaActivo ?? this.ollamaActivo,
    modeloListo: modeloListo ?? this.modeloListo,
    modelo: modelo ?? this.modelo,
    fase: fase ?? this.fase,
    porcentaje: porcentaje ?? this.porcentaje,
    bytes: bytes ?? this.bytes,
    descargaError: descargaError ?? this.descargaError,
    permitido: permitido ?? this.permitido,
  );
}

/// Controlador de la burbuja de chat.
///
/// Mantiene la conversación en memoria (se pierde al cerrar sesión: el bot
/// no guarda nada en el servidor) y traduce los códigos de error de la API
/// a mensajes que una persona de farmacia entienda sin ver `code`.
final class ChatController extends ChangeNotifier {
  ChatController(this._api);

  final ApiClient _api;

  final List<MensajeChat> mensajes = [];

  /// `true` mientras el backend genera la respuesta (sin streaming, la
  /// burbuja muestra «escribiendo…»).
  bool enviando = false;

  EstadoChat estado = EstadoChat.desconocido;

  /// Último error legible; `null` si no hay ninguno.
  String? error;

  /// La lista que ve la UI (inmutable para que los tests no cuelguen).
  List<MensajeChat> get conversacion => List.unmodifiable(mensajes);

  /// Pide el estado (Ollama + modelo + descarga). Silencioso: si falla, el
  /// estado queda en «desconocido» y ya lo contará el envío.
  Future<void> cargarEstado() async {
    try {
      final respuesta = await _api.get('/api/v1/chat/estado');
      if (respuesta is Map<String, Object?>) {
        estado = EstadoChat.fromJson(respuesta);
      } else if (respuesta is Map) {
        estado = EstadoChat.fromJson(respuesta.cast<String, Object?>());
      }
      notifyListeners();
    } on Failure {
      // Sin sesión o sin backend: la burbuja sigue siendo usable y el
      // error real aparece al enviar el primer mensaje.
    }
  }

  /// Envía [texto] y añade la respuesta del modelo a la conversación.
  Future<void> enviar(String texto) async {
    final limpio = texto.trim();
    if (limpio.isEmpty || enviando) return;

    error = null;
    mensajes.add(MensajeChat(esUsuario: true, texto: limpio));
    enviando = true;
    notifyListeners();

    try {
      final respuesta = await _api.post(
        '/api/v1/chat',
        body: {
          'mensajes': [for (final m in mensajes) m.toJson()],
        },
        // Sin streaming: el modelo local en un celular de 4 GB puede tardar
        // varios minutos (carga + clasificación + narración).
        timeout: const Duration(seconds: 300),
      );
      final devuelto = respuesta is Map ? respuesta['respuesta'] : null;
      if (devuelto is! String || devuelto.isEmpty) {
        throw const ParsingFailure();
      }
      // La IA puede devolver su interpretación («PENSO: …») separada: se
      // muestra como mensaje propio ANTES de la respuesta, para que se vea
      // qué entendió (y cómo corrigió los typos) antes de contestar.
      final piensa = respuesta is Map ? respuesta['pensamiento'] : null;
      if (piensa is String && piensa.isNotEmpty) {
        mensajes.add(MensajeChat(esUsuario: false, texto: 'Pienso: $piensa'));
      }
      mensajes.add(MensajeChat(esUsuario: false, texto: devuelto));
    } on Failure catch (fallo) {
      // El turno del usuario se queda en la lista para poder reintentar
      // desde el mismo sitio donde se escribió.
      error = _traducir(fallo);
    } finally {
      enviando = false;
      notifyListeners();
    }
  }

  /// Lanza la descarga del modelo y empieza a sondear el progreso.
  Future<void> descargarModelo() async {
    error = null;
    notifyListeners();
    try {
      await _api.post('/api/v1/chat/modelo/descargar');
      await cargarEstado();
    } on Failure catch (fallo) {
      error = _traducir(fallo);
      notifyListeners();
    }
  }

  /// Un paso del sondeo de la descarga (lo llama un temporizador de la UI).
  Future<void> sondearDescarga() async {
    if (!estado.descargando) return;
    try {
      final respuesta = await _api.get('/api/v1/chat/modelo/descarga');
      final mapa = respuesta is Map ? respuesta.cast<String, Object?>() : null;
      final descarga = mapa?['descarga'];
      if (descarga is Map) {
        estado = estado.copiarCon(
          fase: descarga['fase']?.toString() ?? 'inactivo',
          porcentaje: descarga['porcentaje'] as int?,
          bytes: descarga['bytes'] as int? ?? 0,
          descargaError: descarga['error'] as String?,
        );
        notifyListeners();
      }
    } on Failure {
      // Un sondeo que falla no debe tumbar la UI ni borrar el progreso.
    }
  }

  /// Vuelve a comprobar si el modelo ya está instalado (tras la descarga).
  Future<void> refrescarModelo() => cargarEstado();

  /// Olvida la conversación, el aviso y el estado del servidor.
  ///
  /// El controlador es de la app entera, así que sin esto lo que escribió
  /// una cuenta seguiría en pantalla cuando entrara la siguiente.
  void reiniciar() {
    mensajes.clear();
    error = null;
    estado = EstadoChat.desconocido;
    notifyListeners();
  }

  /// Borra la conversación (botón «limpiar» de la hoja).
  void limpiar() {
    mensajes.clear();
    error = null;
    notifyListeners();
  }

  /// Descarta el error visible sin tocar la conversación.
  void limpiarError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  /// Los códigos que la gente de campo puede encontrarse traducidos a una
  /// frase sin jerga (el mensaje del backend ya viene en español, pero
  /// este mapa añade la parte «qué hago ahora»).
  String _traducir(Failure fallo) {
    final codigo = fallo is ServerFailure ? fallo.code : null;
    return switch (codigo) {
      'ollama_no_disponible' =>
        'No detecto Ollama. Instálalo desde '
            'ollama.com, arráncalo («ollama serve») y vuelve a intentarlo.',
      'modelo_faltante' =>
        'Falta el modelo: descárgalo desde '
            'Ajustes › Asistente IA.',
      'ollama_no_instalado' =>
        'No encuentro el comando `ollama`. '
            'Instálalo desde ollama.com y vuelve a intentarlo.',
      'sesion_requerida' || 'unauthorized' =>
        'Tu sesión ha caducado: '
            'vuelve a entrar para usar el asistente.',
      'ia_no_permitido' =>
        'Tu rol no está habilitado para usar el asistente IA: '
            'pídele a un administrador que lo active en '
            'Ajustes › Asistente IA.',
      _ => fallo.message,
    };
  }
}
