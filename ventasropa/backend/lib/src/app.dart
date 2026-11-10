import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'core/config/app_config.dart';
import 'core/errors/app_exception.dart';
import 'data/database/database.dart';
import 'data/database/migrator.dart';
import 'data/database/sqlite_database.dart';
import 'data/repositories/ajuste_repository_impl.dart';import 'data/repositories/auditoria_repository_impl.dart';
import 'data/repositories/categoria_repository_impl.dart';
import 'data/repositories/cotizacion_repository_impl.dart';
import 'data/repositories/health_repository_impl.dart';
import 'data/repositories/persona_repository_impl.dart';
import 'data/repositories/product_repository_impl.dart';
import 'data/repositories/reporte_repository_impl.dart';
import 'data/repositories/rol_repository_impl.dart';
import 'data/repositories/sesion_repository_impl.dart';
import 'data/repositories/usuario_repository_impl.dart';
import 'data/repositories/venta_repository_impl.dart';
import 'data/security/backfill_contrasenas.dart';
import 'data/security/usuario_programador.dart';
import 'data/services/clasificador_ia.dart';
import 'data/services/consultas/catalogo_consultas.dart';
import 'data/services/descargador_modelo.dart';
import 'data/services/motor_local_llm.dart';
import 'data/services/narrador.dart';
import 'data/services/ollama_service.dart';
import 'data/services/resolvedor_intencion.dart';
import 'data/storage/almacenamiento_imagenes.dart';
import 'data/storage/almacenamiento_respaldos.dart';
import 'data/storage/programador_respaldos.dart';
import 'domain/repositories/ajuste_repository.dart';
import 'domain/repositories/auditoria_repository.dart';
import 'domain/repositories/categoria_repository.dart';
import 'domain/repositories/cotizacion_repository.dart';
import 'domain/repositories/persona_repository.dart';
import 'domain/repositories/product_repository.dart';
import 'domain/repositories/reporte_repository.dart';
import 'domain/repositories/rol_repository.dart';
import 'domain/repositories/sesion_repository.dart';
import 'domain/repositories/usuario_repository.dart';
import 'domain/repositories/venta_repository.dart';
import 'domain/rules/suscripcion.dart';
import 'domain/usecases/ajuste_usecases.dart';
import 'domain/usecases/auditoria_usecases.dart';
import 'domain/usecases/auth_usecases.dart';
import 'domain/usecases/categoria_usecases.dart';
import 'domain/usecases/cotizacion_usecases.dart';
import 'domain/usecases/get_health_status.dart';
import 'domain/usecases/persona_usecases.dart';
import 'domain/usecases/producto_usecases.dart';
import 'domain/usecases/reporte_usecases.dart';
import 'domain/usecases/respaldo_usecases.dart';
import 'domain/usecases/rol_usecases.dart';
import 'domain/usecases/usuario_usecases.dart';
import 'domain/usecases/venta_usecases.dart';
import 'presentation/docs/swagger_docs.dart';
import 'presentation/http/auditoria.dart';
import 'presentation/http/auth_middleware.dart';
import 'presentation/http/middlewares.dart';
import 'presentation/http/rate_limit.dart';
import 'presentation/routes/routes.dart';

/// Punto de composición de la API (raíz de la capa `presentation`).
///
/// Aquí se **inyectan** las dependencias siguiendo las reglas de la clean
/// architecture:
///
/// ```
/// presentation (HTTP)  ->  domain (casos de uso, entidades, contratos)
/// data (SQL, modelos)  ->  domain (implementa los contratos)
/// domain               ->  nada de fuera
/// ```
final class ApiApplication {
  ApiApplication({required this.config, required this.database});

  /// El motor lo decide `DB_ENGINE`: `sqlite` (APK embebida) o `postgres`
  /// (por defecto, escritorio/web sin ningún cambio).
  factory ApiApplication.create(AppConfig config) => ApiApplication(
    config: config,
    database: config.db.esSqlite
        ? SqliteDatabase(config.db.ruta)
        : PostgresDatabase(config.db),
  );

  final AppConfig config;
  final DatabaseConnection database;

  HttpServer? _server;

  // --- Repositorios (implementaciones de los contratos de dominio) ---

