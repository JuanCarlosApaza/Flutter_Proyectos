import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/productos_page.dart';

/// Catálogo en memoria que se queda con el último alta, para comprobar lo
/// que viaja (y lo que no) al backend.
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

Future<void> _abrirAlta(WidgetTester tester) async {
  await tester.tap(find.text('Nuevo Producto'));
  await tester.pumpAndSettle();
}

/// Texto escrito en el campo de texto [indice] del formulario.
///
/// Orden en la pestaña «Obligatorio»: 0 nombre, 1 precio de compra, 2 precio
/// de venta, 3 ganancia % y después la cantidad de cada fila de variantes
/// («Código», «Descripción»... viven en la pestaña «Opcional» y no están
/// montados mientras no se abra).
String _textoEn(WidgetTester tester, int indice) => tester
    .widget<TextFormField>(find.byType(TextFormField).at(indice))
    .controller!
    .text;

Future<void> _escribe(WidgetTester tester, int indice, String texto) async {
  await tester.enterText(find.byType(TextFormField).at(indice), texto);
  await tester.pump();
}

/// Elige [valor] en el selector `campo#0` del formulario (categoría,
/// proveedor o estado).
Future<void> _elige(WidgetTester tester, String campo, String valor) async {
  final selector = find.byKey(ValueKey('$campo#0'));
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: selector, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(valor));
  await tester.pumpAndSettle();
}

/// Crea la talla y el color de la única fila del formulario.
Future<void> _creaTallaYColor(WidgetTester tester) async {
  await tester.tap(find.text('Añadir talla y color'));
  await tester.pumpAndSettle();

  for (final par in const [
    (Key('talla-1'), 'Nueva talla', 'M'),
    (Key('color-1'), 'Nuevo color', 'Rojo'),
  ]) {
    final campo = find.byKey(par.$1);
    await tester.ensureVisible(campo);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: campo, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(par.$2));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      par.$3,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Crear'),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// Estado del producto (campo obligatorio de la pestaña «Obligatorio»).
Future<void> _eligeEstado(WidgetTester tester) =>
    _elige(tester, 'estado', 'Disponible');

void main() {
  group('porcentaje de ganancia junto al precio de venta', () {
    testWidgets('el % calcula el precio de venta sobre el precio de compra', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: _CatalogoFalso()));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _escribe(tester, 1, '80'); // precio de compra
      await _escribe(tester, 3, '25'); // ganancia %

      expect(_textoEn(tester, 2), '100'); // 80 × 1,25
    });

    testWidgets('escribir el precio a mano deja el % con ese margen', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: _CatalogoFalso()));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _escribe(tester, 1, '80');
      await _escribe(tester, 2, '100');

      expect(_textoEn(tester, 3), '25');

      // Y precio y % siguen hablando: el precio sigue al costo mientras
      // haya un porcentaje escrito.
      await _escribe(tester, 1, '90');
      expect(_textoEn(tester, 2), '112.5');
      expect(_textoEn(tester, 3), '25');
    });

    testWidgets('un % con decimales redondea el precio a 2 cifras', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: _CatalogoFalso()));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _escribe(tester, 1, '89.90');
      await _escribe(tester, 3, '12.5');

      expect(_textoEn(tester, 2), '101.14'); // 89,90 × 1,125 = 101,1375
    });

    testWidgets('el % no se guarda si falta el precio de compra', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _escribe(tester, 0, 'Pantalón mezclillo');
      await _escribe(tester, 2, '100');
      await _escribe(tester, 3, '25'); // sin precio de compra no calcula
      await _eligeEstado(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
      await tester.pumpAndSettle();

      expect(
        find.text('Escribe el precio de compra: sobre él se calcula este %'),
        findsWidgets,
      );
      expect(repositorio.ultimaRuta, isNull);
    });

    testWidgets('la calculadora es de pantalla: no viaja al backend', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _escribe(tester, 0, 'Pantalón mezclillo');
      await _escribe(tester, 1, '80'); // precio de compra
      await _escribe(tester, 3, '25'); // → precio de venta 100
      expect(_textoEn(tester, 2), '100');

      await _creaTallaYColor(tester);
      // 4 = cantidad de la fila creada (tras nombre, compra, venta y %);
      // 5 = stock inicial, obligatorio en el alta.
      await _escribe(tester, 4, '3');
      await _escribe(tester, 5, '10');
      // Categoría y proveedor son obligatorios en el alta.
      await _elige(tester, 'categoriaId', 'Ropa');
      await _elige(tester, 'proveedorId', 'Textil Andina');
      await _eligeEstado(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repositorio.ultimaRuta, 'productos');
      expect(repositorio.ultimoCuerpo!['precioVenta'], 100);
      expect(repositorio.ultimoCuerpo!.containsKey('gananciaPct'), isFalse);
    });
  });
}
