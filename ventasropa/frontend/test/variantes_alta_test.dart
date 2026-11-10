import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/productos_page.dart';
import 'package:ventas/presentation/widgets/variantes_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Catálogo en memoria: los catálogos de tallas/colores **arrancan vacíos**
/// (las migraciones dejaron de sembrar datos de ejemplo) y cada `POST` se
/// queda con el registro, como la API.
class _CatalogoFalso implements RecursoRepository {
  final Map<String, List<Recurso>> _listados = {
    'productos': <Recurso>[],
    'categorias': [
      Recurso.fromJson({'id': 1, 'nombre': 'Ropa'}),
    ],
    'proveedores': [
      Recurso.fromJson({'id': 1, 'nombre': 'Textil Andina'}),
    ],
    'tallas': <Recurso>[],
    'colores': <Recurso>[],
  };

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
    return ListadoRecurso(
      total: fuente.length,
      items: fuente.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoCuerpo = body;
    final creado = Recurso.fromJson({
      'id': _listados[ruta]!.length + 10,
      ...body,
    });
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

void _tamano(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _sin(int _) {}

Widget _productos({required RecursoRepository repositorio}) {
  final crud = Crud(repository: repositorio);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProductosController>.value(
        value: ProductosController(crud),
      ),
      ChangeNotifierProvider<CategoriasController>.value(
        value: CategoriasController(crud),
      ),
      ChangeNotifierProvider<MarcasController>.value(
        value: MarcasController(crud),
      ),
      ChangeNotifierProvider<ProveedoresController>.value(
        value: ProveedoresController(crud),
      ),
      ChangeNotifierProvider<TallasController>.value(
        value: TallasController(crud),
      ),
      ChangeNotifierProvider<ColoresController>.value(
        value: ColoresController(crud),
      ),
    ],
    child: MaterialApp(home: ProductosPage(selectedNav: 1, onNavSelect: _sin)),
  );
}

/// Hoja de opciones del desplegable cuyo botón de creación es [boton]: el
/// formulario y su selector son dos hoja separadas, y solo la de opciones
/// lleva ese botón.
Finder _hojaDeOpciones(String boton) =>
    find.ancestor(of: find.text(boton), matching: find.byType(BottomSheet));

/// Abre el selector de la fila [clave], crea [nombre] con [boton] y espera a
/// que la hoja se cierre con el valor elegido.
Future<void> _crearEnSelector(
  WidgetTester tester,
  Key clave,
  String boton,
  String nombre,
) async {
  final campo = find.byKey(clave);
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: campo, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();

  final crear = find.text(boton);
  expect(crear, findsOneWidget);
  await tester.ensureVisible(crear);
  await tester.tap(crear);
  await tester.pumpAndSettle();

  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    nombre,
  );
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Crear')),
  );
  await tester.pumpAndSettle();

  // La hoja de opciones se cierra al crear.
  expect(crear, findsNothing);
}

/// Abre el selector de la fila [clave] y elige [valor] de la lista ya
/// existente.
Future<void> _elegirEnSelector(
  WidgetTester tester,
  Key clave,
  String boton,
  String valor,
) async {
  final campo = find.byKey(clave);
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: campo, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();

  final opcion = find.descendant(
    of: _hojaDeOpciones(boton),
    matching: find.text(valor),
  );
  expect(opcion, findsOneWidget);
  await tester.ensureVisible(opcion);
  await tester.tap(opcion);
  await tester.pumpAndSettle();
}

/// Rellena lo mínimo del formulario para que la validación llegue hasta las
/// filas de variantes: nombre, los dos precios, el stock inicial y los tres
/// selectores obligatorios de la pestaña «Obligatorio» (categoría,
/// proveedor, estado). Con [stock] en `false` se deja vacío para comprobar
/// que el alta queda bloqueada.
Future<void> _rellenaProducto(WidgetTester tester, {bool stock = true}) async {
  await tester.enterText(
    find.byType(TextFormField).at(0),
    'Pantalón mezclillo',
  );
  await tester.enterText(find.byType(TextFormField).at(1), '59.90'); // compra
  await tester.enterText(find.byType(TextFormField).at(2), '89.90'); // venta
  if (stock) {
    // Por etiqueta, no por índice: con filas de variantes ya montadas, el
    // índice del stock se desplaza.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Stock inicial *'),
      '10',
    );
  }

  for (final par in const [
    ('categoriaId', 'Ropa'),
    ('proveedorId', 'Textil Andina'),
    ('estado', 'Disponible'),
  ]) {
    final selector = find.byKey(ValueKey('${par.$1}#0'));
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: selector, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(par.$2));
    await tester.pumpAndSettle();
  }
}