  late final ProductRepository productos = ProductRepositoryImpl(database);
  late final CategoriaRepository categorias = CategoriaRepositoryImpl(database);
  late final PersonaRepository personas = PersonaRepositoryImpl(database);
  late final UsuarioRepository usuarios = UsuarioRepositoryImpl(database);
  late final RolRepository roles = RolRepositoryImpl(database);
  late final AuditoriaRepository auditoria = AuditoriaRepositoryImpl(database);
  late final SesionRepository sesiones = SesionRepositoryImpl(database);
  late final VentaRepository ventas = VentaRepositoryImpl(database);
  late final CotizacionRepository cotizaciones = CotizacionRepositoryImpl(
    database,
  );
  late final ReporteRepository reportes = ReporteRepositoryImpl(database);
  late final AjusteRepository ajustes = AjusteRepositoryImpl(database);

  // --- Casos de uso (lazy: se construyen al primer uso) ---

  late final GetHealthStatus getHealthStatus = GetHealthStatus(
    repository: HealthRepositoryImpl(database),
    serviceName: 'ventas-api',
    version: '0.1.0',
  );

  late final Productos casosProductos = Productos(repository: productos);
  late final Categorias casosCategorias = Categorias(repository: categorias);
  late final Tallas casosTallas = Tallas(repository: categorias);
  late final Colores casosColores = Colores(repository: categorias);
  late final Marcas casosMarcas = Marcas(repository: categorias);
  late final Clientes casosClientes = Clientes(repository: personas);
  late final Proveedores casosProveedores = Proveedores(repository: personas);
  late final Empleados casosEmpleados = Empleados(repository: personas);
  late final Usuarios casosUsuarios = Usuarios(
    repository: usuarios,
    roles: roles,
  );
  late final Roles casosRoles = Roles(repository: roles);

  /// Auditoría de cambios (quién hizo qué y cuándo).
  late final Auditorias casosAuditorias = Auditorias(repository: auditoria);

  /// Login, validación de sesión y logout (middleware + rutas `auth`).
  late final Autenticar casosAuth = Autenticar(
    usuarios: usuarios,
    sesiones: sesiones,
  );

  /// Límite de intentos de login fallidos (fuerza bruta), por IP+usuario.
  late final RateLimiter rateLimiter = RateLimiter(
    maxIntentos: config.loginRateMax,
    ventana: Duration(seconds: config.loginRateWindowSeg),
  );
  late final Ordenes casosOrdenes = Ordenes(
    repository: ventas,
    productos: productos,
  );
  late final Facturas casosFacturas = Facturas(
    repository: ventas,
    ordenes: casosOrdenes,
  );

  /// Cotizaciones: propuestas de precio (sin stock ni pagos).
  late final Cotizaciones casosCotizaciones = Cotizaciones(
    repository: cotizaciones,
    productos: productos,
  );

  /// Reportes agregados (rankings de ventas del dashboard).
  late final Reportes casosReportes = Reportes(repository: reportes);

  /// Ajustes globales del sistema (vista «Ajustes» del frontend).
  late final Ajustes casosAjustes = Ajustes(repository: ajustes);

  /// Documentación OpenAPI (Swagger UI en `/docs` + `/openapi.json`).
  late final SwaggerDocs docs = SwaggerDocs.load(enabled: config.enableDocs);

  /// Almacenamiento local de imágenes (`UPLOADS_DIR`).
  late final AlmacenamientoImagenes almacenImagenes = AlmacenamientoImagenes(
    rutaDirectorio: config.uploadsDir,
  );

  /// Respaldos de la BD (`BACKUPS_DIR`): `pg_dump` en PostgreSQL y una copia
  /// `VACUUM INTO` del fichero cuando el motor es SQLite (APK).
  late final AlmacenamientoRespaldos almacenRespaldos =
      AlmacenamientoRespaldos(
        rutaDirectorio: config.backupsDir,
        db: config.db,
        ejecutable: config.pgDumpBin,
        copiarBase: config.db.esSqlite
            ? (destino) => database.executeScript(
                "VACUUM INTO '${destino.replaceAll("'", "''")}'",
              )
            : null,
      );

  /// Casos de uso de respaldos (sección «Respaldos» de la vista Ajustes).
  late final Respaldos casosRespaldos = Respaldos(
    repository: almacenRespaldos,
  );

