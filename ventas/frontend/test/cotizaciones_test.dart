import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/cotizaciones_page.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:ventas/presentation/widgets/imagen_recurso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Listado vacío: la página se pinta sin datos y sin tocar la red.
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

/// Listados con una cotización, sus líneas (con imagen) y los catálogos
/// que traduce la ficha y el formulario.
class _RepositorioConCotizaciones implements RecursoRepository {
  final cotizacion = Recurso.fromJson({
    'id': 1,
    'fechaCotizacion': '2026-09-30T10:00:00.000Z',
    'clienteId': 1,
    'nombreCliente': 'María Pérez',
    'empleadoId': 7,
    'total': 31.0,
    'estado': 'VIGENTE',
    'fechaCreacion': '2026-09-30T10:00:00.000Z',
    'fechaActualizacion': '2026-09-30T10:00:00.000Z',
  });

  final clientes = [
    Recurso.fromJson({'id': 1, 'nombre': 'María Pérez'}),
  ];

  final empleados = [
    Recurso.fromJson({
      'id': 7,
      'nombre': 'Ana Torres',
      'rol': 'VENDEDOR',
      'permisos': ['ventas.crear'],
    }),
  ];

  final producto = Recurso.fromJson({
    'id': 40,
    'nombre': 'Vitamina C 1000mg',
    'precioVenta': 10.0,
    'stock': 12,
    'imagen': '/api/v1/archivos/imagenes/vitamina.png',
  });

  /// Líneas tal cual del backend (sin `id` propio, con la imagen congelada).
  final List<Map<String, Object?>> lineas = [
    {
      'productoId': 40,
      'nombreProducto': 'Vitamina C 1000mg',
      'imagen': '/api/v1/archivos/imagenes/vitamina.png',
      'cantidad': 3,
      'precioVenta': 10.0,
      'montoTotal': 30.0,
    },
    {
      'productoId': 1,
      'nombreProducto': 'Paracetamol 500mg',
      'imagen': null,
      'cantidad': 1,
      'precioVenta': 1.0,
      'montoTotal': 1.0,
    },
  ];

  Map<String, Object?>? ultimaCotizacion;
  String? ultimoEstadoEditado;
  String? ultimoEstadoFiltrado;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    switch (recurso) {
      case 'cotizaciones':
        ultimoEstadoFiltrado = estado;
        return ListadoRecurso(
          total: 1,
          items: [cotizacion].skip(offset).take(limit).toList(),
        );
      case 'clientes':
        return ListadoRecurso(
          total: clientes.length,
          items: clientes.skip(offset).take(limit).toList(),
        );
      case 'empleados':
        return ListadoRecurso(
          total: empleados.length,
          items: empleados.skip(offset).take(limit).toList(),
        );
      case 'productos':
        return ListadoRecurso(
          total: 1,
          items: [producto].skip(offset).take(limit).toList(),
        );
      default:
        return const ListadoRecurso(total: 0, items: []);
    }
  }

  @override
  Future<Recurso> obtener(String ruta) async {
    // `GET /cotizaciones/1` devuelve la cabecera más sus líneas.
    if (ruta == 'cotizaciones/1') {
      return Recurso(
        id: cotizacion.id,
        datos: {...cotizacion.datos, 'detalles': lineas},
      );
    }
    return const Recurso(id: 0, datos: {});
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    if (ruta == 'cotizaciones') {
      ultimaCotizacion = body;
      return cotizacion;
    }
    throw UnimplementedError();
  }

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) async {
    if (ruta == 'cotizaciones/1/estado') {
      ultimoEstadoEditado = body['estado'] as String?;
      return cotizacion;
    }
    throw UnimplementedError();
  }

  @override
  Future<void> eliminar(String ruta) async {}
}

/// Pinta `CotizacionesPage` con los cuatro controladores que necesita.
Widget _pagina({RecursoRepository? repositorio}) {
  final crud = Crud(repository: repositorio ?? _RepositorioVacio());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<CotizacionesController>.value(
        value: CotizacionesController(crud),
      ),
      ChangeNotifierProvider<ClientesController>.value(
        value: ClientesController(crud),
      ),
      ChangeNotifierProvider<EmpleadosController>.value(
        value: EmpleadosController(crud),
      ),
      ChangeNotifierProvider<ProductosController>.value(
        value: ProductosController(crud),
      ),
    ],
    child: const MaterialApp(home: CotizacionesPage()),
  );
}

