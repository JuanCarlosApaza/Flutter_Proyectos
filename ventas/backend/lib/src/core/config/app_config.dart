import 'env_file.dart';

/// Configuración inmutable de la aplicación.
///
/// La única fuente de verdad de la configuración: el resto del código
/// recibe una instancia por inyección, nunca lee `Platform.environment`.
final class AppConfig {
  const AppConfig({
    required this.host,
    required this.port,
    required this.appEnv,
    required this.enableDocs,
    required this.uploadsDir,
    required this.backupsDir,
    required this.pgDumpBin,
    required this.db,
    this.corsOrigins = const ['*'],
    this.loginRateMax = 10,
    this.loginRateWindowSeg = 300,
    this.bodyMaxMb = 5,
    this.ollamaUrl = 'http://localhost:11434',
    this.chatModel = 'ventas-qwen2.5-1.5b',
    this.chatMotor = 'ollama',
    this.modelosDir = 'models',
    this.chatHfUrl = defaultChatHfUrl,
    this.chatContexto = 'contexto/asistente.md',
  });

  factory AppConfig.load({Map<String, String> environment = const {}}) {
    // Las variables del proceso ganan sobre el archivo .env
    final fileEnv = EnvFile.load();
    String read(String key, String fallback) =>
        environment[key] ?? fileEnv[key] ?? fallback;

    final appEnv = AppEnv.values.firstWhere(
      (e) => e.name == read('APP_ENV', 'development'),
      orElse: () => AppEnv.development,
    );

    return AppConfig(
      host: read('HOST', '0.0.0.0'),
      port: int.tryParse(read('PORT', '8080')) ?? 8080,
      appEnv: appEnv,
      // La documentación se desactiva en producción salvo que se pida.
      enableDocs: switch (read('DOCS_ENABLED', '')) {
        '' => appEnv != AppEnv.production,
        final value => value == 'true',
      },
      uploadsDir: read('UPLOADS_DIR', 'uploads'),
      backupsDir: read('BACKUPS_DIR', 'backups'),
      pgDumpBin: read('PG_DUMP_BIN', 'pg_dump'),
      // Orígenes con acceso CORS: `*` (cualquiera) o lista explícita
      // separada por comas, p. ej. `http://localhost:8081,http://192.168.1.50:8081`.
      corsOrigins: switch (read('CORS_ORIGINS', '')) {
        '' => const ['*'],
        final value => [
          for (final o in value.split(',')) o.trim(),
        ].where((o) => o.isNotEmpty).toList(),
      },
      // Fuerza bruta en el login: intentos fallidos por IP+usuario.
      loginRateMax: int.tryParse(read('LOGIN_RATE_MAX', '')) ?? 10,
      loginRateWindowSeg: int.tryParse(read('LOGIN_RATE_WINDOW', '')) ?? 300,
      // Tamaño máximo de cualquier cuerpo HTTP (imágenes en base64 incluidas).
      bodyMaxMb: int.tryParse(read('BODY_MAX_MB', '')) ?? 5,
      // Asistente IA local: servidor Ollama, modelo creado a partir del GGUF
      // de HuggingFace y carpeta donde viven los `.gguf`.
      ollamaUrl: read('OLLAMA_URL', 'http://localhost:11434'),
      chatModel: read('CHAT_MODEL', 'ventas-qwen2.5-1.5b'),
      chatMotor: read('CHAT_MOTOR', 'ollama'),
      modelosDir: read('MODELOS_DIR', 'models'),
      chatHfUrl: read('CHAT_HF_URL', defaultChatHfUrl),
      chatContexto: read('CHAT_CONTEXTO', 'contexto/asistente.md'),
      db: DbConfig(
        engine: read('DB_ENGINE', 'postgres'),
        ruta: read('DB_RUTA', ''),
        host: read('DB_HOST', 'localhost'),
        port: int.tryParse(read('DB_PORT', '5432')) ?? 5432,
        name: read('DB_NAME', 'ventas'),
        user: read('DB_USER', 'postgres'),
        password: read('DB_PASSWORD', 'postgres'),
        sslMode: read('DB_SSL_MODE', 'disable'),
        poolMax: int.tryParse(read('DB_POOL_MAX', '10')) ?? 10,
      ),
    );
  }

