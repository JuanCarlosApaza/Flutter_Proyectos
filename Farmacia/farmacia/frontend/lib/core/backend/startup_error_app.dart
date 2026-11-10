import 'package:flutter/material.dart';

/// Pantalla de error de arranque del servidor embebido (APK offline).
///
/// En release no hay consola, así que si el backend local no levantó, el
/// motivo se muestra aquí en pantalla en vez de dejar la app "sin conexión"
/// sin ninguna pista.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.motivo});

  /// Mensaje devuelto por el intento de arranque (o timeout).
  final String motivo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFB3261E),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo iniciar el servidor local',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  motivo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Cierra la app y vuelve a abrirla. Si persiste, '
                  'informa este mensaje.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
