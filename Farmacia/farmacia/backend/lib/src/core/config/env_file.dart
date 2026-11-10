import 'dart:io';

/// Carga pares `clave=valor` desde un archivo `.env` (si existe).
///
/// Es una implementación mínima a propósito: evita dependencias externas y
/// basta para lo que necesita la app. Las variables ya presentes en el
/// entorno del proceso tienen prioridad sobre el archivo.
final class EnvFile {
  EnvFile._();

  static Map<String, String> load([String path = '.env']) {
    final file = File(path);
    if (!file.existsSync()) return const <String, String>{};

    final result = <String, String>{};
    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final index = line.indexOf('=');
      if (index <= 0) continue;

      final key = line.substring(0, index).trim();
      var value = line.substring(index + 1).trim();

      // Quita comillas envolventes.
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }
}