  final String host;
  final int port;
  final AppEnv appEnv;

  /// ¿Se sirve Swagger UI en `/docs`?
  final bool enableDocs;

  /// Directorio local de imágenes subidas (`UPLOADS_DIR`).
  ///
  /// Si es relativo se resuelve contra el directorio de trabajo (lanzar el
  /// servidor desde `backend/` deja los ficheros en `backend/uploads/`).
  final String uploadsDir;

  /// Directorio donde `pg_dump` escribe los respaldos (`BACKUPS_DIR`).
  ///
  /// Mismo criterio que [uploadsDir]: relativo al CWD, así que lanzando el
  /// servidor desde `backend/` acaban en `backend/backups/`.
  final String backupsDir;

  /// Ejecutable de `pg_dump` (`PG_DUMP_BIN`): por defecto está en el PATH;
  /// si no lo está, hay que apuntar a la ruta completa del `.exe`.
  final String pgDumpBin;

  /// Orígenes permitidos por CORS (`CORS_ORIGINS`): `['*']` en desarrollo;
  /// en producción, la URL exacta del frontend servido.
  final List<String> corsOrigins;

  /// Intentos de login fallidos tolerados por IP+usuario (`LOGIN_RATE_MAX`).
  final int loginRateMax;

  /// Ventana del rate-limit de login en segundos (`LOGIN_RATE_WINDOW`).
  final int loginRateWindowSeg;

  /// Tamaño máximo de cualquier cuerpo HTTP en MB (`BODY_MAX_MB`).
  final int bodyMaxMb;

  /// URL del servidor Ollama (`OLLAMA_URL`).
  final String ollamaUrl;

  /// Nombre del modelo creado en Ollama (`CHAT_MODEL`).
  final String chatModel;

  /// Motor del asistente IA: `ollama` (servidor en la PC, por defecto) o
  /// `local` (llama.cpp embebido, para la APK offline).
  final String chatMotor;

  /// ¿El chat usa el motor local embebido?
  bool get chatLocal => chatMotor == 'local';

  /// Carpeta donde se guardan los `.gguf` descargados (`MODELOS_DIR`),
  /// relativa al directorio de trabajo (desde `backend/` → `backend/models/`).
  final String modelosDir;

  /// URL de descarga del GGUF del chat (`CHAT_HF_URL`).
  final String chatHfUrl;

  /// Fichero de contexto estático del asistente (`CHAT_CONTEXTO`): esquema,
  /// reglas y ejemplos que se leen en **cada** petición, así que se puede
  /// editar sin reiniciar ni recompilar.
  final String chatContexto;

  final DbConfig db;

  bool get isProduction => appEnv == AppEnv.production;

  @override
  String toString() =>
      'AppConfig(host: $host, port: $port, env: ${appEnv.name}, db: ${db.host}:${db.port}/${db.name})';
}

/// Descarga por defecto del modelo del asistente: Qwen2.5-1.5B-Instruct
/// cuantizado a q4_k_m (~1 GB), el más equilibrado de los que caben en
/// una máquina sin GPU.
const String defaultChatHfUrl =
    'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/'
    'resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf';

enum AppEnv { development, production }

final class DbConfig {
  const DbConfig({
    required this.host,
    required this.port,
    required this.name,
    required this.user,
    required this.password,
    required this.sslMode,
    required this.poolMax,
    this.engine = 'postgres',
    this.ruta = '',
  });

  /// Motor de base de datos: `postgres` (por defecto) o `sqlite`.
  ///
  /// Con `sqlite`, [host]/[port]/[name]/[user]/[password] no se usan y el
  /// fichero vive en [ruta]. Los builds de escritorio/web no lo cambian.
  final String engine;

  /// Ruta del fichero `.db` cuando [engine] es `sqlite`.
  final String ruta;

  final String host;
  final int port;
  final String name;
  final String user;
  final String password;
  final String sslMode;
  final int poolMax;

  bool get esSqlite => engine == 'sqlite';
}