  /// Respaldo automático: se reprograma al arrancar, al respaldar y cada vez
  /// que se guardan los ajustes (donde vive el intervalo).
  late final ProgramadorRespaldos programadorRespaldos = ProgramadorRespaldos(
    ajustes: casosAjustes,
    respaldos: casosRespaldos,
  );

  // --- Asistente IA local (Ollama / llama.cpp embebido) ------------------

  /// Motor del asistente: Ollama en la PC (`CHAT_MOTOR=ollama`, por
  /// defecto) o llama.cpp dentro del propio proceso (`CHAT_MOTOR=local`,
  /// la APK offline) — clasificador y narrador no notan el cambio.
  late final ModeloConversacion ollama = config.chatLocal
      ? MotorLocalLlm(modelo: config.chatModel, rutaModelo: _rutaModeloLocal())
      : OllamaService(url: config.ollamaUrl, modelo: config.chatModel);

  /// Ruta del GGUF: el mismo nombre de fichero que usa
  /// [DescargadorModelo] (último segmento de `CHAT_HF_URL`) en `MODELOS_DIR`.
  String _rutaModeloLocal() {
    final nombre = Uri.parse(config.chatHfUrl).pathSegments.last;
    return '${config.modelosDir}${Platform.pathSeparator}$nombre';
  }

  /// Catálogo de funciones consultables (árbol de variables del chat).
  late final CatalogoConsultas catalogoChat = catalogoConsultas();

  /// Paso 1: match por palabras clave de la pregunta con el catálogo.
  late final ResolvedorIntencion resolvedorChat = ResolvedorIntencion(
    catalogoChat,
    database,
  );

  /// Paso 2 (si no hay match): la IA elige función + parámetros (y lo que
  /// diga se valida contra la BD antes de ejecutar).
  late final ClasificadorIA clasificadorChat = ClasificadorIA(
    ollama: ollama,
    catalogo: catalogoChat,
    db: database,
  );

  /// Paso final: la IA redacta el resultado que trae el back.
  late final Narrador narradorChat = Narrador(
    ollama: ollama,
    cargarContexto: cargarContextoChat,
  );

  /// Descarga del GGUF de HuggingFace (en local se omite `ollama create`:
  /// el fichero YA es el modelo).
  late final DescargadorModelo descargadorModelo = DescargadorModelo(
    url: config.chatHfUrl,
    modelo: config.chatModel,
    directorio: config.modelosDir,
    local: config.chatLocal,
  );

  /// Contexto estático (`CHAT_CONTEXTO`): se relee en **cada** petición,
  /// así que se puede editar `contexto/asistente.md` sin reiniciar.
  ///
  /// Si el fichero no existe o no se puede leer, se devuelve vacío y la
  /// ruta monta el sistema solo con los datos vivos: un fichero ausente no
  /// debería tumbar el chat.
  Future<String> cargarContextoChat() async {
    try {
      return await File(config.chatContexto).readAsString();
    } on FileSystemException {
      return '';
    }
  }

  /// Recalcula cuándo toca el próximo respaldo automático.
  Future<void> _reprogramarRespaldos() async {
    await programadorRespaldos.reprogramar();
  }

  /// Aplica las migraciones pendientes del motor configurado.
  Future<List<String>> migrate() =>
      Migrator(database, engine: config.db.engine).migrate();

