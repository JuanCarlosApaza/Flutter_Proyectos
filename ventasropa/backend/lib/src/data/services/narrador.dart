import '../services/ollama_service.dart';

/// Paso final del pipeline: redacta en español el resultado que ya trae el
/// back. La IA no aporta cifras propias ni interpreta la pregunta aquí: solo
/// convierte `datos` en 1-3 frases naturales.
final class Narrador {
  Narrador({required this.ollama, required this.cargarContexto});

  /// Motor del lenguaje (Ollama en PC o llama.cpp local en la APK).
  final ModeloConversacion ollama;

  /// Contexto estático (`CHAT_CONTEXTO`), releeo en cada petición para poder
  /// editar el estilo sin reiniciar el servidor.
  final Future<String> Function() cargarContexto;

  Future<String> redactar({
    required String pregunta,
    required String datos,
    String interpretacion = '',
  }) async {
    final estatico = (await cargarContexto()).trim();
    return ollama.chat(
      contexto: _sistema(estatico, datos, pregunta, interpretacion),
      mensajes: [(rol: 'user', contenido: pregunta)],
    );
  }

  /// Monta el sistema: fichero de estilo con `{{DATOS}}` relleno. La
  /// pregunta viaja junto a los datos para que el modelo compare la una
  /// con la otra en vez de responder de memoria. Si hay interpretación
  /// («PENSO: …»), también, para narrar según lo que el usuario quería
  /// decir de verdad. Si el fichero no trae el marcador (o no existe), se
  /// añaden los datos igual.
  static String _sistema(
    String estatico,
    String datos,
    String pregunta,
    String interpretacion,
  ) {
    const marcador = '{{DATOS}}';
    final bloque = [
      'Pregunta del usuario: $pregunta',
      if (interpretacion.isNotEmpty)
        'Lo que el usuario quiere decir: $interpretacion',
      datos,
    ].join('\n\n');
    if (estatico.isEmpty) return _porDefecto(bloque);
    if (estatico.contains(marcador)) {
      return estatico.replaceFirst(marcador, bloque);
    }
    return '$estatico\n\n## DATOS\n$bloque';
  }

  static String _porDefecto(String bloque) => '''
Eres el asistente interno de una tienda. Responde en español, con frases
cortas y sin tecnicismos, SOLO con estos datos. No inventes cifras ni
nombres: si un dato no está, dilo.

## DATOS
$bloque
''';
}
