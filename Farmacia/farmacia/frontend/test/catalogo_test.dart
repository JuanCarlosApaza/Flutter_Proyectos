import 'package:farmacia/core/widgets/responsive_layout.dart';
import 'package:farmacia/core/widgets/sesion_scope.dart';
import 'package:farmacia/core/widgets/sidebar.dart';
import 'package:farmacia/domain/entities/recurso.dart';
import 'package:farmacia/domain/entities/usuario.dart';
import 'package:farmacia/domain/repositories/recurso_repository.dart';
import 'package:farmacia/domain/usecases/crud.dart';
import 'package:farmacia/presentation/controllers/carrito_controller.dart';
import 'package:farmacia/presentation/controllers/recurso_controller.dart';
import 'package:farmacia/presentation/pages/catalogo_page.dart';
import 'package:farmacia/presentation/widgets/carrito_panel.dart';
import 'package:farmacia/presentation/widgets/producto_tarjeta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Doble en memoria: productos/categorías de prueba sin tocar la red.
class _RepositorioFalso implements RecursoRepository {
  _RepositorioFalso({this.extra = 0});

  /// Productos adicionales a los 4 de ejemplo: permiten probar la paginación
  /// (24 por página) sin ensuciar el resto de tests.
  final int extra;

  late final List<Recurso> productos = [
    Recurso.fromJson({
      'id': 1,
      'nombre': 'Paracetamol 500mg',
      'precioVenta': 5.5,
      'stock': 20,
      'categoriaId': 1,
      'estado': 'DISPONIBLE',
    }),
    Recurso.fromJson({
      'id': 2,
      'nombre': 'Ibuprofeno 400mg',
      'precioVenta': 8.0,
      'stock': 12,
      'categoriaId': 1,
      'estado': 'DISPONIBLE',
    }),
    Recurso.fromJson({
      'id': 3,
      'nombre': 'Antiséptico topical',
      'precioVenta': 15.0,
      'stock': 0,
      'categoriaId': 2,
      'estado': 'AGOTADO',
    }),
    Recurso.fromJson({
      'id': 4,
      'nombre': 'Vitamina C 1000mg',
      'precioVenta': 25.9,
      'stock': 5,
      'categoriaId': 2,
      'estado': 'DISPONIBLE',
    }),
    for (var i = 0; i < extra; i++)
      Recurso.fromJson({
        'id': 100 + i,
        'nombre': 'Producto ${100 + i}',
        'precioVenta': 3.5,
        'stock': 8,
        'categoriaId': 1,
        'estado': 'DISPONIBLE',
      }),
  ];

  final List<Recurso> categorias = [
    Recurso.fromJson({'id': 1, 'nombre': 'Analgésicos'}),
    Recurso.fromJson({'id': 2, 'nombre': 'Vitaminas'}),
  ];

  /// Clientes del selector de la caja del carrito.
  final List<Recurso> clientes = [
    Recurso.fromJson({'id': 1, 'nombre': 'María Pérez'}),
    Recurso.fromJson({'id': 2, 'nombre': 'Juan Quispe'}),
  ];

  /// Empleados del selector de vendedor de la caja.
  final List<Recurso> empleados = [
    // Con rol que permite crear ventas: el desplegable del carrito solo
    // acepta a esos.
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

  /// Último cuerpo enviado a `POST /ordenes` (para las aserciones).
  Map<String, Object?>? ultimaOrden;

  /// Último cuerpo enviado a `POST /clientes` (alta desde la caja).
  Map<String, Object?>? ultimoCliente;

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
      case 'productos':
        return ListadoRecurso(
          total: productos.length,
          items: productos.skip(offset).take(limit).toList(),
        );
      case 'categorias':
        return ListadoRecurso(
          total: categorias.length,
          items: categorias.skip(offset).take(limit).toList(),
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
      default:
        return const ListadoRecurso(total: 0, items: []);
    }
  }

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) {
    if (ruta == 'ordenes') {
      ultimaOrden = body;
      return Future.value(Recurso.fromJson({'id': 1, 'estado': 'PENDIENTE'}));
    }
    if (ruta == 'clientes') {
      ultimoCliente = body;
      final creado = Recurso.fromJson({'id': clientes.length + 10, ...body});
      clientes.add(creado);
      return Future.value(creado);
    }
    return Future.error(UnimplementedError());
  }

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

