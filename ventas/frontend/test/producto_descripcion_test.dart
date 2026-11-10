import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ventas/core/widgets/ajustes_scope.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/productos_page.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';

/// Catálogo en memoria del módulo de producto: los cuatro desplegables y el
/// `POST` real (se queda con el registro y devuelve lo que manda el formulario).
class _CatalogoFalso implements RecursoRepository {
  final Map<String, List<Recurso>> _listados = {
    'productos': [],
    'categorias': [
      Recurso.fromJson({'id': 1, 'nombre': 'Analgésicos'}),
    ],
    'presentaciones': [
      Recurso.fromJson({'id': 1, 'nombre': 'Caja'}),
    ],
    'marcas': [
      Recurso.fromJson({'id': 1, 'nombre': 'Samsung', 'estado': 'ACTIVO'}),
    ],
    'proveedores': [
      Recurso.fromJson({'id': 1, 'nombre': 'Distribuidora Sur'}),
    ],
    'unidades': [
      Recurso.fromJson({
        'id': 1,
        'codigo': 'KG',
        'nombre': 'Kilogramo',
        'tipo': 'PESO',
        'decimales': 3,
        'estado': 'ACTIVO',
      }),
    ],
  };

  /// Último alta recibida, para las aserciones.
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

void _tamano(WidgetTester tester, [Size tamano = const Size(1400, 2000)]) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _sin(int _) {}

/// Módulo de producto con sus cinco controllers. Los ajustes precargan los
/// dos desplegables obligatorios (unidad y estado) para que el alta no dependa
/// de elegirlos a mano en cada test.
Widget _productos({required RecursoRepository repositorio}) {
  final crud = Crud(repository: repositorio);
  return AjustesScope(
    valores: const {
      'defecto.producto.unidad': 'KG',
      'defecto.producto.estado': 'DISPONIBLE',
    },
    child: MultiProvider(
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
      child: MaterialApp(
        home: ProductosPage(selectedNav: 1, onNavSelect: _sin),
      ),
    ),
  );
}

/// El campo de texto cuyo rótulo es [etiqueta] (el rótulo vive dentro de su
/// propio `TextFormField`).
Finder _campoTexto(String etiqueta) => find.ancestor(
  of: find.text(etiqueta),
  matching: find.byType(TextFormField),
);

/// Líneas que admite el campo de texto [campo] (su `TextField` interno).
int _maximasLineas(WidgetTester tester, Finder campo) => tester
    .widget<TextField>(
      find.descendant(of: campo, matching: find.byType(TextField)),
    )
    .maxLines!;

/// Abre el alta de producto.
Future<void> _abrirAlta(WidgetTester tester) async {
  await tester.tap(find.text('Nuevo Producto'));
  await tester.pumpAndSettle();
}

/// Elige [opcion] en el desplegable cuyo rótulo es [etiqueta], dentro del
/// formulario abierto.
Future<void> _elige(WidgetTester tester, String etiqueta, String opcion) async {
  final campo = find.ancestor(
    of: find.text(etiqueta),
    matching: find.byType(DesplegableBuscable),
  );
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(campo);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, opcion));
  await tester.pumpAndSettle();
}

/// Rellena lo de la pestaña «Obligatorio»: 0 nombre, 1 precio de compra,
/// 2 precio de venta, 3 ganancia % (se deja vacío) y 4 stock. «Unidad» y
/// «Estado» vienen ya precargados por los ajustes, y los tres catálogos
/// obligatorios (categoría, presentación y marca) se eligen a mano.
Future<void> _rellenaObligatorio(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Ibuprofeno 600 mg');
  await tester.enterText(find.byType(TextFormField).at(1), '1.20');
  await tester.enterText(find.byType(TextFormField).at(2), '2.50');
  await tester.enterText(find.byType(TextFormField).at(4), '12');
  await tester.pump();
  await _elige(tester, 'Categoría *', 'Analgésicos');
  await _elige(tester, 'Presentación *', 'Caja');
  await _elige(tester, 'Marca *', 'Samsung');
}

/// Salta a la pestaña «Opcional» y guarda.
Future<void> _guardaDesdeOpcional(WidgetTester tester) async {
  await tester.tap(find.text('Opcional'));
  await tester.pumpAndSettle();
  final guardar = find.widgetWithText(ElevatedButton, 'Crear');
  await tester.ensureVisible(guardar);
  await tester.pumpAndSettle();
  await tester.tap(guardar);
  await tester.pumpAndSettle();
}

void main() {
  group('campo «Descripción» del producto', () {
    testWidgets('vive en la pestaña Opcional y admite cuatro líneas', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: _CatalogoFalso()));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      // En «Obligatorio» no aparece: es texto libre opcional.
      expect(find.text('Descripción'), findsNothing);

      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      final campo = _campoTexto('Descripción');
      expect(campo, findsOneWidget);
      expect(_maximasLineas(tester, campo), 4, reason: 'varias líneas');
      expect(tester.takeException(), isNull);
    });

    testWidgets('el texto que se teclea no pasa de 255 caracteres', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: _CatalogoFalso()));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      await tester.enterText(_campoTexto('Descripción'), 'x' * 300);
      await tester.pump();

      final texto = tester
          .widget<TextFormField>(_campoTexto('Descripción'))
          .controller!
          .text;
      expect(texto, hasLength(255));
      expect(tester.takeException(), isNull);
    });

    testWidgets('al crear, la descripción viaja en el cuerpo', (tester) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _rellenaObligatorio(tester);
      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();
      await tester.enterText(_campoTexto('Descripción'), 'Jarabe para la tos');
      await _guardaDesdeOpcional(tester);

      expect(repositorio.ultimoCuerpo, isNotNull);
      expect(repositorio.ultimoCuerpo!['descripcion'], 'Jarabe para la tos');
      // El resto del formulario sigue llegando con ella.
      expect(repositorio.ultimoCuerpo!['nombre'], 'Ibuprofeno 600 mg');
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin descripción el cuerpo la manda en null', (tester) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();
      await _abrirAlta(tester);

      await _rellenaObligatorio(tester);
      await _guardaDesdeOpcional(tester);

      expect(repositorio.ultimoCuerpo, isNotNull);
      expect(repositorio.ultimoCuerpo!.containsKey('descripcion'), isTrue);
      expect(repositorio.ultimoCuerpo!['descripcion'], isNull);
    });

    testWidgets('al editar se precarga la del registro', (tester) async {
      final repositorio = _CatalogoFalso();
      repositorio._listados['productos']!.add(
        Recurso.fromJson({
          'id': 7,
          'nombre': 'Ibuprofeno 600 mg',
          'precioVenta': 2.5,
          'stock': 12,
          'unidad': 'KG',
          'estado': 'DISPONIBLE',
          'descripcion': 'Jarabe para la tos',
        }),
      );
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      final editar = find.byIcon(Icons.edit_outlined);
      expect(editar, findsWidgets);
      await tester.ensureVisible(editar.first);
      await tester.pumpAndSettle();
      await tester.tap(editar.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(_campoTexto('Descripción'))
            .controller!
            .text,
        'Jarabe para la tos',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
