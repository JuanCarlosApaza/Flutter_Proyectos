import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/productos_page.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Catálogo en memoria: los desplegables del formulario de producto y su
/// `POST` real (crea, se queda con el registro y lo devuelve, como la API).
class _CatalogoFalso implements RecursoRepository {
  final Map<String, List<Recurso>> _listados = {
    'productos': [],
    'categorias': [
      Recurso.fromJson({'id': 1, 'nombre': 'Analgésicos'}),
    ],
    'presentaciones': [
      Recurso.fromJson({'id': 1, 'nombre': 'Caja'}),
    ],
    'proveedores': [
      Recurso.fromJson({'id': 1, 'nombre': 'Distribuidora Sur'}),
    ],
    // Catálogos de tallas/colores del campo de variantes: arrancan vacíos
    // (las migraciones ya no siembran datos de ejemplo).
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

void _tamano(WidgetTester tester, [Size tamano = const Size(1200, 1400)]) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _sin(int _) {}

/// `RecursoForm` suelto: prueba el botón «+» sin montar página ni red.
Widget _formulario({
  required List<Opccion> opciones,
  Future<String?> Function(String nombre)? onCrear,
  Future<String?> Function()? onAlta,
}) {
  return MaterialApp(
    home: Scaffold(
      body: RecursoForm(
        titulo: 'Nuevo producto',
        campos: [
          CampoFormulario(
            clave: 'categoriaId',
            etiqueta: 'Categoría',
            tipo: TipoCampo.opcion,
            opcionesDinamicas: () => opciones,
            etiquetaCrear: 'Nueva categoría',
            onCrear: onCrear,
            onAlta: onAlta,
          ),
        ],
        valores: const {},
      ),
    ),
  );
}

/// Módulo de productos con todos sus controllers: el de producto y los
/// catálogos que alimentan sus desplegables —incluidos tallas y colores, que
/// usa el campo de variantes del alta.
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

/// El botón «+» que acompaña al desplegable de `etiqueta`.
Finder _botonMas(String etiqueta) => find.byTooltip(etiqueta);

void main() {
  group('botón «+» al lado del desplegable', () {
    testWidgets('crea la opción y el campo se queda con la nueva', (
      tester,
    ) async {
      final opciones = [
        const Opccion('1', 'Analgésicos'),
        const Opccion('2', 'Vitaminas'),
      ];
      String? enviado;

      _tamano(tester);
      await tester.pumpWidget(
        _formulario(
          opciones: opciones,
          onCrear: (nombre) async {
            enviado = nombre;
            opciones.add(Opccion('3', nombre));
            return '3';
          },
        ),
      );
      await tester.pumpAndSettle();

      // El botón vive junto al campo, sin abrir la hoja de opciones.
      expect(_botonMas('Nueva categoría'), findsOneWidget);

      await tester.tap(_botonMas('Nueva categoría'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Resfriados',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Crear'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(enviado, 'Resfriados');
      // El desplegable se repinta con la opción recién creada ya elegida.
      expect(find.text('Resfriados'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancelar el diálogo no crea ni cambia el valor', (
      tester,
    ) async {
      final opciones = [const Opccion('1', 'Analgésicos')];
      var llamadas = 0;

      _tamano(tester);
      await tester.pumpWidget(
        _formulario(
          opciones: opciones,
          onCrear: (nombre) async {
            llamadas++;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_botonMas('Nueva categoría'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(llamadas, 0);
      expect(find.byType(AlertDialog), findsNothing);
      // El campo sigue vacío (sin «— Sin asignar —» elegido a mano).
      expect(find.text('Analgésicos'), findsNothing);
    });

    testWidgets('el botón dentro de la hoja de opciones sigue funcionando', (
      tester,
    ) async {
      final opciones = [
        const Opccion('1', 'Analgésicos'),
        const Opccion('2', 'Vitaminas'),
      ];
      String? enviado;

      _tamano(tester);
      await tester.pumpWidget(
        _formulario(
          opciones: opciones,
          onCrear: (nombre) async {
            enviado = nombre;
            opciones.add(Opccion('4', nombre));
            return '4';
          },
        ),
      );
      await tester.pumpAndSettle();

      // Se abre el desplegable (búsqueda) y se crea desde su propio pie.
      await tester.tap(
        find.descendant(
          of: find.byType(DesplegableBuscable),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.text('Nueva categoría'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Gripe',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Crear'),
        ),
      );
      await tester.pumpAndSettle();

      expect(enviado, 'Gripe');
      expect(find.text('Gripe'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('el flujo `onAlta` manda él solo y deja lo que devuelve', (
      tester,
    ) async {
      final opciones = [const Opccion('1', 'Analgésicos')];
      var llamadas = 0;

      _tamano(tester);
      await tester.pumpWidget(
        _formulario(
          opciones: opciones,
          // Un alta con diálogo propio (el de «Nuevo cliente» o el de
          // «Nuevo empleado»): no recibe nombre, devuelve el valor elegido.
          onAlta: () async {
            llamadas++;
            opciones.add(const Opccion('7', 'Gripe'));
            return '7';
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(_botonMas('Nueva categoría'), findsOneWidget);
      await tester.tap(_botonMas('Nueva categoría'));
      await tester.pumpAndSettle();

      expect(llamadas, 1);
      // Ni diálogo de solo nombre ni hoja de opciones: el flujo trae el suyo.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
      // Y el campo se queda con el registro que devolvió.
      expect(find.text('Gripe'), findsOneWidget);
    });

    testWidgets('sin `onCrear` ni `onAlta` no se pinta ningún botón', (
      tester,
    ) async {
      _tamano(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RecursoForm(
              titulo: 'Nuevo producto',
              campos: [
                CampoFormulario(
                  clave: 'categoriaId',
                  etiqueta: 'Categoría',
                  tipo: TipoCampo.opcion,
                  opciones: [Opccion('1', 'Analgésicos')],
                ),
              ],
              valores: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    });
  });

  group('formulario de producto', () {
    testWidgets('los dos desplegables llevan su botón «+»', (tester) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();

      expect(_botonMas('Nueva categoría'), findsOneWidget);
      expect(_botonMas('Nuevo proveedor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('crear una categoría la deja elegida en el producto', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_botonMas('Nueva categoría'));
      await tester.tap(_botonMas('Nueva categoría'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Resfriados',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Crear'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // El alta llegó a su endpoint con el nombre escrito…
      expect(repositorio.ultimaRuta, 'categorias');
      expect(repositorio.ultimoCuerpo, {'nombre': 'Resfriados'});
      // …y el desplegable del producto ya la muestra seleccionada.
      expect(find.text('Resfriados'), findsOneWidget);
    });
  });
}
