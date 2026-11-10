import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ventas/core/validation/reglas.dart';
import 'package:ventas/core/widgets/sesion_scope.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/entities/usuario.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/carrito_controller.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/productos_page.dart';
import 'package:ventas/presentation/pages/unidades_page.dart';
import 'package:ventas/presentation/widgets/carrito_panel.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:ventas/presentation/widgets/opciones_formulario.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';

// ---------------------------------------------------------------------------
// Falsos
// ---------------------------------------------------------------------------

/// Catálogo en memoria: `GET /unidades` devuelve la semilla y el `POST`
/// se queda con el cuerpo para las aserciones.
class _CatalogoUnidades implements RecursoRepository {
  _CatalogoUnidades({bool semillaUnidades = true}) {
    if (semillaUnidades) {
      _listados['unidades'] = [
        _unidad(
          id: 1,
          codigo: 'KG',
          nombre: 'Kilogramo',
          tipo: 'PESO',
          decimales: 3,
        ),
        _unidad(
          id: 2,
          codigo: 'CAJA',
          nombre: 'Caja',
          tipo: 'UNIDAD',
          decimales: 0,
        ),
        _unidad(
          id: 3,
          codigo: 'LT',
          nombre: 'Litro',
          tipo: 'VOLUMEN',
          decimales: 3,
          estado: 'INACTIVO',
        ),
      ];
    }
  }

  final Map<String, List<Recurso>> _listados = {};

