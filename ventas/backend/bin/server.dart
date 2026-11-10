import 'dart:io';

import 'package:ventas_backend/src/app.dart';
import 'package:ventas_backend/src/core/config/app_config.dart';

/// Punto de entrada del servidor.
///
/// Uso:
/// ```sh
/// cp .env.example .env   # editar credenciales
/// dart run bin/server.dart
/// ```
Future<void> main(List<String> arguments) async {
  final config = AppConfig.load(environment: Platform.environment);
  final app = ApiApplication.create(config);

  try {
    final server = await app.start();
    stdout.writeln(
      'API escuchando en http://${server.address.host}:${server.port}\n'
      '  GET /api/v1/health\n'
      '  GET /api/v1/products\n'
      '  GET /                 (índice)\n'
      '${app.docs.available ? '  GET /docs               (Swagger UI)\n  GET /openapi.json        (especificación OpenAPI)\n' : '  /docs deshabilitado (falta doc/openapi.json o DOCS_ENABLED=false)\n'}',
    );
  } on Exception catch (error) {
    stderr.writeln('No se pudo arrancar la API: $error');
    await app.stop();
    exitCode = 1;
    return;
  }

  // Apagado ordenado con Ctrl+C.
  var shuttingDown = false;
  ProcessSignal.sigint.watch().listen((_) async {
    if (shuttingDown) return;
    shuttingDown = true;
    stdout.writeln('\nCerrando servidor...');
    await app.stop();
    exit(0);
  });
}
