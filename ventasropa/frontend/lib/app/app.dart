import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/network/api_client.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/ajustes_scope.dart';
import '../core/widgets/chat_flotante.dart';
import '../core/widgets/sesion_scope.dart';
import '../presentation/controllers/auth_controller.dart';
import '../presentation/controllers/carrito_controller.dart';
import '../presentation/controllers/chat_controller.dart';
import '../presentation/controllers/health_controller.dart';
import '../presentation/controllers/informe_controller.dart';
import '../presentation/controllers/load_state.dart';
import '../presentation/controllers/recurso_controller.dart';
import '../presentation/controllers/reporte_controller.dart';
import '../presentation/controllers/respaldos_controller.dart';
import '../presentation/pages/login_page.dart';
import '../presentation/pages/main_screen.dart';
import '../presentation/widgets/suscripcion_bloqueada.dart';
import 'dependencies.dart';

/// Raíz de la UI: tema + inyección de dependencias.
class VentasApp extends StatelessWidget {
  const VentasApp({super.key, required this.dependencies});

  final Dependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // El único cliente con el token de sesión instalado: cualquier
        // widget que hable con la API directamente (p. ej. el subidor de
        // imágenes) debe usar ESTE, no crear uno nuevo, o la petición
        // saldría sin `Authorization` y la API respondería 401.
        Provider<ApiClient>.value(value: dependencies.apiClient),
        ChangeNotifierProvider<AuthController>.value(
          value: dependencies.authController,
        ),
        ChangeNotifierProvider<HealthController>.value(
          value: dependencies.healthController,
        ),
        ChangeNotifierProvider<ReportesController>.value(
          value: dependencies.reportesController,
        ),
        ChangeNotifierProvider<InformeController>.value(
          value: dependencies.informeController,
        ),
        ChangeNotifierProvider<ProductosController>.value(
          value: dependencies.productosController,
        ),
        ChangeNotifierProvider<ClientesController>.value(
          value: dependencies.clientesController,
        ),
        ChangeNotifierProvider<ProveedoresController>.value(
          value: dependencies.proveedoresController,
        ),
        ChangeNotifierProvider<EmpleadosController>.value(
          value: dependencies.empleadosController,
        ),
        ChangeNotifierProvider<UsuariosController>.value(
          value: dependencies.usuariosController,
        ),
        ChangeNotifierProvider<RolesController>.value(
          value: dependencies.rolesController,
        ),
        ChangeNotifierProvider<AuditoriaController>.value(
          value: dependencies.auditoriaController,
        ),
        ChangeNotifierProvider<CategoriasController>.value(
          value: dependencies.categoriasController,
        ),
        ChangeNotifierProvider<TallasController>.value(
          value: dependencies.tallasController,
        ),
        ChangeNotifierProvider<ColoresController>.value(
          value: dependencies.coloresController,
        ),
        ChangeNotifierProvider<MarcasController>.value(
          value: dependencies.marcasController,
        ),
        ChangeNotifierProvider<VariantesController>.value(
          value: dependencies.variantesController,
        ),
        ChangeNotifierProvider<OrdenesController>.value(
          value: dependencies.ordenesController,
        ),
        ChangeNotifierProvider<FacturasController>.value(
          value: dependencies.facturasController,
        ),
        ChangeNotifierProvider<CotizacionesController>.value(
          value: dependencies.cotizacionesController,
        ),
        ChangeNotifierProvider<CarritoController>.value(
          value: dependencies.carritoController,
        ),
        ChangeNotifierProvider<AjustesController>.value(
          value: dependencies.ajustesController,
        ),
        ChangeNotifierProvider<RespaldosController>.value(
          value: dependencies.respaldosController,
        ),
        ChangeNotifierProvider<ChatController>.value(
          value: dependencies.chatController,
        ),
      ],
      child: _AjustesRaiz(
        controlador: dependencies.ajustesController,
        child: MaterialApp(
          title: 'Ventas',
          debugShowCheckedModeBanner: false,
          // La app es solo en español: con las localizaciones de Flutter,
          // el calendario de fechas y el resto de widgets nativos de
          // Material salen en español (antes salían en inglés).
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: AppColors.pageBg,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.brandGreen,
              primary: AppColors.brandGreen,
            ),
          ),
          home: const _RaizDeSesion(),
          // La burbuja del asistente vive en el `builder`, es decir, por
          // encima del `Navigator`: aparece en todas las pantallas sin que
          // cada pantalla tenga que montarla. Solo dentro de sesión, y si
          // no la han ocultado desde Ajustes (en celular ocupa pantalla).
          builder: (context, child) => ChatFlotante(
            autenticado:
                context.watch<AuthController>().estado ==
                AuthEstado.autenticado,
            visible: AjustesScope.de(context).valor(Ajustes.burbujaIA) != '0',
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Publica los ajustes cargados **por encima de `MaterialApp`**.
///
/// Las hojas modales (carrito, «Nueva Orden», los propios desplegables) se
/// montan en el `Navigator` y quedan fuera del `SesionScope` —que envuelve a
/// `MainScreen` dentro de `home:`—, así que el scope tiene que vivir aquí,
/// en la raíz, para que todas las pantallas los vean.
///
/// Fuera de la app real (pantallas aisladas en tests) no hay scope y cada
/// consumidor cae en los valores de fábrica.
class _AjustesRaiz extends StatelessWidget {
  const _AjustesRaiz({required this.controlador, required this.child});

  final AjustesController controlador;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controlador,
    builder: (context, _) =>
        AjustesScope(valores: controlador.valores, child: child),
  );
}

