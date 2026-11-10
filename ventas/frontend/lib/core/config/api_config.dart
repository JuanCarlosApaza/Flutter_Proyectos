import 'package:flutter/foundation.dart';

/// Configuración de conexión con el backend.
///
/// El valor puede cambiarse en tiempo de compilación sin tocar código:
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8080
/// ```
///
/// Sin `--dart-define` la URL se resuelve sola en tiempo de ejecución:
///
/// * **Web**: usa el mismo host que sirve la página (`Uri.base.host`). En la
///   PC eso es `localhost`; si el celular abre la web por la IP de la PC
///   (p. ej. escaneando el QR de acceso), la API se llama en esa misma IP.
///   Así ninguna de las dos plataformas necesita `--dart-define`.
/// * **Móvil/emulador**: `localhost` (solo sirve en emulador; para un
///   dispositivo físico pasa `API_BASE_URL`).
abstract final class ApiConfig {
  /// URL explícita del backend; vacía si no se pasó `--dart-define`.
  static const String _definida = String.fromEnvironment('API_BASE_URL');

  /// Puerto del backend; se usa para derivar la URL en web.
  static const String puerto = String.fromEnvironment(
    'API_PORT',
    defaultValue: '8080',
  );

  /// URL base efectiva (sin barra final) contra la que se llaman las rutas.
  static String get baseUrl {
    if (_definida.isNotEmpty) return _definida;
    if (kIsWeb) return '${Uri.base.scheme}://${Uri.base.host}:$puerto';
    return 'http://localhost:$puerto';
  }

  static const Duration connectTimeout = Duration(seconds: 8);
}
