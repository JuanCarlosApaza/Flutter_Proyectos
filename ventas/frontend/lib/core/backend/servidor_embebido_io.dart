import 'dart:io';
import 'dart:isolate';

import 'package:ventas_backend/ventas_backend.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Backend dentro de la propia app (APK offline con SQLite).
///
/// Solo arranca si el build lleva `--dart-define=SERVIDOR_EMBEBIDO=1`; sin
/// ese flag (escritorio/web de siempre) no hace nada y el sistema sigue
/// hablando con el backend externo de PostgreSQL.
///
/// El servidor corre en un **isolate** propio para no bloquear el hilo de
/// la interfaz, escucha solo en `127.0.0.1` (nadie más puede tocarlo) y
/// guarda la base en el directorio de documentos de la app — que Android
/// **no borra al actualizar** el APK, así que los datos del cliente
/// sobreviven a cada nueva versión.
abstract final class ServidorEmbebido {
  /// ¿Este build embebe el servidor? (flag de compilación: acepta `true`
  /// o `1` — `bool.fromEnvironment` solo entiende `true`, por eso se
  /// complementa con la lectura como texto).
  static const bool activo =
      bool.fromEnvironment('SERVIDOR_EMBEBIDO') ||
      String.fromEnvironment('SERVIDOR_EMBEBIDO') == '1';

  /// Arranca el backend y espera a que esté sirviendo.
  ///
  /// Devuelve `null` si todo fue bien o, si no, el mensaje de error (la app
  /// arranca igual y las llamadas API mostrarán su estado de error).
  static Future<String?> iniciar() async {
    if (!activo) return null;

    final documentos = await getApplicationDocumentsDirectory();
    final base = Directory('${documentos.path}/ventas');
    final bd = Directory('${base.path}/bd');
    final imagenes = Directory('${base.path}/imagenes');
    final respaldos = Directory('${base.path}/respaldos');
    final modelos = Directory('${base.path}/modelos');
    final contexto = File('${base.path}/contexto/asistente.md');
    for (final carpeta in [base, bd, imagenes, respaldos, modelos]) {
      await carpeta.create(recursive: true);
    }
    // Contexto del asistente IA: viaja como asset de la app y se copia a
    // documents en cada arranque (así una actualización del APK trae el
    // contexto nuevo sin borrar los datos).
    try {
      await contexto.parent.create(recursive: true);
      await contexto.writeAsString(
        await rootBundle.loadString('assets/contexto/asistente.md'),
        flush: true,
      );
    } catch (_) {
      // Sin contexto estático el chat sigue funcionando con su prompt por
      // defecto (Narrador._porDefecto).
    }

    final respuesta = ReceivePort();
    await Isolate.spawn(_arrancar, <String, Object>{
      'respuesta': respuesta.sendPort,
      'bd': '${bd.path}${Platform.pathSeparator}ventas.db',
      'imagenes': imagenes.path,
      'respaldos': respaldos.path,
      'modelos': modelos.path,
      'contexto': contexto.path,
    }, errorsAreFatal: true);
    final mensaje = await respuesta.first.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          'error: el servidor no respondió en 30 segundos '
          '(puede que el isolate haya terminado con error)',
    ) as String;
    respuesta.close();
    return mensaje == 'listo' ? null : mensaje;
  }

  /// Cuerpo del isolate: configura `AppConfig` a mano (no hay `.env` en el
  /// celular) y arranca la API con el motor SQLite.
  static Future<void> _arrancar(Map<String, Object> args) async {
    final SendPort respuesta = args['respuesta'] as SendPort;
    try {
      final config = AppConfig.load(
        environment: <String, String>{
          'APP_ENV': 'production',
          'HOST': '127.0.0.1',
          'PORT': '8080',
          'DB_ENGINE': 'sqlite',
          'DB_RUTA': args['bd'] as String,
          'UPLOADS_DIR': args['imagenes'] as String,
          'BACKUPS_DIR': args['respaldos'] as String,
          'MODELOS_DIR': args['modelos'] as String,
          // Asistente IA: llama.cpp dentro de la propia app (el GGUF se
          // descarga desde Ajustes y vive en MODELOS_DIR).
          'CHAT_MOTOR': 'local',
          'CHAT_CONTEXTO': args['contexto'] as String,
        },
      );
      final app = ApiApplication.create(config);
      await app.start();
      respuesta.send('listo');
    } catch (error) {
      respuesta.send('error: $error');
    }
  }
}