/// Elige la pantalla según el estado de la sesión: splash de arranque,
/// login o dashboard. Es el "guard" de rutas equivalente a un `PrivateRoute`.
class _RaizDeSesion extends StatefulWidget {
  const _RaizDeSesion();

  @override
  State<_RaizDeSesion> createState() => _RaizDeSesionState();
}

class _RaizDeSesionState extends State<_RaizDeSesion> {
  /// Evita repetir el `GET /chat/estado` en cada reconstrucción.
  bool _chatEstadoCargado = false;

  @override
  void initState() {
    super.initState();
    // Restaura la sesión guardada tras el primer frame (así se pinta antes
    // el splash y no hay pantalla en blanco mientras se lee el disco).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthController>().restaurar();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final ajustes = context.watch<AjustesController>();

    // Al entrar en la sesión se piden los ajustes (un único GET) antes de
    // montar la UI: así la página inicial y los valores por defecto de los
    // formularios no arrancan con los de fábrica y luego saltan.
    if (auth.estado == AuthEstado.autenticado &&
        ajustes.state == LoadState.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AjustesController>().cargar();
      });
    }

    // Al entrar se pregunta si Ollama y el modelo están listos: la burbuja
    // pinta el estado en la hoja y Ajustes el botón de descarga.
    if (auth.estado == AuthEstado.autenticado && !_chatEstadoCargado) {
      _chatEstadoCargado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatController>().cargarEstado();
      });
    }
    // Al salir se olvidan: si cambia la cuenta que entra, no debe leer lo
    // que escribió la anterior (el chat vive en memoria, no en el servidor).
    if (auth.estado == AuthEstado.sinSesion && _chatEstadoCargado) {
      _chatEstadoCargado = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatController>().reiniciar();
      });
    }

    // Al salir se olvidan: si cambia la cuenta que entra, vuelve a pedirlos.
    if (auth.estado == AuthEstado.sinSesion &&
        ajustes.state != LoadState.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AjustesController>().reiniciar();
        context.read<RespaldosController>().reiniciar();
      });
    }

    // Un fallo al leerlos no bloquea la app: se sigue con los de fábrica.
    final ajustesListos =
        ajustes.state == LoadState.loaded || ajustes.state == LoadState.error;

    // Bloqueo por suscripción (por encima de todo: ni login ni sesión se
    // muestran hasta que se reactive con la clave).
    if (auth.suscripcionVencida) return const SuscripcionBloqueada();

    return switch (auth.estado) {
      AuthEstado.inicial || AuthEstado.cargando => const _SplashSesion(),
      AuthEstado.sinSesion => const LoginPage(),
      AuthEstado.autenticado =>
        ajustesListos
            ? SesionScope(
                datos: DatosSesion(
                  usuario: auth.usuario!,
                  cerrarSesion: auth.cerrarSesion,
                ),
                child: const MainScreen(),
              )
            : const _SplashSesion(),
    };
  }
}

/// Pantalla de transición mientras se comprueba si hay sesión guardada.
class _SplashSesion extends StatelessWidget {
  const _SplashSesion();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_pharmacy_rounded,
              size: 48,
              color: AppColors.brandGreen,
            ),
            SizedBox(height: 18),
            CircularProgressIndicator(color: AppColors.brandGreen),
          ],
        ),
      ),
    );
  }
}
