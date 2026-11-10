/// Stub de web: la app web nunca embebe backend (sigue contra el servidor
/// externo de PostgreSQL, como hasta ahora).
abstract final class ServidorEmbebido {
  static const bool activo = false;

  static Future<String?> iniciar() async => null;
}
