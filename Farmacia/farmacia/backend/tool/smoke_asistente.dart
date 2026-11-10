import 'dart:io';

import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/data/database/database.dart';
import 'package:farmacia_backend/src/data/services/clasificador_ia.dart';
import 'package:farmacia_backend/src/data/services/consultas/catalogo_consultas.dart';
import 'package:farmacia_backend/src/data/services/narrador.dart';
import 'package:farmacia_backend/src/data/services/ollama_service.dart';
import 'package:farmacia_backend/src/data/services/resolvedor_intencion.dart';
import 'package:farmacia_backend/src/presentation/routes/chat_routes.dart';

/// Prueba de humo del asistente contra la BD y Ollama **reales**, sin pasar
/// por HTTP ni por la sesión: `dart run tool/smoke_asistente.dart`.
///
/// Con argumentos usa esas preguntas; sin ellos, la lista de siempre.
/// Recorre el pipeline completo (palabras clave → clasificador → SQL →
/// narrador) e imprime la decisión y la respuesta.
Future<void> main(List<String> argumentos) async {
  final config = AppConfig.load();
  final db = PostgresDatabase(config.db);
  final ollama = OllamaService(url: config.ollamaUrl, modelo: config.chatModel);
  final catalogo = catalogoConsultas();
  final resolvedor = ResolvedorIntencion(catalogo, db);
  final clasificador = ClasificadorIA(ollama: ollama, catalogo: catalogo);
  final narrador = Narrador(
    ollama: ollama,
    cargarContexto: () => File(config.chatContexto).readAsString(),
  );

  const preguntasPorDefecto = [
    'Hola',
    '¿cuántos medicamentos tengo?',
    '¿cuál es el medicamento con más stock?',
    '¿qué vendí ayer?',
    '¿qué está por vencer?',
    '¿cuánto tengo de ibuprofeno?',
    '¿cuántos clientes tengo?',
    '¿qué vendiste más el mes pasado?',
    '¿cómo me ha ido este año?',
    '¿qué tiempo hará mañana?',
    '¿cuánto tengo de eso?',
  ];

  // Cada argumento (entre comillas) es una pregunta.
  final preguntas = argumentos.isEmpty ? preguntasPorDefecto : argumentos;

  for (final pregunta in preguntas) {
    final reloj = Stopwatch()..start();
    final decision =
        await resolvedor.resolver(pregunta) ??
        await clasificador.clasificar(pregunta);

    final String resumen;
    final String respuesta;
    if (decision is Conversacional) {
      resumen = 'conversacional (back, sin IA)';
      respuesta = decision.respuesta;
    } else if (decision is FaltaInfo) {
      resumen = 'falta_info (back, sin IA)';
      respuesta = decision.pregunta;
    } else if (decision is Ninguna) {
      resumen = 'ninguna (back, sin IA)';
      respuesta = 'No encontré una respuesta para eso.';
    } else {
      decision as Ejecutar;
      resumen = 'ejecutar ${decision.funcion} ${decision.parametros}';
      // Mismo código que la ruta HTTP: incluye normalizaProsa.
      respuesta = await ejecutarYRedactar(
        decision,
        pregunta: pregunta,
        resolvedor: resolvedor,
        narrador: narrador,
      );
    }
    reloj.stop();
    // ignore: avoid_print
    print('\nP: $pregunta');
    // ignore: avoid_print
    print('  [$resumen · ${reloj.elapsedMilliseconds} ms]');
    // ignore: avoid_print
    print('  R: $respuesta');
  }

  await db.close();
}
