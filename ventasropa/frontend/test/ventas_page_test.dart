import 'package:ventas/core/widgets/sesion_scope.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/entities/usuario.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/ventas_page.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Listados vacíos: la página se pinta sin datos y sin tocar la red.
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

/// Listados con una orden (y sus líneas), una factura y los catálogos de
/// nombres que traduce la ficha de detalle.
class _RepositorioConDatos implements RecursoRepository {
  final orden = Recurso.fromJson({
    'id': 1,
    'fechaOrden': '2026-09-29T14:03:00.000Z',
    'clienteId': 1,
    'nombreCliente': 'María Pérez',
    'empleadoId': 7,
    'pagos': [
      {'metodoPago': 'EFECTIVO', 'monto': 21.0, 'referencia': null},
    ],
    'total': 21.0,
    'estado': 'PENDIENTE',
    'fechaCreacion': '2026-09-29T14:03:00.000Z',
    'fechaActualizacion': '2026-09-29T14:05:00.000Z',
  });

  final factura = Recurso.fromJson({
    'id': 3,
    'fechaFactura': '2026-09-29T14:10:00.000Z',
    'clienteId': 1,
    'empleadoId': 7,
    'ordenId': 1,
    'subtotal': 21.0,
    'rebaja': 1.0,
    'iva': 0.0,
    'total': 20.0,
    'estado': 'EMITIDA',
    'fechaCreacion': '2026-09-29T14:10:00.000Z',
    'fechaActualizacion': '2026-09-29T14:10:00.000Z',
  });

  final clientes = [
    Recurso.fromJson({'id': 1, 'nombre': 'María Pérez'}),
  ];

  // Dos vendedores para poder cambiar de uno a otro en el formulario, más un
  // empleado cuyo rol no permite vender: ese último no debe entrar en el
  // desplegable.
  final empleados = [
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
    Recurso.fromJson({
      'id': 9,
      'nombre': 'Luis Alcázar',
      'rol': 'BODEGUERO',
      'permisos': ['productos.ver'],
    }),
  ];

  final producto = Recurso.fromJson({
    'id': 40,
    'nombre': 'Vitamina C 1000mg',
    'precioVenta': 10.0,
    'stock': 12,
    'variantes': [
      {
        'id': 40,
        'productoId': 40,
        'tallaId': 1,
        'colorId': 1,
        'talla': 'Única',
        'color': 'Único',
        'stock': 12,
        'estado': 'ACTIVO',
      },
    ],
  });

  /// Cuerpo enviado por el formulario de «Nueva Orden».
  Map<String, Object?>? ultimaOrden;

  /// Último cuerpo enviado a `POST /clientes` (alta desde el selector).
  Map<String, Object?>? ultimoCliente;