  /// Último alta recibida, para las aserciones.
  String? ultimaRuta;
  Map<String, Object?>? ultimoCuerpo;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    final fuente = _listados[recurso] ?? const <Recurso>[];
    var items = fuente;
    if (estado != null) {
      items = items.where((r) => r.texto('estado') == estado).toList();
    }
    if (q != null && q.isNotEmpty) {
      final texto = q.toLowerCase();
      items = items
          .where(
            (r) =>
                r.texto('codigo').toLowerCase().contains(texto) ||
                r.texto('nombre').toLowerCase().contains(texto),
          )
          .toList();
    }
    return ListadoRecurso(
      total: items.length,
      items: items.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoCuerpo = body;
    final creado = Recurso.fromJson({'id': 99, ...body});
    _listados[ruta]!.add(creado);
    return creado;
  }

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

Recurso _unidad({
  required int id,
  required String codigo,
  required String nombre,
  required String tipo,
  required int decimales,
  String estado = 'ACTIVO',
}) => Recurso.fromJson({
  'id': id,
  'codigo': codigo,
  'nombre': nombre,
  'tipo': tipo,
  'decimales': decimales,
  'estado': estado,
});

/// Controlador de unidades ya cargado (sin red): de él beben el formulario
/// de producto y el carrito.
UnidadesController _unidadesCargadas([List<Recurso>? semilla]) {
  final controlador = UnidadesController(Crud(repository: _CatalogoUnidades()));
  controlador.items =
      semilla ??
      [
        _unidad(
          id: 1,
          codigo: 'KG',
          nombre: 'Kilogramo',
          tipo: 'PESO',
          decimales: 3,
        ),
        _unidad(
          id: 2,
          codigo: 'CAJA',
          nombre: 'Caja',
          tipo: 'UNIDAD',
          decimales: 0,
        ),
        _unidad(
          id: 3,
          codigo: 'LT',
          nombre: 'Litro',
          tipo: 'VOLUMEN',
          decimales: 3,
        ),
      ];
  return controlador;
}

Recurso _producto({
  int id = 1,
  double stock = 12.75,
  String unidad = 'KG',
  double precio = 10,
}) => Recurso.fromJson({
  'id': id,
  'nombre': 'Arroz',
  'precioVenta': precio,
  'stock': stock,
  'unidad': unidad,
});

void _tamano(WidgetTester tester, [Size tamano = const Size(1200, 1400)]) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _sin(int _) {}

/// Página de unidades montada sobre su repositorio falso.
Widget _pagina({RecursoRepository? repositorio, List<String>? permisos}) {
  final crud = Crud(repository: repositorio ?? _CatalogoUnidades());
  final arbol = MultiProvider(
    providers: [
      ChangeNotifierProvider<UnidadesController>.value(
        value: UnidadesController(crud),
      ),
    ],
    child: MaterialApp(home: UnidadesPage(selectedNav: 11, onNavSelect: _sin)),
  );
  if (permisos == null) return arbol;
  return SesionScope(
    datos: DatosSesion(
      usuario: Usuario(
        id: 1,
        nombreUsuario: 'pruebas',
        nivelUsuario: 'CAJERO',
        permisos: permisos,
      ),
      cerrarSesion: () async {},
    ),
    child: arbol,
  );
}

/// Pinta solo la hoja del carrito (checkout aislado de la página).
Widget _hoja({required CarritoController carrito}) {
  return ChangeNotifierProvider<CarritoController>.value(
    value: carrito,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                mostrarCarrito(context, onGenerarOrden: (_) async {}),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

/// Módulo de productos con el catálogo de unidades que alimenta su
/// desplegable «Unidad de venta».
Widget _productos({RecursoRepository? repositorio}) {
  final crud = Crud(repository: repositorio ?? _CatalogoUnidades());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductosController>.value(
        value: ProductosController(crud),
      ),
      ChangeNotifierProvider<CategoriasController>.value(
        value: CategoriasController(crud),
      ),
      ChangeNotifierProvider<PresentacionesController>.value(
        value: PresentacionesController(crud),
      ),
      ChangeNotifierProvider<ProveedoresController>.value(
        value: ProveedoresController(crud),
      ),
      ChangeNotifierProvider<UnidadesController>.value(
        value: UnidadesController(crud),
      ),
      ChangeNotifierProvider<ColoresController>.value(
        value: ColoresController(crud),
      ),
      ChangeNotifierProvider<MarcasController>.value(
        value: MarcasController(crud),
      ),
    ],
    child: MaterialApp(home: ProductosPage(selectedNav: 1, onNavSelect: _sin)),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // 1. Catálogo: de dónde salen los decimales de cada cantidad
  // -------------------------------------------------------------------------
  group('UnidadesController', () {
    test('decimalesDe lee el catálogo de la BD (KG 3, CAJA 0)', () {
      expect(_unidadesCargadas().decimalesDe('KG'), 3);
      expect(_unidadesCargadas().decimalesDe('CAJA'), 0);
      expect(_unidadesCargadas().decimalesDe('LT'), 3);
    });

    test('decimalesDe recorta al rango que admite la columna (0..3)', () {
      final unidades = _unidadesCargadas([
        _unidad(
          id: 9,
          codigo: 'RARO',
          nombre: 'Raro',
          tipo: 'UNIDAD',
          decimales: 9,
        ),
      ]);
      expect(unidades.decimalesDe('RARO'), 3);
    });

    test(
      'sin catálogo cargado manda el respaldo: se fracciona o se cuenta',
      () {
        final vacias = UnidadesController(
          Crud(repository: _CatalogoUnidades()),
        );
        expect(vacias.decimalesDe('KG'), 3);
        expect(vacias.decimalesDe('GALON'), 3);
        expect(vacias.decimalesDe('CAJA'), 0);
        expect(vacias.decimalesDe('SOBRE'), 0);
        expect(vacias.decimalesDe(''), 0);
      },
    );

    test('porCodigo busca por la clave natural que viaja en el producto', () {
      final unidades = _unidadesCargadas();
      expect(unidades.porCodigo('KG')?.texto('nombre'), 'Kilogramo');
      expect(unidades.porCodigo('kg'), isNull);
      expect(unidades.porCodigo('NADA'), isNull);
    });

    test(
      'unidadesDe etiqueta con nombre y código y ordena por tipo/código',
      () {
        final opciones = unidadesDe(_unidadesCargadas().items);

        // El valor que viaja es el código, no el id de la fila, y el orden es
        // el mismo que el del listado de la API: por tipo (PESO, UNIDAD,
        // VOLUMEN…) y después por código.
        expect(opciones.map((o) => o.valor), ['KG', 'CAJA', 'LT']);
        expect(opciones.map((o) => o.etiqueta), [
          'Kilogramo (KG)',
          'Caja (CAJA)',
          'Litro (LT)',
        ]);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2. Carrito: cantidades fraccionadas con tope de stock exacto
  // -------------------------------------------------------------------------
  group('CarritoController fraccionado', () {
    test('agregar con stock fraccionado no trunca el tope', () {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());

      carrito.agregar(_producto(stock: 12.75));
      expect(carrito.cantidadDe(1), 1);

      // 12.750 KG disponibles: se pueden llevar 12.750, no se corta a 12.
      carrito.definirCantidad(1, 12.75);
      expect(carrito.cantidadDe(1), 12.75);

      // ...y el stock sigue siendo el tope.
      carrito.definirCantidad(1, 99);
      expect(carrito.cantidadDe(1), 12.75);
      expect(carrito.unidades, 12.75);
      expect(carrito.total, 127.5);
    });

    test('los botones ± se mueven al paso de la unidad', () {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());

      carrito.agregar(_producto());
      carrito.sumar(1);
      expect(carrito.cantidadDe(1), 1.25);
      carrito.sumar(1);
      expect(carrito.cantidadDe(1), 1.5);

      carrito.restar(1);
      expect(carrito.cantidadDe(1), 1.25);
      // Nunca por encima del stock.
      carrito.definirCantidad(1, 12.75);
      carrito.sumar(1);
      expect(carrito.cantidadDe(1), 12.75);
    });

    test('lo que se cuenta por envase solo admite enteros de paso', () {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());

      carrito.agregar(_producto(unidad: 'CAJA', stock: 5));
      carrito.sumar(1);
      expect(carrito.cantidadDe(1), 2);
      carrito.restar(1);
      expect(carrito.cantidadDe(1), 1);
      expect(
        LineaCarrito(productoId: 0, nombre: '', precio: 0, stock: 0).paso,
        1,
      );
    });

    test('una cantidad a cero retira la línea', () {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());

      carrito.agregar(_producto());
      carrito.definirCantidad(1, 0.25);
      expect(carrito.cantidadDe(1), 0.25);
      carrito.restar(1);

      expect(carrito.vacio, isTrue);
      expect(carrito.unidades, 0);
    });

    test('un producto agotado no entra al carrito', () {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());

      carrito.agregar(_producto(stock: 0));
      expect(carrito.vacio, isTrue);

      // Stock parcial (0.750 KG) sí cabe, con esa cantidad exacta.
      carrito.agregar(_producto(id: 2, stock: 0.75));
      expect(carrito.cantidadDe(2), 0.75);
    });

    test('el total y el badge no arrastran error binario', () {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());

      carrito.agregar(_producto(id: 1, precio: 0.1));
      carrito.agregar(_producto(id: 2, precio: 0.2));
      carrito.definirCantidad(1, 0.1);
      carrito.definirCantidad(2, 0.2);

      expect(cantidadTexto(carrito.unidades), '0.3');
      expect(cantidadTexto(carrito.total), '0.05');
      expect(redondearCantidad(0.1 + 0.2, 3), 0.3);
    });
  });