  /// Handler HTTP completo: middlewares + rutas.
  Handler get handler {
    final routes = buildRoutes(
      getHealthStatus: getHealthStatus,
      autenticar: casosAuth,
      productos: casosProductos,
      categorias: casosCategorias,
      tallas: casosTallas,
      colores: casosColores,
      marcas: casosMarcas,
      clientes: casosClientes,
      proveedores: casosProveedores,
      empleados: casosEmpleados,
      usuarios: casosUsuarios,
      roles: casosRoles,
      auditorias: casosAuditorias,
      ordenes: casosOrdenes,
      facturas: casosFacturas,
      cotizaciones: casosCotizaciones,
      reportes: casosReportes,
      ajustes: casosAjustes,
      almacenImagenes: almacenImagenes,
      respaldos: casosRespaldos,
      ollama: ollama,
      resolvedorChat: resolvedorChat,
      clasificadorChat: clasificadorChat,
      narradorChat: narradorChat,
      descargadorModelo: descargadorModelo,
      alCrearRespaldo: _reprogramarRespaldos,
      alGuardarAjustes: _reprogramarRespaldos,
      docs: docs,
      rateLimiter: rateLimiter,
    );

    return Pipeline()
        .addMiddleware(cors(origenesPermitidos: config.corsOrigins))
        .addMiddleware(requestId())
        .addMiddleware(errorHandler())
        // Corta cuerpos gigantes ANTES de leerlos (413); va dentro de
        // `errorHandler` para que la respuesta salga en JSON.
        .addMiddleware(limiteCuerpo(maxBytes: config.bodyMaxMb * 1024 * 1024))
        .addMiddleware(logRequests())
        // El más interno: valida el token justo antes de entrar en la ruta
        // y sus errores (401/403) los traduce el `errorHandler` de fuera.
        .addMiddleware(
          autenticar(
            autenticar: casosAuth,
            sinUsuarios: _sinUsuarios,
            suscripcion: _suscripcionPermitida,
          ),
        )
        // Envuelve las rutas: audita TODA mutación con la sesión ya
        // inyectada (y los rechazos incluidos). GET no se audita.
        .addHandler(auditarCambios(routes, auditorias: casosAuditorias));
  }

  /// ¿La BD no tiene **ningún** usuario? (primer arranque)
  ///
  /// En ese caso se permite `POST /api/v1/usuarios` sin sesión para poder
  /// crear la primera cuenta; en cuanto existe una, la ruta queda protegida.
  Future<bool> _sinUsuarios() async =>
      (await casosUsuarios.listar(limit: 1)).isEmpty;

  /// ¿La suscripción permite usar el sistema? (la usa el middleware en cada
  /// petición autenticada).
  ///
  /// Sin activación previa → siempre `true`. Si está activa, comprueba
  /// vencimiento y el guardián de fecha (reloj retrocedido) y, cuando el día
  /// avanza, guarda la nueva fecha vista (una escritura por día, no por
  /// petición).
  Future<bool> _suscripcionPermitida() async {
    final valores = {
      for (final ajuste in await casosAjustes.listar())
        ajuste.clave: ajuste.valor,
    };
    final ahora = DateTime.now();
    final evaluacion = comprobarSuscripcion(
      vence: valores[ajusteSuscripcionVence] ?? '',
      vista: valores[ajusteSuscripcionVista] ?? '',
      hoy: ahora,
    );
    if (evaluacion.refrescarVista) {
      await casosAjustes.guardar({
        ajusteSuscripcionVista: suscripcionFecha(ahora),
      });
    }
    return evaluacion.permitir;
  }

  /// Ejecuta las migraciones y arranca el servidor HTTP.
  ///
  /// En desarrollo, si la BD no está disponible se arranca igualmente en
  /// modo degradado (`/api/v1/health` devolverá `database: down`).
  /// En producción, un fallo de migración detiene el arranque.
  Future<HttpServer> start() async {
    try {
      final applied = await migrate();
      if (applied.isNotEmpty) {
        stdout.writeln('Migraciones aplicadas: ${applied.join(', ')}');
      }
      // Contraseñas legadas en texto plano → hash bcrypt (idempotente).
      final rehasheadas = await hashearContrasenasLegadas(database);
      if (rehasheadas > 0) {
        stdout.writeln('Contraseñas re-hasheadas: $rehasheadas');
      }
      // Cuenta permanente del programador: solo se crea si falta (una
      // instalación nueva nunca queda sin acceso de mantenimiento).
      await asegurarUsuarioProgramador(database);
    } on AppException catch (error) {
      if (config.isProduction) rethrow;
      stderr.writeln(
        'Aviso: no se pudo preparar la BD (${error.code ?? 'error'}): '
        '${error.message}. El servidor arranca en modo degradado.',
      );
    }

    final server = await shelf_io.serve(handler, config.host, config.port);
    _server = server;
    // El respaldo automático se programa DESPUÉS de servir: si la BD no
    // responde, el servidor arranca igualmente (modo degradado).
    await programadorRespaldos.iniciar();
    return server;
  }

  /// Cancela el respaldo automático, cierra el servidor y el pool de
  /// conexiones.
  Future<void> stop() async {
    programadorRespaldos.detener();
    final server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    await database.close();
  }
}
