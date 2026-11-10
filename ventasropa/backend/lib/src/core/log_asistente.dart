import 'dart:io';

/// Se apaga en los tests.
///
/// El diagnóstico está pensado para el servidor en marcha; dentro de
/// `dart test` solo rompería la línea del reporter sin añadir nada. Las
/// pruebas lo desactivan al principio de `main`.
bool logAsistenteActivo = true;

/// Diagnóstico del asistente IA en la consola del servidor.
///
/// Sigue el mismo formato que el log de peticiones de shelf
/// (`2026-10-03T00:41:02.123456 ...`, con `[ERROR] ` al principio en los
/// fallos), así todo lo del asistente queda en el mismo stream y en el mismo
/// estilo que `GET /api/v1/chat/estado [503]`, y se puede leer en orden.
///
/// No hay un logger estructurado en este proyecto: el resto de módulos
/// escribe con `stdout`/`stderr`, así que se sigue esa costumbre. La
/// diferencia es que aquí **se escribe siempre en `stdout`** incluso en los
/// errores, para no partir el log en dos ficheros y perder el contexto.
void logAsistente(String mensaje) {
  if (!logAsistenteActivo) return;
  stdout.writeln('${DateTime.now().toIso8601String()} asistente: $mensaje');
}

/// Igual que [logAsistente] marcado como fallo. El motivo de un error de
/// Ollama no llega a ningún otro sitio: `errorHandler` convierte la
/// excepción en la respuesta antes de que `logRequests` la vea, así que la
/// causa solo existe aquí.
void logAsistenteError(String mensaje) {
  if (!logAsistenteActivo) return;
  stdout.writeln(
    '[ERROR] ${DateTime.now().toIso8601String()} asistente: $mensaje',
  );
}

/// Primeras [limite] letras de [texto] en una sola línea.
///
/// Para resumir la salida cruda de un subproceso o la respuesta de Ollama
/// sin llenar el log de saltos de línea; devuelve `(sin salida)` si no hay
/// nada que contar.
String resumirLog(String texto, {int limite = 200}) {
  final limpio = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (limpio.isEmpty) return '(sin salida)';
  return limpio.length <= limite ? limpio : '${limpio.substring(0, limite)}…';
}