  // -------------------------------------------------------------------------
  // 3. Pantalla «Unidades»
  // -------------------------------------------------------------------------
  group('UnidadesPage', () {
    testWidgets('la tabla pinta código, nombre, tipo, decimales y estado', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_pagina());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // El encabezado lleva el contador de filas detrás: «… (3)».
      expect(
        find.textContaining('Gestión de Unidades de Medida'),
        findsOneWidget,
      );
      for (final texto in [
        'KG',
        'Kilogramo',
        'PESO',
        'CAJA',
        'Caja',
        'UNIDAD',
        'LT',
        'Litro',
        'VOLUMEN',
        'INACTIVO',
      ]) {
        expect(find.text(texto), findsWidgets, reason: 'falta «$texto»');
      }
      // Dos filtros de estado (más el «Todos») y el botón de alta.
      expect(find.text('Nueva Unidad'), findsOneWidget);
    });

    testWidgets('el alta envía código, tipo y decimales a /unidades', (
      tester,
    ) async {
      final repositorio = _CatalogoUnidades();
      _tamano(tester);
      await tester.pumpWidget(_pagina(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nueva Unidad'));
      await tester.pumpAndSettle();

      final formulario = find.byType(RecursoForm);
      expect(formulario, findsOneWidget);
      // El código solo existe al crear: es la clave que viaja en el producto.
      expect(
        find.descendant(of: formulario, matching: find.text('Código *')),
        findsOneWidget,
      );

      final campos = find.descendant(
        of: formulario,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(campos.at(0), 'tonelada');
      await tester.enterText(campos.at(1), 'Tonelada');
      await tester.enterText(campos.at(2), '3');

      // Tipo y estado son desplegables: se eligen en su hoja de opciones.
      final desplegables = find.descendant(
        of: formulario,
        matching: find.byType(DesplegableBuscable),
      );
      await tester.tap(desplegables.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Peso (KG, LB, ONZA)'));
      await tester.pumpAndSettle();

      await tester.tap(desplegables.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activo'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: formulario, matching: find.text('Crear')),
      );
      await tester.pumpAndSettle();

      expect(repositorio.ultimaRuta, 'unidades');
      expect(repositorio.ultimoCuerpo, {
        'codigo': 'tonelada',
        'nombre': 'Tonelada',
        'tipo': 'PESO',
        'decimales': 3,
        'estado': 'ACTIVO',
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('al editar el código no aparece (inmutable)', (tester) async {
      _tamano(tester);
      await tester.pumpWidget(_pagina());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      final formulario = find.byType(RecursoForm);
      expect(formulario, findsOneWidget);
      expect(
        find.descendant(of: formulario, matching: find.text('Editar unidad')),
        findsOneWidget,
      );
      // Sin campo de código: cambiarlo respondería 400 codigo_inmutable.
      expect(
        find.descendant(of: formulario, matching: find.text('Código *')),
        findsNothing,
      );
      // El resto de la ficha sí se edita.
      expect(
        find.descendant(of: formulario, matching: find.text('Nombre *')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: formulario, matching: find.text('Decimales *')),
        findsOneWidget,
      );
    });

    testWidgets('con solo `unidades.ver` la tabla se ve y no se da de alta', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_pagina(permisos: const ['unidades.ver']));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Gestión de Unidades de Medida'),
        findsOneWidget,
      );
      expect(find.text('KG'), findsWidgets);
      expect(find.text('Nueva Unidad'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('con `unidades.crear` el alta se ofrece', (tester) async {
      _tamano(tester);
      await tester.pumpWidget(
        _pagina(permisos: const ['unidades.ver', 'unidades.crear']),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nueva Unidad'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 4. Campo de cantidad del carrito
  // -------------------------------------------------------------------------
  group('carrito: campo de cantidad decimal', () {
    testWidgets('escribir una cantidad fraccionada fija la línea', (
      tester,
    ) async {
      final carrito = CarritoController(unidadesMedida: _unidadesCargadas());
      carrito.agregar(_producto());

      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_hoja(carrito: carrito));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // La hoja lleva más campos (el del cliente); el de la cantidad es el
      // único que arranca con la cantidad de la línea («1»).
      Finder campo(String texto) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (w) => w is TextFormField && w.controller?.text == texto,
        ),
      );
      expect(campo('1'), findsOneWidget);
      expect(find.text('KG'), findsOneWidget);

      await tester.enterText(campo('1'), '0.75');
      await tester.pumpAndSettle();
      expect(carrito.cantidadDe(1), 0.75);

      // Más que el stock → se recorta al tope.
      await tester.enterText(campo('0.75'), '99');
      await tester.pumpAndSettle();
      expect(carrito.cantidadDe(1), 12.75);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // 5. Formulario de producto: la unidad la decide el catálogo
  // -------------------------------------------------------------------------
  group('producto: el desplegable «Unidad de venta» sale del catálogo', () {
    testWidgets('ofrece las unidades de la BD, no la lista fija', (
      tester,
    ) async {
      _tamano(tester, const Size(1400, 1800));
      await tester.pumpWidget(_productos());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();

      final unidad = find.ancestor(
        of: find.text('Unidad de venta *'),
        matching: find.byType(DesplegableBuscable),
      );
      expect(unidad, findsOneWidget);
      await tester.ensureVisible(unidad);
      await tester.pumpAndSettle();
      await tester.tap(unidad);
      await tester.pumpAndSettle();

      // Semilla de la BD (KG, CAJA, LT): aparecen con su nombre y código.
      expect(find.text('Kilogramo (KG)'), findsOneWidget);
      expect(find.text('Caja (CAJA)'), findsOneWidget);
      expect(find.text('Litro (LT)'), findsOneWidget);
      // La lista fija de respaldo ya no pinta: ML no está en la semilla.
      expect(find.text('Mililitro (ML)'), findsNothing);

      await tester.tap(find.text('Kilogramo (KG)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kilogramo (KG)'), findsWidgets);
    });

    testWidgets('con el catálogo vacío se cae a la lista fija', (tester) async {
      _tamano(tester, const Size(1400, 1800));
      await tester.pumpWidget(
        _productos(repositorio: _CatalogoUnidades(semillaUnidades: false)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();

      final unidad = find.ancestor(
        of: find.text('Unidad de venta *'),
        matching: find.byType(DesplegableBuscable),
      );
      await tester.ensureVisible(unidad);
      await tester.pumpAndSettle();
      await tester.tap(unidad);
      await tester.pumpAndSettle();

      expect(find.text('Unidad (UN)'), findsOneWidget);
      expect(find.text('Mililitro (ML)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
