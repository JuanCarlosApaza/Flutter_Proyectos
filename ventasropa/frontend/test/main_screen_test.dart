import 'package:ventas/core/theme/app_colors.dart';
import 'package:ventas/core/widgets/sesion_scope.dart';
import 'package:ventas/core/widgets/sidebar.dart';
import 'package:ventas/domain/entities/health_status.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/entities/reporte.dart';
import 'package:ventas/domain/entities/usuario.dart';
import 'package:ventas/domain/repositories/health_repository.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/repositories/reporte_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/domain/usecases/get_health_status.dart';
import 'package:ventas/domain/usecases/reporte_usecases.dart';
import 'package:ventas/presentation/controllers/carrito_controller.dart';
import 'package:ventas/presentation/controllers/health_controller.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/controllers/reporte_controller.dart';
import 'package:ventas/presentation/pages/catalogo_page.dart';
import 'package:ventas/presentation/pages/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Listados vacíos: las páginas se pintan sin datos y sin tocar la red.
class _RepositorioVacio implements RecursoRepository {
  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    const fuente = <Recurso>[];
    return ListadoRecurso(
      total: fuente.length,
      items: fuente.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

/// Vacío, salvo los empleados: hacen falta para que el desplegable de
/// vendedor de «Nueva Orden» tenga opciones (y pueda salir la de la sesión).
class _RepositorioConEmpleados extends _RepositorioVacio {
  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    if (recurso == 'empleados') {
      final fuente = [
        // Solo los cuyo rol permite crear ventas entran en el desplegable.
        Recurso.fromJson({
          'id': 7,
          'nombre': 'Ana Torres',
          'rol': 'VENDEDOR',
          'permisos': ['ventas.crear'],
        }),
        Recurso.fromJson({
          'id': 8,
          'nombre': 'Rosa Gómez',
          'rol': 'VENDEDOR',
          'permisos': ['ventas.crear'],
        }),
      ];
      return ListadoRecurso(
        total: fuente.length,
        items: fuente.skip(offset).take(limit).toList(),
      );
    }
    return super.listar(
      recurso,
      limit: limit,
      offset: offset,
      estado: estado,
      q: q,
    );
  }
}

/// Salud de la API siempre "ok" (la consulta el dashboard).
class _SaludOk implements HealthRepository {
  const _SaludOk();

  @override
  Future<HealthStatus> getStatus() async => HealthStatus(
    service: 'ventas-api',
    version: 'test',
    databaseConnected: true,
    checkedAt: DateTime(2026),
  );
}

/// Rankings de venta vacíos: los gráficos pintan su estado "sin datos".
class _ReportesVacios implements ReporteRepository {
  const _ReportesVacios();

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  }) async => const [];

  @override
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async => InformeVentas(
    desde: _dia(desde),
    hasta: _dia(hasta),
    agrupacion: agrupacion,
    resumen: const ResumenVentas(total: 0, ordenes: 0, unidades: 0),
    serie: const [],
  );

  @override
  Future<InformeProductos> ventasPorProductoYCategoria({
    required DateTime desde,
    required DateTime hasta,
  }) async => const InformeProductos(productos: [], categorias: []);

  static String _dia(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

/// La app completa (navegación + los controladores que usan dashboard,
/// catálogo y clientes).
Widget _app({RecursoRepository? repositorio}) {
  final crud = Crud(repository: repositorio ?? _RepositorioVacio());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<HealthController>.value(
        value: HealthController(const GetHealthStatus(repository: _SaludOk())),
      ),
      ChangeNotifierProvider<ProductosController>.value(
        value: ProductosController(crud),
      ),
      ChangeNotifierProvider<CategoriasController>.value(
        value: CategoriasController(crud),
      ),
      ChangeNotifierProvider<MarcasController>.value(
        value: MarcasController(crud),
      ),
      ChangeNotifierProvider<ClientesController>.value(
        value: ClientesController(crud),
      ),
      ChangeNotifierProvider<EmpleadosController>.value(
        value: EmpleadosController(crud),
      ),
      ChangeNotifierProvider<OrdenesController>.value(
        value: OrdenesController(crud),
      ),
      ChangeNotifierProvider<FacturasController>.value(
        value: FacturasController(crud),
      ),
      ChangeNotifierProvider<ReportesController>.value(
        value: ReportesController(
          const Reportes(repository: _ReportesVacios()),
        ),
      ),
      ChangeNotifierProvider<CarritoController>.value(
        value: CarritoController(),
      ),
    ],
    child: const MaterialApp(home: MainScreen()),
  );
}

