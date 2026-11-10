import 'package:farmacia/core/network/api_client.dart';
import 'package:farmacia/core/widgets/responsive_layout.dart';
import 'package:farmacia/core/widgets/sidebar.dart';
import 'package:farmacia/data/datasources/health_remote_datasource.dart';
import 'package:farmacia/data/repositories/health_repository_impl.dart';
import 'package:farmacia/domain/entities/recurso.dart';
import 'package:farmacia/domain/entities/reporte.dart';
import 'package:farmacia/domain/repositories/recurso_repository.dart';
import 'package:farmacia/domain/repositories/reporte_repository.dart';
import 'package:farmacia/domain/usecases/crud.dart';
import 'package:farmacia/domain/usecases/get_health_status.dart';
import 'package:farmacia/domain/usecases/reporte_usecases.dart';
import 'package:farmacia/presentation/controllers/health_controller.dart';
import 'package:farmacia/presentation/controllers/recurso_controller.dart';
import 'package:farmacia/presentation/controllers/reporte_controller.dart';
import 'package:farmacia/presentation/pages/clientes_page.dart';
import 'package:farmacia/presentation/pages/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Validación de la §14 de `DISENO_RESPONSIVE.md` a los 4 anchos de prueba.
///
/// Cualquier `RenderFlex overflow` hace fallar el test, así que sirve también
/// como red de seguridad de la responsividad.
class _RepositorioFalso implements RecursoRepository {
  final List<Recurso> registros = [
    for (var i = 1; i <= 14; i++)
      Recurso.fromJson({
        'id': i,
        'nombre': 'Cliente ${i.toString().padLeft(2, '0')}',
        'ci': '404040$i',
        'ciudad': 'Lima',
        'telefono': '999888$i',
        'estado': i.isEven ? 'ACTIVO' : 'INACTIVO',
        'fechaOrden': '2026-08-0${(i % 9) + 1}T10:00:00Z',
        'tipoPago': 'EFECTIVO',
        'total': 100 + i,
        'stock': i * 3,
        'nombreCliente': 'Cliente ${i.toString().padLeft(2, '0')}',
        // Vencimientos: uno ya vencido, dos dentro de la ventana de 90 días
        // (los que pinta la tarjeta «Productos por vencer») y el resto, lejanos.
        'fechaVencimiento': switch (i) {
          3 => _dentroDe(-5),
          5 => _dentroDe(15),
          7 => _dentroDe(70),
          _ => _dentroDe(400),
        },
      }),
  ];

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async => ListadoRecurso(
    total: registros.length,
    items: registros.skip(offset).take(limit).toList(),
  );

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

/// Rankings del dashboard siempre con datos, sin tocar la red.
class _ReportesFalsos implements ReporteRepository {
  @override
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  }) async => [
    for (var i = 1; i <= limite; i++)
      VentaProducto(
        productoId: i,
        nombre: 'Producto $i',
        unidades: orden == 'desc' ? 40 - (i * 3) : i,
        monto: i * 10.5,
      ),
  ];
}

/// `fechaVencimiento` relativa a hoy (`-5` = ya vencido).
String _dentroDe(int dias) =>
    DateTime.now().add(Duration(days: dias)).toIso8601String().split('T').first;

void _tamano(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _dashboard(RecursoRepository repositorio) {
  final crud = Crud(repository: repositorio);
  final api = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<HealthController>.value(
        value: HealthController(
          GetHealthStatus(
            repository: HealthRepositoryImpl(HealthRemoteDataSource(api)),
          ),
        ),
      ),
      ChangeNotifierProvider<ProductosController>.value(
        value: ProductosController(crud),
      ),
      ChangeNotifierProvider<ClientesController>.value(
        value: ClientesController(crud),
      ),
      ChangeNotifierProvider<OrdenesController>.value(
        value: OrdenesController(crud),
      ),
      ChangeNotifierProvider<FacturasController>.value(
        value: FacturasController(crud),
      ),
      ChangeNotifierProvider<ReportesController>.value(
        value: ReportesController(Reportes(repository: _ReportesFalsos())),
      ),
    ],
    child: MaterialApp(
      home: const DashboardPage(selectedNav: 0, onNavSelect: _sinNavegacion),
    ),
  );
}

void _sinNavegacion(int _) {}

Widget _clientes(RecursoRepository repositorio) {
  return ChangeNotifierProvider<ClientesController>.value(
    value: ClientesController(Crud(repository: repositorio)),
    child: MaterialApp(
      home: ClientesPage(selectedNav: 3, onNavSelect: _sinNavegacion),
    ),
  );
}

void main() {
  group('dashboard a los 4 anchos de la guía', () {
    for (final tamano in const [
      (Size(1200, 800), 'desktop'),
      (Size(900, 800), 'tablet'),
      (Size(600, 780), 'móvil'),
      (Size(360, 780), 'móvil estrecho'),
    ]) {
      testWidgets('${tamano.$2} (${tamano.$1.width.toInt()}px)', (
        tester,
      ) async {
        _tamano(tester, tamano.$1);
        await tester.pumpWidget(_dashboard(_RepositorioFalso()));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Resumen general'), findsOneWidget);

        final esDesktop = tamano.$1.width >= 1100;
        expect(find.byType(Sidebar), esDesktop ? findsOneWidget : findsNothing);
        expect(
          find.byType(BottomNavigationBar),
          esDesktop ? findsNothing : findsOneWidget,
        );
        // Grid de KPIs: 4 columnas en desktop, 3 en tablet, 2 en móvil.
        expect(find.text('Productos'), findsWidgets); // KPI (+ ítem sidebar)
        expect(find.text('Ventas pagadas'), findsOneWidget); // solo el KPI
      });
    }
  });

  group('clientes: tabla (>=700) y tarjetas (<700)', () {
    testWidgets('900px -> tabla completa con encabezados', (tester) async {
      _tamano(tester, const Size(900, 800));
      await tester.pumpWidget(_clientes(_RepositorioFalso()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Sidebar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Nombre'), findsOneWidget); // encabezado de columna
      expect(find.text('CI: '), findsNothing); // no hay tarjetas
    });

    testWidgets('360px -> tarjetas y PageHeader apilado', (tester) async {
      _tamano(tester, const Size(360, 780));
      await tester.pumpWidget(_clientes(_RepositorioFalso()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('CI: '), findsWidgets); // pares etiqueta: valor
      expect(find.text('Nombre'), findsNothing); // la 1ª columna es el título

      // < 500: el botón queda debajo del título, no en la misma fila.
      final titulo = tester.getTopLeft(find.text('Gestión de Clientes (14)'));
      final boton = tester.getTopLeft(find.text('Nuevo Cliente'));
      expect(boton.dy, greaterThan(titulo.dy));
      expect(find.byType(PageHeader), findsOneWidget);
    });

    testWidgets('900px -> botón del header en la misma fila', (tester) async {
      _tamano(tester, const Size(900, 800));
      await tester.pumpWidget(_clientes(_RepositorioFalso()));
      await tester.pumpAndSettle();

      final titulo = tester.getTopLeft(find.text('Gestión de Clientes (14)'));
      final boton = tester.getTopLeft(find.text('Nuevo Cliente'));
      expect((boton.dy - titulo.dy).abs(), lessThan(24));
    });
  });
}
