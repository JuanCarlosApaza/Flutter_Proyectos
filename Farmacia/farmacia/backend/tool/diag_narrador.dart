import 'dart:io';

import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/data/services/narrador.dart';
import 'package:farmacia_backend/src/data/services/ollama_service.dart';

/// Martilla al narrador con los mismos datos para cazar alucinaciones.
/// Uso: dart run tool/diag_narrador.dart
Future<void> main() async {
  final config = AppConfig.load();
  final ollama = OllamaService(url: config.ollamaUrl, modelo: config.chatModel);
  final narrador = Narrador(
    ollama: ollama,
    cargarContexto: () => File(config.chatContexto).readAsString(),
  );

  const pregunta = 'cuanto vendi ayer?';
  const datos = 'Ayer: 0 órdenes por \$0.00 '
      '(Antes de ayer: 0 órdenes por \$0.00, sin cambio)';

  for (var i = 0; i < 8; i++) {
    final texto = await narrador.redactar(pregunta: pregunta, datos: datos);
    // ignore: avoid_print
    print('#$i → $texto');
  }
}
