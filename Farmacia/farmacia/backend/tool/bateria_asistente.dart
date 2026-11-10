import 'dart:io';

import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/data/database/database.dart';
import 'package:farmacia_backend/src/data/services/clasificador_ia.dart';
import 'package:farmacia_backend/src/data/services/consultas/catalogo_consultas.dart';
import 'package:farmacia_backend/src/data/services/narrador.dart';
import 'package:farmacia_backend/src/data/services/ollama_service.dart';
import 'package:farmacia_backend/src/data/services/resolvedor_intencion.dart';
import 'package:farmacia_backend/src/presentation/routes/chat_routes.dart';

/// Batería de preguntas con verificación automática de enrutado.
///
/// Cada línea del fichero es `esperada|pregunta` (esperada = nombre de la
/// función, `conversacional`, `falta_info` o `ninguna`). Imprime [OK]/[FALLO]
/// con la respuesta y un resumen final.
///
/// Uso: `dart run tool/bateria_asistente.dart fichero.txt`
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/bateria_asistente.dart <fichero>');
    exit(2);
  }
  final lineas = await File(args.first).readAsLines();

  final config = AppConfig.load();
  final db = PostgresDatabase(config.db);
  final ollama = OllamaService(url: config.ollamaUrl, modelo: config.chatModel);
  final catalogo = catalogoConsultas();
  final resolvedor = ResolvedorIntencion(catalogo, db);
  final clasificador = ClasificadorIA(
    ollama: ollama,
    catalogo: catalogo,
    db: db,
  );
  final narrador = Narrador(
    ollama: ollama,
    cargarContexto: () => File(config.chatContexto).readAsString(),
  );

  var ok = 0;
  var fallos = 0;
  String? preguntaPrevia;
  for (final linea in lineas) {
    final recortada = linea.trim();
    if (recortada.isEmpty || recortada.startsWith('#')) continue;
    final partes = recortada.split('|');
    if (partes.length < 2) continue;
    final esperada = partes.first.trim();
    final pregunta = partes.sublist(1).join('|').trim();

    // Historial SOLO para anáforas («y del mes pasado») y correcciones
    // («no, el que tengo mas»): con historial demás el modelo se despista.
    final norm = ResolvedorIntencion.normalizar(pregunta);
    final necesitaHistorial =
        norm.startsWith(RegExp(r'^[ye]\s')) ||
        RegExp(
          r'\b(no cual|no el|no la|digo|me refiero|en vez de|'
          r'mas bien|repito|otra cosa)\b',
        ).hasMatch(norm);
    final historial = <({String rol, String contenido})>[
      if (necesitaHistorial && preguntaPrevia != null)
        (rol: 'user', contenido: preguntaPrevia),
    ];
    // Mismo pipeline que la ruta: palabras clave → clasificador con PENSO
    // → reintento del resolvedor con la frase corregida por el modelo.
    Decision decision;
    final resuelto = await resolvedor.resolver(pregunta);
    if (resuelto != null) {
      decision = resuelto;
    } else {
      final r = await clasificador.clasificarConPensamiento(
        pregunta,
        historial: historial,
      );
      decision = r.decision;
      if ((decision is FaltaInfo || decision is Ninguna) &&
          r.pensamiento.isNotEmpty) {
        final corregido = await resolvedor.resolver(r.pensamiento);
        if (corregido is Ejecutar) decision = corregido;
      }
    }

    final String obtenida;
    final String respuesta;
    if (decision is Conversacional) {
      obtenida = 'conversacional';
      respuesta = decision.respuesta;
    } else if (decision is FaltaInfo) {
      obtenida = 'falta_info';
      respuesta = decision.pregunta;
    } else if (decision is Ninguna) {
      obtenida = 'ninguna';
      respuesta = 'No encontré una respuesta para eso.';
    } else {
      decision as Ejecutar;
      obtenida = decision.funcion;
      respuesta = await ejecutarYRedactar(
        decision,
        pregunta: pregunta,
        resolvedor: resolvedor,
        narrador: narrador,
      );
    }

    final coincide = obtenida == esperada;
    if (coincide) {
      ok++;
    } else {
      fallos++;
    }
    // ignore: avoid_print
    print(
      '${coincide ? "[OK]   " : "[FALLO]"} ($esperada → $obtenida) '
      '«$pregunta»',
    );
    // ignore: avoid_print
    print('       R: ${respuesta.replaceAll('\n', ' / ')}');
    preguntaPrevia = pregunta;
  }

  // ignore: avoid_print
  print('\nTOTAL: $ok OK, $fallos FALLO de ${ok + fallos}');
  await db.close();
  if (fallos > 0) exit(1);
}
