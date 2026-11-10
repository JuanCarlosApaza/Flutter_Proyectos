import '../core/network/api_client.dart';
import '../data/datasources/auth_remote_datasource.dart';
import '../data/datasources/recurso_remote_datasource.dart';
import '../data/datasources/health_remote_datasource.dart';
import '../data/datasources/reporte_remote_datasource.dart';
import '../data/datasources/sesion_local_datasource.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/health_repository_impl.dart';
import '../data/repositories/recurso_repository_impl.dart';
import '../domain/usecases/auth_usecases.dart';
import '../domain/usecases/crud.dart';
import '../domain/usecases/get_health_status.dart';
import '../domain/usecases/reporte_usecases.dart';
import '../presentation/controllers/auth_controller.dart';
import '../presentation/controllers/carrito_controller.dart';
import '../presentation/controllers/chat_controller.dart';
import '../presentation/controllers/health_controller.dart';
import '../presentation/controllers/informe_controller.dart';
import '../presentation/controllers/recurso_controller.dart';
import '../presentation/controllers/reporte_controller.dart';
import '../presentation/controllers/respaldos_controller.dart';

/// Contenedor de dependencias (composition root).
///
/// Es el único sitio donde se "cablean" las capas:
///
/// ```
/// ApiClient -> DataSource -> Repositorio(impl) -> Caso de uso -> Controlador
/// ```
///
/// Un único caso de uso CRUD ([Crud]) alimenta los controladores de los
/// 10 recursos de la API; el controlador de salud mantiene su propio camino.
class Dependencies {
  Dependencies({ApiClient? apiClient}) : apiClient = apiClient ?? ApiClient() {
    // Sesión global (login, persistencia y cierre): primero, porque el resto
    // de peticiones viajan con el token que ella instala en el ApiClient.
    final cliente = this.apiClient;
    authController = AuthController(
      autenticacion: Autenticacion(
        repository: AuthRepositoryImpl(
          AuthRemoteDataSource(cliente),
          SesionLocalDataSource(),
          cliente,
        ),
      ),
      apiClient: cliente,
    );

    final crud = Crud(
      repository: RecursoRepositoryImpl(
        RecursoRemoteDataSource(this.apiClient),
      ),
    );

    healthController = HealthController(getHealthStatus);

    // Rankings de venta del dashboard (reportes agregados, no CRUD).
    reportesController = ReportesController(
      Reportes(repository: ReporteRemoteDataSource(cliente)),
    );

    // Pantalla «Reportes»: informes por rango de fechas (mismo caso de uso
    // que el dashboard, con otro controlador y otros filtros).
    informeController = InformeController(
      Reportes(repository: ReporteRemoteDataSource(cliente)),
    );

    productosController = ProductosController(crud);
    clientesController = ClientesController(crud);
    proveedoresController = ProveedoresController(crud);
    empleadosController = EmpleadosController(crud);
    usuariosController = UsuariosController(crud);
    rolesController = RolesController(crud);
    auditoriaController = AuditoriaController(crud);
    categoriasController = CategoriasController(crud);
    tallasController = TallasController(crud);
    coloresController = ColoresController(crud);
    marcasController = MarcasController(crud);
    variantesController = VariantesController(crud);
    ordenesController = OrdenesController(crud);
    facturasController = FacturasController(crud);
    cotizacionesController = CotizacionesController(crud);

    // Ajustes globales (vista «Ajustes»): se cargan al entrar en la sesión.
    ajustesController = AjustesController(crud);

    // Respaldos de la BD (sección de Ajustes): listado + descarga del .dump.
    respaldosController = RespaldosController(crud, cliente);

    // Carrito de compras del catálogo: estado en memoria de la sesión, sin
    // dependencias de red (la orden se genera al final del checkout).
    carritoController = CarritoController();

    // Asistente IA local (burbuja flotante): habla directamente con el
    // backend, sin pasar por el CRUD genérico.
    chatController = ChatController(cliente);
  }

  final ApiClient apiClient;

  // Casos de uso
  late final GetHealthStatus getHealthStatus = GetHealthStatus(
    repository: HealthRepositoryImpl(HealthRemoteDataSource(apiClient)),
  );

  // Controladores (estado observable de la UI)
  late final AuthController authController;
  late final HealthController healthController;
  late final ReportesController reportesController;
  late final InformeController informeController;
  late final ProductosController productosController;
  late final ClientesController clientesController;
  late final ProveedoresController proveedoresController;
  late final EmpleadosController empleadosController;
  late final UsuariosController usuariosController;
  late final RolesController rolesController;
  late final AuditoriaController auditoriaController;
  late final CategoriasController categoriasController;
  late final TallasController tallasController;
  late final ColoresController coloresController;
  late final MarcasController marcasController;
  late final VariantesController variantesController;
  late final OrdenesController ordenesController;
  late final FacturasController facturasController;
  late final CotizacionesController cotizacionesController;
  late final AjustesController ajustesController;
  late final RespaldosController respaldosController;
  late final CarritoController carritoController;
  late final ChatController chatController;

  void dispose() {
    authController.dispose();
    healthController.dispose();
    reportesController.dispose();
    informeController.dispose();
    productosController.dispose();
    clientesController.dispose();
    proveedoresController.dispose();
    empleadosController.dispose();
    usuariosController.dispose();
    rolesController.dispose();
    auditoriaController.dispose();
    categoriasController.dispose();
    tallasController.dispose();
    coloresController.dispose();
    marcasController.dispose();
    variantesController.dispose();
    ordenesController.dispose();
    facturasController.dispose();
    cotizacionesController.dispose();
    ajustesController.dispose();
    respaldosController.dispose();
    carritoController.dispose();
    chatController.dispose();
  }
}