  // Las líneas llegan tal cual del backend: sin `id` propio.
  final List<Map<String, Object?>> lineas = [
    {
      'productoId': 1,
      'ordenId': 1,
      'nombreProducto': 'Paracetamol 500mg',
      'cantidad': 2,
      'precioVenta': 5.5,
      'montoTotal': 11.0,
    },
    {
      'productoId': 4,
      'ordenId': 1,
      'nombreProducto': 'Vitamina C 1000mg',
      'cantidad': 1,
      'precioVenta': 10.0,
      'montoTotal': 10.0,
    },
  ];

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
      case 'ordenes':
        return ListadoRecurso(
          total: 1,
          items: [orden].skip(offset).take(limit).toList(),
        );
      case 'facturas':
        return ListadoRecurso(
          total: 1,
          items: [factura].skip(offset).take(limit).toList(),
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
    // `GET /ordenes/1` devuelve la cabecera más sus líneas en la misma
    // respuesta (la lista de `detalles` ya no se pide aparte).
    if (ruta == 'ordenes/1') {
      return Recurso(id: orden.id, datos: {...orden.datos, 'detalles': lineas});
    }
    return const Recurso(id: 0, datos: {});
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    if (ruta == 'ordenes') {
      ultimaOrden = body;
      return orden;
    }
    if (ruta == 'clientes') {
      ultimoCliente = body;
      final creado = Recurso.fromJson({'id': clientes.length + 10, ...body});
      clientes.add(creado);
      return creado;
    }
    throw UnimplementedError();
  }

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

/// Pinta `VentasPage` con los cinco controladores que necesita.
Widget _ventas({RecursoRepository? repositorio}) {
  final crud = Crud(repository: repositorio ?? _RepositorioVacio());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<OrdenesController>.value(
        value: OrdenesController(crud),
      ),
      ChangeNotifierProvider<FacturasController>.value(
        value: FacturasController(crud),
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
    child: MaterialApp(home: VentasPage(selectedNav: 3, onNavSelect: (_) {})),
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

  testWidgets('arranca sin excepción y pinta su cabecera', (tester) async {
    escritorio(tester);

    await tester.pumpWidget(_ventas());
    await tester.pumpAndSettle();

    // Regresión: leer los controladores `late` (resueltos en
    // `didChangeDependencies`) dentro de `initState` lanzaba
    // LateInitializationError al montar la página.
    expect(tester.takeException(), isNull);
    expect(find.text('Gestión de Ventas (0)'), findsOneWidget);
  });

  testWidgets('el formulario "Nueva Orden" pinta sus tres desplegables', (
    tester,
  ) async {
    escritorio(tester);

    await tester.pumpWidget(_ventas());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva Orden'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Cabecera de la hoja + campos (las opciones se memorizan por fuente).
    expect(find.text('Nueva Orden'), findsNWidgets(2));
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Vendedor'), findsOneWidget);
    expect(find.text('Método de pago'), findsOneWidget);
    expect(find.text('Prenda'), findsOneWidget);
    expect(find.text('Talla / color'), findsOneWidget);
    // Opciones por defecto de los dos selects no obligatorios.
    expect(find.text('— Cliente ocasional —'), findsOneWidget);
    expect(find.text('— Sin asignar —'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
  });

  testWidgets(
    'nueva orden: el vendedor por defecto es la sesión y admite cambio',
    (tester) async {
      escritorio(tester);
      final repositorio = _RepositorioConDatos();

      await tester.pumpWidget(
        SesionScope(
          datos: DatosSesion(
            usuario: const Usuario(
              id: 9,
              nombreUsuario: 'ana',
              nivelUsuario: 'CAJERO',
              permisos: ['ventas.ver', 'ventas.crear'],
              empleadoId: 7,
            ),
            cerrarSesion: () async {},
          ),
          child: _ventas(repositorio: repositorio),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nueva Orden'));
      await tester.pumpAndSettle();

      // Sale marcada la cuenta conectada (Ana Torres, id 7)…
      expect(tester.takeException(), isNull);
      expect(find.text('Ana Torres'), findsOneWidget);

      // …y se puede cambiar a otro vendedor.
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(DesplegableBuscable),
            )
            .at(1),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rosa Gómez'));
      await tester.pumpAndSettle();
      expect(find.text('Rosa Gómez'), findsOneWidget);

      // Lo que llega a `POST /ordenes` es el vendedor elegido.
      // Desplegables de la hoja: 0 cliente · 1 vendedor · 2 producto · 3 método.
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(DesplegableBuscable),
            )
            .at(2),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vitamina C 1000mg'));
      await tester.pumpAndSettle();

      // El total (vitamina 10 × 1) hay que repartirlo: se paga en efectivo.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Monto (Bs)').first,
        '10',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crear'));
      // Tras guardar se dispara `alertaExito` (QuickAlert + GIF): solo pumps
      // acotados, `pumpAndSettle` se quedaría girando con el GIF.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repositorio.ultimaOrden?['empleadoId'], 8);
      final pagos = repositorio.ultimaOrden?['pagos'] as List;
      expect((pagos.single as Map)['metodoPago'], 'EFECTIVO');
      expect((pagos.single as Map)['monto'], 10.0);
    },
  );

  testWidgets(
    'el desplegable de vendedor solo lista vendedores y se filtra escribiendo',
    (tester) async {
      escritorio(tester);

      await tester.pumpWidget(_ventas(repositorio: _RepositorioConDatos()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nueva Orden'));
      await tester.pumpAndSettle();

      // Se abre el selector de vendedor (2.º desplegable de la hoja).
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(DesplegableBuscable),
            )
            .at(1),
      );
      await tester.pumpAndSettle();

      // La hoja de opciones es la última abierta.
      final hoja = find.byType(BottomSheet).last;
      Finder en(Finder f) => find.descendant(of: hoja, matching: f);

      // Solo los cuyo rol permite crear ventas: Luis es bodeguero.
      expect(en(find.text('Ana Torres')), findsOneWidget);
      expect(en(find.text('Rosa Gómez')), findsOneWidget);
      expect(en(find.text('Luis Alcázar')), findsNothing);

      // Escribir con el teclado va filtrando la lista.
      await tester.enterText(en(find.byType(TextField)), 'rosa g');
      await tester.pumpAndSettle();
      expect(en(find.text('Rosa Gómez')), findsOneWidget);
      expect(en(find.text('Ana Torres')), findsNothing);

      await tester.enterText(en(find.byType(TextField)), 'nadie');
      await tester.pumpAndSettle();
      expect(en(find.textContaining('Sin coincidencias')), findsOneWidget);
    },
  );

  testWidgets(
    'el vendedor de la sesión entra en la lista aunque su rol no lo permita',
    (tester) async {
      escritorio(tester);

      // La sesión está vinculada a un empleado cuyo rol no vende: el
      // vendedor por defecto no puede quedar fuera de sus propias opciones.
      await tester.pumpWidget(
        SesionScope(
          datos: DatosSesion(
            usuario: const Usuario(
              id: 2,
              nombreUsuario: 'luis',
              nivelUsuario: 'CAJERO',
              permisos: ['ventas.ver', 'ventas.crear'],
              empleadoId: 9,
            ),
            cerrarSesion: () async {},
          ),
          child: _ventas(repositorio: _RepositorioConDatos()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nueva Orden'));
      await tester.pumpAndSettle();

      expect(find.text('Luis Alcázar'), findsOneWidget);

      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(DesplegableBuscable),
            )
            .at(1),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.text('Luis Alcázar'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('«Nueva Orden» crea un cliente desde su selector', (tester) async {
    escritorio(tester);
    final repositorio = _RepositorioConDatos();

    await tester.pumpWidget(_ventas(repositorio: repositorio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva Orden'));
    await tester.pumpAndSettle();

    // El selector de cliente es el primero de la hoja.
    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(DesplegableBuscable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuevo cliente'));
    await tester.pumpAndSettle();

    // El alta abre su propia hoja con la ficha completa del cliente: los
    // campos de texto van por orden (nombre, apellido, CI...).
    final camposAlta = find.descendant(
      of: find.byType(BottomSheet).last,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(camposAlta.at(0), 'Rosa');
    await tester.enterText(camposAlta.at(1), 'Ramos');
    await tester.enterText(camposAlta.at(2), '6789012');
    final crear = find.descendant(
      of: find.byType(BottomSheet).last,
      matching: find.widgetWithText(ElevatedButton, 'Crear'),
    );
    await tester.ensureVisible(crear);
    await tester.pumpAndSettle();
    await tester.tap(crear);
    await tester.pumpAndSettle();

    // El alta llegó a la API con la ficha entera y el formulario se queda
    // con la nueva, mostrando «Nombre Apellido».
    expect(repositorio.ultimoCliente?['nombre'], 'Rosa');
    expect(repositorio.ultimoCliente?['apellido'], 'Ramos');
    expect(repositorio.ultimoCliente?['ci'], '6789012');
    expect(repositorio.ultimoCliente?['estado'], 'ACTIVO');
    expect(find.text('Rosa Ramos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso `clientes.crear` no se ofrece el alta', (
    tester,
  ) async {
    escritorio(tester);

    // La sesión crea órdenes pero no da de alta clientes: el botón no pinta.
    await tester.pumpWidget(
      SesionScope(
        datos: DatosSesion(
          usuario: const Usuario(
            id: 2,
            nombreUsuario: 'luis',
            nivelUsuario: 'CAJERO',
            permisos: ['ventas.ver', 'ventas.crear'],
          ),
          cerrarSesion: () async {},
        ),
        child: _ventas(repositorio: _RepositorioConDatos()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva Orden'));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(DesplegableBuscable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nuevo cliente'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.text('María Pérez'),
      ),
      findsOneWidget,
    );
  });

  group('ficha de detalle de la venta', () {
    /// Abre el detalle de la fila visible con el botón 👁.
    Future<void> verDetalle(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();
    }

    testWidgets('la orden muestra cliente, empleado, pago y sus productos', (
      tester,
    ) async {
      escritorio(tester);
      await tester.pumpWidget(_ventas(repositorio: _RepositorioConDatos()));
      await tester.pumpAndSettle();

      await verDetalle(tester);

      final hoja = find.byType(BottomSheet);
      Finder en(Finder texto) => find.descendant(of: hoja, matching: texto);

      expect(en(find.text('Orden #1')), findsOneWidget);
      expect(en(find.text('María Pérez')), findsOneWidget);
      expect(en(find.text('Ana Torres')), findsOneWidget);
      expect(en(find.text('Efectivo')), findsOneWidget);
      expect(en(find.text('Fecha de orden')), findsOneWidget);
      // Líneas que trae `GET /ordenes/1` junto a la cabecera.
      expect(en(find.text('Productos · 2 líneas · 3 u.')), findsOneWidget);
      expect(en(find.text('Paracetamol 500mg')), findsOneWidget);
      expect(en(find.text('2 UN × Bs 5.50')), findsOneWidget);
      expect(en(find.text('Bs 11.00')), findsOneWidget);
      expect(en(find.text('Vitamina C 1000mg')), findsOneWidget);
      expect(en(find.text('Bs 10.00')), findsOneWidget);
      expect(en(find.text('Total')), findsOneWidget);
      // El desglose de pagos (efectivo 21.00) y el total muestran el mismo.
      expect(en(find.text('Bs 21.00')), findsNWidgets(2));
      expect(en(find.text('Ver recibo')), findsOneWidget);
      expect(en(find.text('Cerrar')), findsOneWidget);
      // Sin desbordes en la hoja (filas etiqueta/valor + lista de líneas).
      expect(tester.takeException(), isNull);
    });

    testWidgets('la factura traduce sus importes y a quién pertenece', (
      tester,
    ) async {
      escritorio(tester);
      await tester.pumpWidget(_ventas(repositorio: _RepositorioConDatos()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Boletas'));
      await tester.pumpAndSettle();
      await verDetalle(tester);

      final hoja = find.byType(BottomSheet);
      Finder en(Finder texto) => find.descendant(of: hoja, matching: texto);

      expect(en(find.text('Boleta #3')), findsOneWidget);
      expect(en(find.text('Orden')), findsOneWidget);
      expect(en(find.text('#1')), findsOneWidget);
      expect(en(find.text('María Pérez')), findsOneWidget);
      expect(en(find.text('Ana Torres')), findsOneWidget);
      expect(en(find.text('Subtotal')), findsOneWidget);
      expect(en(find.text('Bs 21.00')), findsOneWidget);
      expect(en(find.text('Rebaja')), findsOneWidget);
      expect(en(find.text('− Bs 1.00')), findsOneWidget);
      expect(en(find.text('IVA 14.94%')), findsOneWidget);
      expect(en(find.text('Total')), findsOneWidget);
      expect(en(find.text('Bs 20.00')), findsOneWidget);
      expect(en(find.text('Ver recibo')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
