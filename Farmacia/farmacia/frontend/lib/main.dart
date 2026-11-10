import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/backend/servidor_embebido.dart';
import 'core/backend/startup_error_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // APK offline (SERVIDOR_EMBEBIDO=1 o =true): arranca el backend con
  // SQLite en su propio isolate antes de la UI. En web/escritorio es un
  // no-op.
  final errorServidor = await ServidorEmbebido.iniciar();

  final dependencies = Dependencies();

  if (errorServidor != null) {
    // El servidor embebido no arrancó: se muestra el motivo en pantalla
    // (en release no hay consola) en vez de dejar la app "sin conexión"
    // sin pista de qué falló.
    runApp(StartupErrorApp(motivo: errorServidor));
    return;
  }

  runApp(FarmaciaApp(dependencies: dependencies));
}