Future<void> _abrirAlta(WidgetTester tester) async {
  await tester.tap(find.text('Nuevo Producto'));
  await tester.pumpAndSettle();
}

void main() {
  group('alta de producto: tallas y colores escritos a mano', () {
    setUp(FilaVarianteAlta.reiniciarIds);
    testWidgets('crea la talla y el color desde el propio formulario', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      // Los catálogos arrancan vacíos: ni «S» ni «Negro» existen de fábrica.
      expect(find.text('S'), findsNothing);
      expect(find.text('Negro'), findsNothing);
      expect(
        find.text(
          'Sin filas todavía: si la prenda no tiene tallas (medias, '
          'gorros...), déjalo así y se guardará como «Única». ¿Sí '
          'tiene? Añade la primera combinación.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Añadir talla y color'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('talla-1')), findsOneWidget);

      await _crearEnSelector(
        tester,
        const ValueKey('talla-1'),
        'Nueva talla',
        'S',
      );
      await _crearEnSelector(
        tester,
        const ValueKey('color-1'),
        'Nuevo color',
        'Negro',
      );
      await tester.enterText(find.byKey(const ValueKey('cantidad-1')), '5');
      await tester.pumpAndSettle();

      // La fila queda elegida y el catálogo ya tiene los dos registros nuevos.
      expect(find.text('S'), findsOneWidget);
      expect(find.text('Negro'), findsOneWidget);
      expect(repositorio._listados['tallas'], hasLength(1));
      expect(repositorio._listados['colores'], hasLength(1));

      await _rellenaProducto(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repositorio.ultimaRuta, 'productos');
      expect(repositorio.ultimoCuerpo!['variantes'], [
        {'talla': 'S', 'color': 'Negro', 'stock': 5},
      ]);
    });

    testWidgets('sin ninguna fila crea el producto sin tallas (Única)', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _rellenaProducto(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
      await tester.pumpAndSettle();

      // La lista vacía viaja al backend, que le crea la variante única
      // «Única» / «Único» (prenda sin tallas: medias, gorros...) con el
      // stock inicial introducido.
      expect(tester.takeException(), isNull);
      expect(repositorio.ultimaRuta, 'productos');
      expect(repositorio.ultimoCuerpo!['variantes'], isEmpty);
      expect(repositorio.ultimoCuerpo!['stock'], 10);
    });

    testWidgets('sin stock inicial no deja crear el producto', (tester) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _rellenaProducto(tester, stock: false);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
      await tester.pumpAndSettle();

      // El stock es obligatorio en el alta: sin él no se envía nada.
      expect(find.text('Este campo es obligatorio'), findsOneWidget);
      expect(repositorio.ultimaRuta, isNull);
    });

    testWidgets('una combinación repetida en dos filas se rechaza', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await tester.tap(find.text('Añadir talla y color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir talla y color'));
      await tester.pumpAndSettle();

      await _crearEnSelector(
        tester,
        const ValueKey('talla-1'),
        'Nueva talla',
        'S',
      );
      await _crearEnSelector(
        tester,
        const ValueKey('color-1'),
        'Nuevo color',
        'Negro',
      );
      // La segunda fila elige los mismos, ya dados de alta en la primera.
      await _elegirEnSelector(
        tester,
        const ValueKey('talla-2'),
        'Nueva talla',
        'S',
      );
      await _elegirEnSelector(
        tester,
        const ValueKey('color-2'),
        'Nuevo color',
        'Negro',
      );

      await _rellenaProducto(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            'La talla «S» con el color «Negro» ya está en otra fila.',
          ),
        ),
        findsOneWidget,
      );
      expect(repositorio.ultimaRuta, isNot('productos'));
    });
  });
}