void _tamano(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pinta el catálogo con sus 6 controladores (productos, categorías,
/// clientes, empleados, órdenes y carrito).
///
/// [empleadoDeLaSesion] registra una sesión: su `empleadoId` es el vendedor
/// por defecto de la caja (sin sesión el panel se queda en "Sin asignar").
Widget _catalogo({
  required RecursoRepository repositorio,
  required CarritoController carrito,
  ValueChanged<int>? onNavSelect,
  int? empleadoDeLaSesion,
}) {
  final crud = Crud(repository: repositorio);
  final arbol = MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductosController>.value(
        value: ProductosController(crud),
      ),
      ChangeNotifierProvider<CategoriasController>.value(
        value: CategoriasController(crud),
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
      ChangeNotifierProvider<CarritoController>.value(value: carrito),
    ],
    child: MaterialApp(
      home: CatalogoPage(selectedNav: 2, onNavSelect: onNavSelect ?? _sin),
    ),
  );
  if (empleadoDeLaSesion == null) return arbol;

  // La página lee la sesión antes de abrir la hoja (el modal queda fuera del
  // `SesionScope`, igual que en la app real).
  return SesionScope(
    datos: DatosSesion(
      usuario: Usuario(
        id: 1,
        nombreUsuario: 'ana',
        nivelUsuario: 'CAJERO',
        // El carrito genera órdenes: el botón exige `ventas.crear`.
        permisos: const [
          'ventas.ver',
          'ventas.crear',
          'catalogo.ver',
          'catalogo.crear',
        ],
        empleadoId: empleadoDeLaSesion,
      ),
      cerrarSesion: () async {},
    ),
    child: arbol,
  );
}

void _sin(int _) {}

/// Pinta solo la hoja del carrito (checkout aislado de la página).
Widget _hoja({
  required CarritoController carrito,
  required Future<void> Function(Map<String, Object?> body) onGenerarOrden,
}) {
  return ChangeNotifierProvider<CarritoController>.value(
    value: carrito,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                mostrarCarrito(context, onGenerarOrden: onGenerarOrden),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _abrirCatalogo(
  WidgetTester tester, {
  Size tamano = const Size(1200, 1000),
  RecursoRepository? repositorio,
  CarritoController? carrito,
  ValueChanged<int>? onNavSelect,
  int? empleadoDeLaSesion,
}) async {
  _tamano(tester, tamano);
  await tester.pumpWidget(
    _catalogo(
      repositorio: repositorio ?? _RepositorioFalso(),
      carrito: carrito ?? CarritoController(),
      onNavSelect: onNavSelect,
      empleadoDeLaSesion: empleadoDeLaSesion,
    ),
  );
  await tester.pumpAndSettle();
}

Recurso _producto(int id, {int stock = 2}) => Recurso.fromJson({
  'id': id,
  'nombre': 'Producto $id',
  'precioVenta': 10,
  'stock': stock,
});

/// Encabezado de sección del catálogo agrupado (texto de 15 px): se
/// distingue así de la casilla del panel y del rótulo de la tarjeta.
Finder _encabezado(String nombre) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data == nombre && widget.style?.fontSize == 15,
);

void main() {
  group('CarritoController (unidad)', () {
    test('agregar suma unidades, total y desbloquea el badge', () {
      final carrito = CarritoController();
      carrito.agregar(_producto(1, stock: 10));
      carrito.agregar(_producto(1, stock: 10), cantidad: 2);

      expect(carrito.unidades, 3);
      expect(carrito.cantidadDe(1), 3);
      expect(carrito.total, 30.0);
      expect(carrito.vacio, isFalse);
    });

    test('nunca supera el stock disponible', () {
      final carrito = CarritoController();
      for (var i = 0; i < 10; i++) {
        carrito.agregar(_producto(1)); // stock 2
      }
      expect(carrito.cantidadDe(1), 2);

      carrito.agregar(_producto(1), cantidad: 50);
      expect(carrito.cantidadDe(1), 2);
    });

    test('un producto sin stock no entra al carrito', () {
      final carrito = CarritoController();
      carrito.agregar(
        Recurso.fromJson({'id': 7, 'nombre': 'Agotado', 'stock': 0}),
      );
      expect(carrito.vacio, isTrue);
    });

    test('bajar la cantidad a 0 retira la línea y vaciar limpia todo', () {
      final carrito = CarritoController();
      carrito.agregar(_producto(1));
      carrito.agregar(_producto(2));

      carrito.cambiarCantidad(1, -1);
      expect(carrito.contiene(1), isFalse);
      expect(carrito.unidades, 1);

      carrito.vaciar();
      expect(carrito.vacio, isTrue);
      expect(carrito.total, 0);
    });
  });

  group('catálogo: vitrina y filtros', () {
    testWidgets('pinta las tarjetas, el índice y el panel de filtros', (
      tester,
    ) async {
      await _abrirCatalogo(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Catálogo (4)'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Vitamina C 1000mg'), findsOneWidget);
      // Índice de categorías con conteos.
      expect(find.text('Todas (4)'), findsOneWidget);
      expect(find.text('Analgésicos (2)'), findsOneWidget);
      expect(find.text('Vitaminas (2)'), findsOneWidget);
      // Secciones del panel lateral (la del sidebar también dice Categorías).
      expect(find.text('Disponibilidad'), findsOneWidget);
      expect(find.text('Precio'), findsOneWidget);
      expect(find.text('Categorías'), findsNWidgets(2));
    });

    testWidgets('el buscador estrecha los resultados', (tester) async {
      await _abrirCatalogo(tester);

      await tester.enterText(find.byType(TextField).first, 'ibupro');
      await tester.pumpAndSettle();

      expect(find.text('Ibuprofeno 400mg'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsNothing);
      expect(find.text('Catálogo (1)'), findsOneWidget);
    });

    testWidgets('la casilla de categoría filtra el grid', (tester) async {
      await _abrirCatalogo(tester);

      await tester.tap(find.text('Analgésicos (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Ibuprofeno 400mg'), findsOneWidget);
      expect(find.text('Vitamina C 1000mg'), findsNothing);
      expect(find.text('Catálogo (2)'), findsOneWidget);

      // Desmarcarla (o pulsar "Todas") restaura la vitrina completa.
      await tester.tap(find.text('Todas (4)'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo (4)'), findsOneWidget);
    });

    testWidgets('la casilla de disponibilidad esconde lo que no aplica', (
      tester,
    ) async {
      await _abrirCatalogo(tester);

      await tester.tap(find.text('Agotados (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Antiséptico topical'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsNothing);
      expect(find.text('Catálogo (1)'), findsOneWidget);
    });

    testWidgets('el precio mínimo/máximo recorta por rango', (tester) async {
      await _abrirCatalogo(tester);

      // Índice 0 = buscador; 1 y 2 = los campos "Desde" y "Hasta".
      await tester.enterText(find.byType(TextField).at(1), '20');
      await tester.pumpAndSettle();

      expect(find.text('Vitamina C 1000mg'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsNothing);

      // Rango vacío (20–22 no contiene ningún precio): sin coincidencias.
      await tester.enterText(find.byType(TextField).at(2), '22');
      await tester.pumpAndSettle();
      expect(find.text('Catálogo (0)'), findsOneWidget);
      expect(
        find.text('Ningún producto coincide con los filtros aplicados'),
        findsOneWidget,
      );

      // Limpiar filtros restaura la vitrina.
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo (4)'), findsOneWidget);
    });

    testWidgets('agrupar por categoría pinta un índice con encabezados', (
      tester,
    ) async {
      await _abrirCatalogo(tester);

      // Antes: no hay encabezados de sección (solo casillas y tarjetas).
      expect(_encabezado('Analgésicos'), findsNothing);

      await tester.tap(find.text('Por categoría'));
      await tester.pumpAndSettle();

      // Después: una sección por categoría con su encabezado.
      expect(_encabezado('Analgésicos'), findsOneWidget);
      expect(_encabezado('Vitaminas'), findsOneWidget);
      expect(_encabezado('Sin categoría'), findsNothing);
    });
  });

  group('catálogo: paginación', () {
    /// Botón "siguiente página" de los controles de paginación.
    Finder siguiente() => find.descendant(
      of: find.byType(PaginationControls),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );

    testWidgets('solo pinta la página activa y ofrece ir a la siguiente', (
      tester,
    ) async {
      await _abrirCatalogo(tester, repositorio: _RepositorioFalso(extra: 26));

      expect(find.text('Catálogo (30)'), findsOneWidget);
      // 24 por página: no se inflan las 30 tarjetas de golpe.
      expect(find.byType(ProductoTarjeta), findsNWidgets(24));
      expect(find.text('Mostrando 1–24 de 30 productos'), findsOneWidget);

      await tester.ensureVisible(siguiente());
      await tester.tap(siguiente());
      await tester.pumpAndSettle();

      expect(find.text('Mostrando 25–30 de 30 productos'), findsOneWidget);
      expect(find.byType(ProductoTarjeta), findsNWidgets(6));
      expect(find.text('Producto 125'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsNothing);
    });

    testWidgets('buscar desde la 2ª página vuelve a la primera', (
      tester,
    ) async {
      await _abrirCatalogo(tester, repositorio: _RepositorioFalso(extra: 26));

      await tester.ensureVisible(siguiente());
      await tester.tap(siguiente());
      await tester.pumpAndSettle();
      expect(find.text('Mostrando 25–30 de 30 productos'), findsOneWidget);

      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Paracetamol');
      await tester.pumpAndSettle();

      // Un resultado = una sola página: sin controles y desde el principio.
      expect(find.text('Catálogo (1)'), findsOneWidget);
      expect(find.byType(ProductoTarjeta), findsNWidgets(1));
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.byType(PaginationControls), findsNothing);
    });

    testWidgets('con una sola página no se muestran controles ni rango', (
      tester,
    ) async {
      await _abrirCatalogo(tester);

      expect(find.byType(PaginationControls), findsNothing);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Vitamina C 1000mg'), findsOneWidget);
    });
  });

  group('catálogo: carrito', () {
    testWidgets('agregar actualiza el botón del carrito y abre la hoja', (
      tester,
    ) async {
      final carrito = CarritoController();
      await _abrirCatalogo(tester, carrito: carrito);

      expect(find.text('Carrito'), findsOneWidget);
      await tester.tap(find.text('Agregar').first);
      await tester.pumpAndSettle();

      expect(carrito.unidades, 1);
      expect(find.text('Carrito (1)'), findsOneWidget);
      // La tarjeta pasa a contador de unidades.
      expect(find.text('1 en carrito'), findsOneWidget);

      await tester.tap(find.text('Carrito (1)'));
      await tester.pumpAndSettle();

      // El contenido vive en la hoja; la vitrina sigue debajo (por eso se
      // busca dentro del BottomSheet y no en toda la pantalla).
      final hoja = find.byType(BottomSheet);
      expect(
        find.descendant(of: hoja, matching: find.text('Tu carrito')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hoja, matching: find.text('Paracetamol 500mg')),
        findsOneWidget,
      );
      // El subtotal de la línea (13 px) y el total del carrito (18 px).
      expect(
        find.descendant(
          of: hoja,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == 'Bs 5.50' &&
                widget.style?.fontSize == 18,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hoja, matching: find.text('Generar orden')),
        findsOneWidget,
      );
    });

    testWidgets('las unidades del contador también llegan al stock tope', (
      tester,
    ) async {
      final carrito = CarritoController();
      await _abrirCatalogo(tester, carrito: carrito);

      await tester.tap(find.text('Agregar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar una unidad').first);
      await tester.pumpAndSettle();

      expect(carrito.cantidadDe(1), 2);
      expect(find.text('2 en carrito'), findsOneWidget);

      await tester.tap(find.byTooltip('Quitar una unidad').first);
      await tester.pumpAndSettle();
      expect(carrito.cantidadDe(1), 1);
    });

    testWidgets('generar orden envía el cuerpo y vacía el carrito', (
      tester,
    ) async {
      final carrito = CarritoController();
      Map<String, Object?>? enviado;
      _tamano(tester, const Size(420, 800));
      await tester.pumpWidget(
        _hoja(
          carrito: carrito,
          onGenerarOrden: (body) async {
            enviado = body;
            carrito.vaciar();
          },
        ),
      );
      await tester.pumpAndSettle();

      // Sin líneas no se puede generar nada.
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Tu carrito está vacío'), findsOneWidget);

      carrito.agregar(_producto(1));
      carrito.agregar(_producto(2, stock: 5), cantidad: 3);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generar orden'));
      await tester.pumpAndSettle();

      expect(enviado, isNotNull);
      final pagosEnviados = enviado!['pagos'] as List;
      expect((pagosEnviados.single as Map)['metodoPago'], 'EFECTIVO');
      expect(enviado!['items'], [
        {'productoId': 1, 'cantidad': 1},
        {'productoId': 2, 'cantidad': 3},
      ]);
      expect(carrito.vacio, isTrue);
      // La hoja se cierra sola al concretar la compra.
      expect(find.text('Generar orden'), findsNothing);
    });

    testWidgets('la caja elige cliente y manda directo al módulo de Ventas', (
      tester,
    ) async {
      final carrito = CarritoController();
      final repositorio = _RepositorioFalso();
      var destino = -1;

      await _abrirCatalogo(
        tester,
        repositorio: repositorio,
        carrito: carrito,
        onNavSelect: (indice) => destino = indice,
      );

      await tester.tap(find.text('Agregar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carrito (1)'));
      await tester.pumpAndSettle();

      // El selector de cliente forma parte de la caja.
      final hoja = find.byType(BottomSheet);
      expect(
        find.descendant(of: hoja, matching: find.text('Cliente')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: hoja, matching: find.text('— Cliente ocasional —')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('María Pérez'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: hoja, matching: find.text('Generar orden')),
      );
      // Se evita `pumpAndSettle`: la alerta de éxito lleva GIF (QuickAlert).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(repositorio.ultimaOrden, isNotNull);
      expect(repositorio.ultimaOrden!['clienteId'], 1);
      expect(repositorio.ultimaOrden!['nombreCliente'], 'María Pérez');
      final pagosOrden = repositorio.ultimaOrden!['pagos'] as List;
      expect((pagosOrden.single as Map)['metodoPago'], 'EFECTIVO');
      expect(carrito.vacio, isTrue);
      // La venta saltó al módulo de Ventas (posición de "Ventas" en navItems).
      expect(destino, navVentas);
    });

    testWidgets(
      'la caja crea un cliente desde el selector y lo deja elegido',
      (tester) async {
        final carrito = CarritoController();
        final repositorio = _RepositorioFalso();

        await _abrirCatalogo(
          tester,
          repositorio: repositorio,
          carrito: carrito,
        );

        await tester.tap(find.text('Agregar').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Carrito (1)'));
        await tester.pumpAndSettle();

        // Se abre el selector de cliente y se da de alta desde su pie.
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('— Cliente ocasional —'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nuevo cliente'));
        await tester.pumpAndSettle();

        // El alta abre su propia hoja con la ficha completa del cliente:
        // los seis campos de texto van por orden (nombre, apellido, CI...).
        final camposAlta = find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.byType(TextFormField),
        );
        await tester.enterText(camposAlta.at(0), 'Rosa');
        await tester.enterText(camposAlta.at(1), 'Ramos');
        await tester.enterText(camposAlta.at(2), '77123456');
        final crear = find.descendant(
          of: find.byType(BottomSheet).last,
          matching: find.widgetWithText(ElevatedButton, 'Crear'),
        );
        await tester.ensureVisible(crear);
        await tester.pumpAndSettle();
        await tester.tap(crear);
        await tester.pumpAndSettle();

        // El alta llegó a la API con la ficha entera y el selector se queda
        // con la nueva, mostrando «Nombre Apellido».
        expect(repositorio.ultimoCliente?['nombre'], 'Rosa');
        expect(repositorio.ultimoCliente?['apellido'], 'Ramos');
        expect(repositorio.ultimoCliente?['ci'], '77123456');
        expect(repositorio.ultimoCliente?['estado'], 'ACTIVO');
        expect(find.text('Rosa Ramos'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Y ya figura entre las opciones al volver a abrir la hoja.
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet).first,
            matching: find.text('Rosa Ramos'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(BottomSheet).last,
            matching: find.text('Rosa Ramos'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'la caja preselecciona el vendedor de la sesión y admite cambio',
      (tester) async {
        final carrito = CarritoController();
        final repositorio = _RepositorioFalso();

        // Sesión con un empleado vinculado (Ana Torres, id 7).
        await _abrirCatalogo(
          tester,
          repositorio: repositorio,
          carrito: carrito,
          empleadoDeLaSesion: 7,
        );

        await tester.tap(find.text('Agregar').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Carrito (1)'));
        await tester.pumpAndSettle();

        final hoja = find.byType(BottomSheet);
        expect(
          find.descendant(of: hoja, matching: find.text('Vendedor')),
          findsOneWidget,
        );
        // Sale marcada la cuenta conectada…
        expect(
          find.descendant(of: hoja, matching: find.text('Ana Torres')),
          findsOneWidget,
        );

        // …y se puede cambiar a otro vendedor.
        await tester.tap(
          find.descendant(of: hoja, matching: find.text('Ana Torres')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rosa Gómez'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: hoja, matching: find.text('Rosa Gómez')),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(of: hoja, matching: find.text('Generar orden')),
        );
        // Se evita `pumpAndSettle`: la alerta de éxito lleva GIF (QuickAlert).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        // Lo que llega a `POST /ordenes` es el vendedor elegido.
        expect(repositorio.ultimaOrden, isNotNull);
        expect(repositorio.ultimaOrden!['empleadoId'], 8);
      },
    );
  });

  group('catálogo: responsivo', () {
    test('el sidebar incluye el módulo y el bottom nav sigue mapeado', () {
      expect(navItems.map((item) => item.label), contains('Catálogo'));
      // Dashboard, Catálogo, Productos y Ventas: el orden del bottom nav.
      expect(bottomNavIndices(null), [0, 2, 1, 4]);
    });

    for (final tamano in const [
      (Size(1200, 1000), 'desktop'),
      (Size(900, 900), 'tablet'),
      (Size(600, 800), 'móvil'),
      (Size(360, 800), 'móvil estrecho'),
    ]) {
      testWidgets('${tamano.$2} (${tamano.$1.width.toInt()}px)', (
        tester,
      ) async {
        await _abrirCatalogo(tester, tamano: tamano.$1);

        expect(tester.takeException(), isNull);
        expect(find.text('Catálogo (4)'), findsOneWidget);

        final esDesktop = tamano.$1.width >= 1100;
        expect(find.byType(Sidebar), esDesktop ? findsOneWidget : findsNothing);
        expect(
          find.byType(BottomNavigationBar),
          esDesktop ? findsNothing : findsOneWidget,
        );
      });
    }

    testWidgets('< 700: los filtros se abren en una hoja modal', (
      tester,
    ) async {
      await _abrirCatalogo(tester, tamano: const Size(600, 800));

      expect(find.text('Filtros'), findsOneWidget);

      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Disponibilidad'), findsOneWidget);
      expect(find.text('Agotados (1)'), findsOneWidget);
    });

    testWidgets('< 700: la hoja responde al precio y a las casillas', (
      tester,
    ) async {
      await _abrirCatalogo(tester, tamano: const Size(600, 800));
      expect(find.text('Catálogo (4)'), findsOneWidget);

      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();

      // "Hasta 6": el slider, sus etiquetas y la vitrina se enteran
      // (regresión: la hoja quedaba congelada y siempre enseñaba el tope).
      await tester.enterText(find.byType(TextField).at(2), '6');
      await tester.pumpAndSettle();

      expect(find.text('Bs 6.00'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Ibuprofeno 400mg'), findsNothing);
      expect(find.text('Catálogo (4)'), findsNothing);

      // La casilla refleja el toque mientras la hoja sigue abierta.
      await tester.tap(find.text('Agotados (1)'));
      await tester.pumpAndSettle();

      final casilla = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('Agotados (1)'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(casilla.value, isTrue);
    });

    testWidgets('< 700: el índice de categorías es un carrusel horizontal', (
      tester,
    ) async {
      await _abrirCatalogo(tester, tamano: const Size(600, 800));

      final chipTodas = find.text('Todas (4)');
      expect(chipTodas, findsOneWidget);
      expect(
        find.ancestor(of: chipTodas, matching: find.byType(ListView)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: chipTodas, matching: find.byType(Wrap)),
        findsNothing,
      );
      // Táctil: solo deslizado, sin flechas.
      expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    });

    testWidgets('>= 700: el panel de filtros acompaña al grid', (tester) async {
      await _abrirCatalogo(tester);

      // Los filtros van en el panel lateral: no existe el botón de hoja.
      expect(find.widgetWithText(ElevatedButton, 'Filtros'), findsNothing);
      expect(find.text('Agotados (1)'), findsOneWidget);
    });

    testWidgets('>= 700: el índice de categorías también es carrusel', (
      tester,
    ) async {
      await _abrirCatalogo(tester);

      final chipTodas = find.text('Todas (4)');
      expect(chipTodas, findsOneWidget);
      expect(
        find.ancestor(of: chipTodas, matching: find.byType(ListView)),
        findsOneWidget,
      );
      expect(
        find.ancestor(of: chipTodas, matching: find.byType(Wrap)),
        findsNothing,
      );
      // PC (no táctil): flechas laterales para avanzar con el ratón.
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });
  });
}