void main() {
  /// Viewport de escritorio (sidebar, tabla).
  void escritorio(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('la tabla pinta cliente, creador, total y estado', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioConCotizaciones();

    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Gestión de Cotizaciones (1)'), findsOneWidget);
    expect(find.text('Nueva cotización'), findsOneWidget);
    // Fila: cliente, nº, creador (empleado resuelto), fecha y total.
    expect(find.text('María Pérez'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Ana Torres'), findsOneWidget);
    expect(find.text('2026-09-30'), findsOneWidget);
    expect(find.text('Bs 31.00'), findsOneWidget);
    expect(find.text('VIGENTE'), findsWidgets);
    // Chips de estado para filtrar.
    expect(find.text('ACEPTADA'), findsOneWidget);
    expect(find.text('RECHAZADA'), findsOneWidget);
  });

  testWidgets('los chips de estado filtran contra la API', (tester) async {
    escritorio(tester);
    final repositorio = _RepositorioConCotizaciones();

    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();
    expect(repositorio.ultimoEstadoFiltrado, isNull);

    await tester.tap(
      find.descendant(
        of: find.byType(FilterChip),
        matching: find.text('ACEPTADA'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repositorio.ultimoEstadoFiltrado, 'ACEPTADA');
  });

  testWidgets('«Nueva cotización» envía cliente e items y sin pagos', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioConCotizaciones();

    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva cotización'));
    await tester.pumpAndSettle();

    final hoja = find.byType(BottomSheet);
    expect(
      find.descendant(of: hoja, matching: find.text('Nueva Cotización')),
      findsOneWidget,
    );

    // Cliente: mostrador → María Pérez (la opción del desplegable es la
    // última: la de la tabla de fondo también tiene ese nombre).
    await tester.tap(
      find.descendant(of: hoja, matching: find.text('— Cliente mostrador —')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('María Pérez').last);
    await tester.pumpAndSettle();

    // Producto de la única línea (2.º desplegable de la hoja).
    await tester.tap(
      find
          .descendant(of: hoja, matching: find.byType(DesplegableBuscable))
          .at(1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vitamina C 1000mg'));
    await tester.pumpAndSettle();

    // Total en vivo: 1 × Bs 10.00 (sin tope de stock).
    expect(find.text('Bs 10.00'), findsWidgets);

    // El producto elegido muestra su imagen grande junto a precio y stock.
    expect(
      find.descendant(of: hoja, matching: find.byType(ImagenRecurso)),
      findsOneWidget,
    );
    expect(find.text('Stock disponible: 12 UN'), findsOneWidget);

    // Tocar la imagen la amplía en un diálogo con la foto del producto.
    await tester.tap(
      find.descendant(of: hoja, matching: find.byType(ImagenRecurso)),
    );
    await tester.pumpAndSettle();
    final dialogo = find.byType(AlertDialog);
    expect(dialogo, findsOneWidget);
    expect(
      find.descendant(of: dialogo, matching: find.text('Vitamina C 1000mg')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: dialogo, matching: find.text('Cerrar')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: hoja, matching: find.text('Crear')));
    // `alertaExito` (QuickAlert + GIF): solo pumps acotados.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repositorio.ultimaCotizacion, isNotNull);
    final body = repositorio.ultimaCotizacion!;
    expect(body['clienteId'], 1);
    expect(body['nombreCliente'], 'María Pérez');
    expect(body['items'], [
      {'productoId': 40, 'varianteId': null, 'cantidad': 1},
    ]);
    // Sin pagos ni stock: una cotización solo propone precios.
    expect(body.containsKey('pagos'), isFalse);
  });

  testWidgets('el selector de producto muestra la miniatura en cada opción', (
    tester,
  ) async {
    escritorio(tester);
    await tester.pumpWidget(
      _pagina(repositorio: _RepositorioConCotizaciones()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva cotización'));
    await tester.pumpAndSettle();

    // 2.º desplegable de la hoja = Producto (se creó con `conImagen: true`).
    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(DesplegableBuscable),
          )
          .at(1),
    );
    await tester.pumpAndSettle();

    // La hoja de opciones pinta la miniatura junto al nombre del producto
    // (la opción «— Selecciona —» no lleva imagen).
    expect(find.byType(ImagenRecurso), findsOneWidget);
    expect(find.text('Vitamina C 1000mg'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la ficha muestra los datos, las líneas con imagen y el PDF', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioConCotizaciones();

    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    final hoja = find.byType(BottomSheet);
    Finder en(Finder texto) => find.descendant(of: hoja, matching: texto);

    expect(en(find.text('Cotización #1')), findsOneWidget);
    expect(en(find.text('María Pérez')), findsOneWidget);
    expect(en(find.text('Ana Torres')), findsOneWidget);
    expect(en(find.text('Vitamina C 1000mg')), findsOneWidget);
    expect(en(find.text('3 UN × Bs 10.00')), findsOneWidget);
    expect(en(find.text('Bs 30.00')), findsOneWidget);
    expect(en(find.text('Total')), findsOneWidget);
    // Cada línea pinta su hueco de imagen (la de Paracetamol, sin imagen,
    // sale como placeholder; la de Vitamina C intenta cargar la red).
    expect(en(find.byType(ImagenRecurso)), findsNWidgets(2));
    expect(en(find.text('Ver PDF')), findsOneWidget);
    expect(en(find.text('Cerrar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar estado envía PUT al endpoint de estado', (tester) async {
    escritorio(tester);
    final repositorio = _RepositorioConCotizaciones();

    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final dialogo = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: dialogo,
        matching: find.text('Cambiar estado de la cotización'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: dialogo, matching: find.text('ACEPTADA')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialogo, matching: find.text('Aceptar')),
    );
    // `alertaExito` tras guardar: pumps acotados por el GIF.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repositorio.ultimoEstadoEditado, 'ACEPTADA');
  });

  testWidgets('sin cotizaciones pinta el estado vacío', (tester) async {
    escritorio(tester);

    await tester.pumpWidget(_pagina());
    await tester.pumpAndSettle();

    expect(find.text('No hay cotizaciones registradas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
