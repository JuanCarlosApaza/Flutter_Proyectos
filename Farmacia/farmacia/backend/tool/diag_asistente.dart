import 'dart:io';

import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/data/database/database.dart';
import 'package:farmacia_backend/src/data/services/clasificador_ia.dart';
import 'package:farmacia_backend/src/data/services/consultas/catalogo_consultas.dart';
import 'package:farmacia_backend/src/data/services/narrador.dart';
import 'package:farmacia_backend/src/data/services/ollama_service.dart';
import 'package:farmacia_backend/src/data/services/resolvedor_intencion.dart';

/// Diagnóstico rápido: ¿qué decide el resolvedor y qué dice el clasificador
/// para una pregunta concreta. Uso: dart run tool/diag_asistente.dart "pregunta"
Future<void> main(List<String> args) async {
  final pregunta = args.isNotEmpty ? args.join(' ') : 'cuanto vendi ayer?';
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

  print('P: "$pregunta"');
  final decision = await resolvedor.resolver(pregunta);
  print('resolvedor → ${decision ?? "null (pasa al clasificador)"}');

  print('\npipeline completo (3 vueltas, como la ruta HTTP):');
  for (var i = 0; i < 3; i++) {
    final dec =
        await resolvedor.resolver(pregunta) ??
        await clasificador.clasificar(pregunta);
    final String resumen;
    final String respuesta;
    if (dec is Conversacional) {
      resumen = 'conversacional';
      respuesta = dec.respuesta;
    } else if (dec is FaltaInfo) {
      resumen = 'falta_info';
      respuesta = dec.pregunta;
    } else if (dec is Ninguna) {
      resumen = 'ninguna';
      respuesta = 'No encontré una respuesta para eso.';
    } else {
      dec as Ejecutar;
      resumen = 'ejecutar ${dec.funcion} ${dec.parametros}';
      final datos = await resolvedor.ejecutar(dec);
      // ignore: avoid_print
      print('  #$i DATOS: $datos');
      respuesta = datos.startsWith('Sin ') || datos.startsWith('No ')
          ? datos
          : await narrador.redactar(pregunta: pregunta, datos: datos);
    }
    print('  #$i [$resumen]');
    print('  #$i R: $respuesta');
  }

  print('\nclasificador (3 intentos, temperatura 0.3):');
  for (var i = 0; i < 3; i++) {
    final bruto = await ollama.chat(
      contexto: clasificador.promptSistema(),
      mensajes: [(rol: 'user', contenido: pregunta)],
    );
    print('  #$i bruto: $bruto');
    print('  #$i → ${await clasificador.interpretar(bruto)}');
  }

  await db.close();
}