/// Ítem del sidebar: color de fondo del primer contenedor con relleno
/// (verde de la selección o transparente).
Color? _colorDelItem(WidgetTester tester, String etiqueta) {
  final enSidebar = find.descendant(
    of: find.byType(Sidebar),
    matching: find.text(etiqueta),
  );
  final contenedores = find
      .ancestor(of: enSidebar, matching: find.byType(Container))
      .evaluate();
  for (final elemento in contenedores) {
    final contenedor = elemento.widget as Container;
    final decoracion = contenedor.decoration;
    if (decoracion is BoxDecoration && decoracion.color != null) {
      return decoracion.color;
    }
  }
  return null;
}

void main() {
  /// Viewport de escritorio (se ve el sidebar).
  void escritorio(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> irA(WidgetTester tester, String modulo) async {
    await tester.tap(
      find.descendant(of: find.byType(Sidebar), matching: find.text(modulo)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el sidebar navega y el resaltado sigue la selección', (
    tester,
  ) async {
    escritorio(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_colorDelItem(tester, 'Dashboard'), AppColors.brandGreen);

    await irA(tester, 'Catálogo');
    expect(find.text('Catálogo (0)'), findsOneWidget);
    expect(_colorDelItem(tester, 'Catálogo'), AppColors.brandGreen);

    await irA(tester, 'Clientes');
    expect(find.text('Gestión de Clientes (0)'), findsOneWidget);
    expect(_colorDelItem(tester, 'Clientes'), AppColors.brandGreen);
    // El anterior deja de estar seleccionado.
    expect(_colorDelItem(tester, 'Catálogo'), isNot(AppColors.brandGreen));
  });

  testWidgets('cambiar de módulo no recrea las páginas visitadas', (
    tester,
  ) async {
    escritorio(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await irA(tester, 'Catálogo');
    final catalogo = tester.widget<CatalogoPage>(
      find.byType(CatalogoPage, skipOffstage: false),
    );

    // Ida y vuelta: el widget debe ser **el mismo objeto**, no una copia.
    // Antes cada página se reconstruía entera en cada clic del sidebar.
    await irA(tester, 'Clientes');
    await irA(tester, 'Catálogo');

    expect(tester.takeException(), isNull);
    final catalogoTrasVolver = tester.widget<CatalogoPage>(
      find.byType(CatalogoPage, skipOffstage: false),
    );
    expect(identical(catalogo, catalogoTrasVolver), isTrue);
    expect(find.text('Catálogo (0)'), findsOneWidget);
  });

  testWidgets('la sesión es el vendedor por defecto en «Nueva Orden»', (
    tester,
  ) async {
    escritorio(tester);
    // La app real, tal cual: sidebar → Ventas → Nueva Orden, con sesión.
    await tester.pumpWidget(
      SesionScope(
        datos: DatosSesion(
          usuario: const Usuario(
            id: 1,
            nombreUsuario: 'ana',
            nivelUsuario: 'CAJERO',
            permisos: [
              'dashboard.ver',
              'productos.ver',
              'catalogo.ver',
              'clientes.ver',
              'ventas.ver',
              'ventas.crear',
            ],
            empleadoId: 7,
          ),
          cerrarSesion: () async {},
        ),
        child: _app(repositorio: _RepositorioConEmpleados()),
      ),
    );
    await tester.pumpAndSettle();

    await irA(tester, 'Ventas');
    await tester.tap(find.text('Nueva Orden'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Sale marcada la cuenta conectada (Ana Torres, id 7)…
    expect(find.text('Ana Torres'), findsOneWidget);

    // …y admite cambiar a otro vendedor.
    await tester.tap(find.text('Ana Torres'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rosa Gómez'));
    await tester.pumpAndSettle();
    expect(find.text('Rosa Gómez'), findsOneWidget);
  });

  testWidgets('en móvil, el drawer "Más" navega al módulo y se cierra', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Más'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Catálogo')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // El drawer se cierra y el módulo queda seleccionado.
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Catálogo (0)'), findsOneWidget);
  });
}
