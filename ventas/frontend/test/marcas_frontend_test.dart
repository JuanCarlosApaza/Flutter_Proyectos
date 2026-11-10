import 'package:ventas/core/widgets/ajustes_scope.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/categorias_page.dart';
import 'package:ventas/presentation/pages/productos_page.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Catálogo en memoria con las marcas y productos de las pruebas de la
/// migración 023: columna/filtro de la tabla, campos del formulario y la
/// pestaña «Marcas» de Categorías. Los filtros que llegan a `listar` se
/// guardan para poder asertar el `?marcaId=`.
class _CatalogoFalso implements RecursoRepository {
  _CatalogoFalso({bool semillas = false})
    : _listados = {
        'productos': [
          if (semillas)
            Recurso.fromJson({
              'id': 1,
              'nombre': 'Galaxy A15',
              'precioVenta': 1200.0,
              'precioCompra': 900.0,
              'stock': 3.0,
              'unidad': 'UN',
              'estado': 'DISPONIBLE',
              'marcaId': 1,
              'garantiaMeses': 12,
            }),
          Recurso.fromJson({
            'id': 2,
            'nombre': 'Pan',
            'precioVenta': 2.0,
            'precioCompra': 1.0,
            'stock': 8.0,
            'unidad': 'UN',
            'estado': 'DISPONIBLE',
          }),
        ],
        'categorias': [
          Recurso.fromJson({'id': 1, 'nombre': 'Analgésicos'}),
        ],
        'presentaciones': [
          Recurso.fromJson({'id': 1, 'nombre': 'Caja'}),
        ],
        'proveedores': [],
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
        'colores': [],
        'marcas': [
          if (semillas) ...[
            Recurso.fromJson({
              'id': 1,
              'nombre': 'Samsung',
              'estado': 'ACTIVO',
            }),
            Recurso.fromJson({'id': 2, 'nombre': 'Nike', 'estado': 'ACTIVO'}),
          ],
        ],
      };

  final Map<String, List<Recurso>> _listados;

  /// Último alta/edición recibida y últimos filtros de productos.
  String? ultimaRuta;
  Map<String, Object?>? ultimoCuerpo;
  Map<String, String>? filtrosProductos;

  int _siguienteId = 100;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    if (recurso == 'productos') filtrosProductos = filtros;
    var fuente = [...?_listados[recurso]];
    final marcaId = filtros?['marcaId'];
    if (marcaId != null) {
      final id = int.tryParse(marcaId);
      fuente = fuente.where((r) => r['marcaId'] == id).toList();
    }
    if (estado != null) {
      fuente = fuente.where((r) => r.texto('estado') == estado).toList();
    }
    return ListadoRecurso(
      total: fuente.length,
      items: fuente.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoCuerpo = body;
    final creado = Recurso.fromJson({'id': _siguienteId++, ...body});
    _listados.putIfAbsent(ruta, () => []).add(creado);
    return creado;
  }

  @override
  Future<Recurso> obtener(String ruta) async {
    final partes = ruta.split('/');
    final id = int.tryParse(partes.last) ?? -1;
    final encontrado = (_listados[partes.first] ?? const <Recurso>[])
        .where((r) => r.id == id)
        .firstOrNull;
    return encontrado ?? Recurso(id: 0, datos: const {});
  }

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoCuerpo = body;
    final partes = ruta.split('/');
    final lista = _listados.putIfAbsent(partes.first, () => []);
    final id = int.parse(partes.last);
    final i = lista.indexWhere((r) => r.id == id);
    if (i >= 0) {
      lista[i] = Recurso.fromJson({'id': id, ...lista[i].datos, ...body});
      return lista[i];
    }
    return Recurso.fromJson({'id': id, ...body});
  }

  @override
  Future<void> eliminar(String ruta) async {
    final partes = ruta.split('/');
    final id = int.tryParse(partes.last) ?? -1;
    _listados[partes.first]?.removeWhere((r) => r.id == id);
  }
}

void _tamano(WidgetTester tester, [Size tamano = const Size(1400, 2000)]) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _sin(int _) {}

/// Módulo de productos con sus siete controllers (el de producto y los seis
/// catálogos que alimentan sus desplegables y su filtro de marca). Los
/// ajustes precargan los dos desplegables obligatorios (unidad y estado)
/// para que el alta no dependa de elegirlos a mano en cada test.
Widget _productos({required _CatalogoFalso repositorio}) {
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

/// Página de Categorías con sus cuatro pestañas (Categorías,
/// Presentaciones, Colores y Marcas). El ajuste de estado deja el alta de
/// marca precargada («ACTIVO»), igual que en el resto de catálogos.
Widget _categorias({required _CatalogoFalso repositorio}) {
  final crud = Crud(repository: repositorio);
  return AjustesScope(
    valores: const {
      'defecto.categoria.estado': 'ACTIVO',
      'defecto.presentacion.estado': 'ACTIVO',
      'defecto.color.estado': 'ACTIVO',
      'defecto.marca.estado': 'ACTIVO',
    },
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<CategoriasController>.value(
          value: CategoriasController(crud),
        ),
        ChangeNotifierProvider<PresentacionesController>.value(
          value: PresentacionesController(crud),
        ),
        ChangeNotifierProvider<ColoresController>.value(
          value: ColoresController(crud),
        ),
        ChangeNotifierProvider<MarcasController>.value(
          value: MarcasController(crud),
        ),
      ],
      child: MaterialApp(
        home: CategoriasPage(selectedNav: 1, onNavSelect: _sin),
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

/// Un texto solo dentro del formulario abierto (la página de fondo también
/// tiene rótulos iguales, p. ej. el filtro «Marca» de la tabla).
Finder _enFormulario(String texto) =>
    find.descendant(of: find.byType(RecursoForm), matching: find.text(texto));

/// Una opción de la hoja del desplegable: acota el tap/aserción porque la
/// tabla de fondo repite los mismos nombres (p. ej. «Samsung» en su fila).
Finder _opcion(String texto) => find.widgetWithText(ListTile, texto);

/// Elige [opcion] en el desplegable cuyo rótulo es [etiqueta], dentro del
/// formulario abierto (los catálogos obligatorios viven en «Obligatorio»).
Future<void> _elige(WidgetTester tester, String etiqueta, String opcion) async {
  final campo = find.ancestor(
    of: _enFormulario(etiqueta),
    matching: find.byType(DesplegableBuscable),
  );
  await tester.ensureVisible(campo);
  await tester.pumpAndSettle();
  await tester.tap(campo);
  await tester.pumpAndSettle();
  await tester.tap(_opcion(opcion));
  await tester.pumpAndSettle();
}

void main() {
  group('tabla de productos: la marca', () {
    testWidgets(
      'pinta el nombre de la marca y deja el — de quien no la lleva',
      (tester) async {
        final repositorio = _CatalogoFalso(semillas: true);
        _tamano(tester);
        await tester.pumpWidget(_productos(repositorio: repositorio));
        await tester.pumpAndSettle();

        expect(find.text('Galaxy A15'), findsOneWidget);
        // La celda de la columna «Marca» (el producto con marca)…
        expect(find.text('Samsung'), findsOneWidget);
        // …y «—» para el producto sin marca (junto a los otros «—» de la
        // fila: máximo a rebaja, etc.).
        expect(find.text('—'), findsWidgets);
        // La marca que nadie usa no aparece en ninguna parte.
        expect(find.text('Nike'), findsNothing);
        // El filtro de marca arranca en «Todas las marcas».
        expect(find.text('Todas las marcas'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('el desplegable «Marca» filtra la tabla en el servidor', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso(semillas: true);
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      // El rótulo «Marca» también es la cabecera de la columna: el filtro
      // es el que vive dentro de un desplegable.
      final filtro = find.ancestor(
        of: find.text('Marca'),
        matching: find.byType(DesplegableBuscable),
      );
      expect(filtro, findsOneWidget);
      await tester.ensureVisible(filtro);
      await tester.pumpAndSettle();
      await tester.tap(filtro);
      await tester.pumpAndSettle();

      expect(_opcion('Todas las marcas'), findsOneWidget);
      expect(_opcion('Samsung'), findsOneWidget);
      expect(_opcion('Nike'), findsOneWidget);

      await tester.tap(_opcion('Samsung'));
      await tester.pumpAndSettle();

      // La tabla se recarga con `?marcaId=1` y solo queda su producto.
      expect(repositorio.filtrosProductos?['marcaId'], '1');
      expect(find.text('Galaxy A15'), findsOneWidget);
      expect(find.text('Pan'), findsNothing);
      expect(tester.takeException(), isNull);

      // Al volver a «Todas las marcas» el filtro desaparece.
      await tester.ensureVisible(filtro);
      await tester.pumpAndSettle();
      await tester.tap(filtro);
      await tester.pumpAndSettle();
      await tester.tap(_opcion('Todas las marcas'));
      await tester.pumpAndSettle();

      expect(repositorio.filtrosProductos, isNull);
      expect(find.text('Pan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('formulario de producto: marca y garantía', () {
    testWidgets('la marca es obligatoria en Obligatorio y la garantía '
        'trae sus presets', (tester) async {
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: _CatalogoFalso()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();

      // La marca (obligatoria) vive ya en «Obligatorio», junto a su botón
      // «+»; la garantía sigue en «Opcional». El «Marca» de la página de
      // fondo es el filtro de la tabla y por eso la búsqueda se acota al
      // formulario.
      expect(_enFormulario('Marca *'), findsOneWidget);
      expect(find.byTooltip('Nueva marca'), findsOneWidget);
      expect(_enFormulario('Garantía'), findsNothing);

      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      expect(_enFormulario('Marca *'), findsNothing);
      expect(_enFormulario('Garantía'), findsOneWidget);

      // Presets de la garantía (meses) + la opción vacía «Sin asignar».
      final garantia = find.ancestor(
        of: _enFormulario('Garantía'),
        matching: find.byType(DesplegableBuscable),
      );
      await tester.ensureVisible(garantia);
      await tester.pumpAndSettle();
      await tester.tap(garantia);
      await tester.pumpAndSettle();

      expect(_opcion('— Sin asignar —'), findsOneWidget);
      expect(_opcion('3 meses'), findsOneWidget);
      expect(_opcion('12 meses'), findsOneWidget);
      // La hoja recorta la lista a 380 px: el último preset hay que
      // desplazarse hasta él para que se construya.
      final sesenta = _opcion('60 meses');
      await tester.scrollUntilVisible(
        sesenta,
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(sesenta, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('los catálogos obligatorios, la marca y la garantía viajan '
        'en el cuerpo', (tester) async {
      final repositorio = _CatalogoFalso(semillas: true);
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();
      // Rellena lo obligatorio (mismos índices que el formulario real).
      await tester.enterText(find.byType(TextFormField).at(0), 'Galaxy S24');
      await tester.enterText(find.byType(TextFormField).at(1), '3000');
      await tester.enterText(find.byType(TextFormField).at(2), '3500');
      await tester.enterText(find.byType(TextFormField).at(4), '2');
      await tester.pump();

      // Los tres catálogos obligatorios viven en esta pestaña.
      await _elige(tester, 'Categoría *', 'Analgésicos');
      await _elige(tester, 'Presentación *', 'Caja');
      await _elige(tester, 'Marca *', 'Samsung');

      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      final garantia = find.ancestor(
        of: _enFormulario('Garantía'),
        matching: find.byType(DesplegableBuscable),
      );
      await tester.ensureVisible(garantia);
      await tester.pumpAndSettle();
      await tester.tap(garantia);
      await tester.pumpAndSettle();
      await tester.tap(_opcion('12 meses'));
      await tester.pumpAndSettle();

      final guardar = find.widgetWithText(ElevatedButton, 'Crear');
      await tester.ensureVisible(guardar);
      await tester.pumpAndSettle();
      await tester.tap(guardar);
      await tester.pumpAndSettle();

      expect(repositorio.ultimoCuerpo, isNotNull);
      expect(repositorio.ultimoCuerpo!['categoriaId'], '1');
      expect(repositorio.ultimoCuerpo!['presentacionId'], '1');
      expect(repositorio.ultimoCuerpo!['marcaId'], '1');
      expect(repositorio.ultimoCuerpo!['garantiaMeses'], '12');
      expect(repositorio.ultimoCuerpo!['nombre'], 'Galaxy S24');
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Nueva marca» crea la marca y la deja elegida', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Producto'));
      await tester.pumpAndSettle();

      // «Nueva marca» está en «Obligatorio», la pestaña que abre por
      // defecto.
      await tester.ensureVisible(find.byTooltip('Nueva marca'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Nueva marca'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Logitech',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Crear'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repositorio.ultimaRuta, 'marcas');
      expect(repositorio.ultimoCuerpo, {'nombre': 'Logitech'});
      expect(find.text('Logitech'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('pestaña «Marcas» de Categorías', () {
    testWidgets('abre vacía con su propio alta y el mensaje de creación', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso();
      _tamano(tester);
      await tester.pumpWidget(_categorias(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marcas'));
      await tester.pumpAndSettle();

      // El encabezado lleva el conteo del servidor: «Gestión de Marcas (0)».
      expect(find.textContaining('Gestión de Marcas'), findsOneWidget);
      expect(find.text('Nueva Marca'), findsOneWidget);
      expect(find.text('No hay marcas'), findsOneWidget);

      await tester.tap(find.text('Nueva Marca'));
      await tester.pumpAndSettle();
      await tester.enterText(_campoTexto('Nombre *'), 'Logitech');
      final guardar = find.widgetWithText(ElevatedButton, 'Crear');
      await tester.ensureVisible(guardar);
      await tester.pumpAndSettle();
      await tester.tap(guardar);
      await tester.pumpAndSettle();

      expect(repositorio.ultimaRuta, 'marcas');
      expect(repositorio.ultimoCuerpo?['nombre'], 'Logitech');
      expect(find.text('Marca creada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('editar una marca muestra «Marca actualizada»', (tester) async {
      final repositorio = _CatalogoFalso(semillas: true);
      _tamano(tester);
      await tester.pumpWidget(_categorias(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marcas'));
      await tester.pumpAndSettle();
      expect(find.text('Samsung'), findsOneWidget);

      await tester.tap(find.byTooltip('Editar').first);
      await tester.pumpAndSettle();
      await tester.enterText(_campoTexto('Nombre *'), 'Samsung Bolivia');
      final guardar = find.widgetWithText(ElevatedButton, 'Actualizar');
      await tester.ensureVisible(guardar);
      await tester.pumpAndSettle();
      await tester.tap(guardar);
      await tester.pumpAndSettle();

      expect(repositorio.ultimoCuerpo?['nombre'], 'Samsung Bolivia');
      expect(find.text('Marca actualizada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ocultar una marca muestra «Marca ocultada»', (tester) async {
      final repositorio = _CatalogoFalso(semillas: true);
      _tamano(tester);
      await tester.pumpWidget(_categorias(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marcas'));
      await tester.pumpAndSettle();
      expect(find.text('Samsung'), findsOneWidget);

      await tester.tap(find.byTooltip('Eliminar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ocultar'));
      await tester.pumpAndSettle();

      expect(find.text('Marca ocultada'), findsOneWidget);
      // Se oculta Samsung (la primera fila); Nike sigue en el catálogo.
      expect(repositorio._listados['marcas']!.any((m) => m.id == 1), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('detalle del producto', () {
    testWidgets('enseña la marca y los meses de garantía de cada fila', (
      tester,
    ) async {
      final repositorio = _CatalogoFalso(semillas: true);
      _tamano(tester);
      await tester.pumpWidget(_productos(repositorio: repositorio));
      await tester.pumpAndSettle();

      // Ficha del Galaxy A15 (solo lectura): la marca Samsung ya vive en
      // la pestaña «Obligatorio»…
      await tester.tap(find.byTooltip('Ver detalle').first);
      await tester.pumpAndSettle();

      expect(find.text('Detalle: Galaxy A15'), findsOneWidget);
      expect(_enFormulario('Marca *'), findsOneWidget);
      expect(_enFormulario('Samsung'), findsOneWidget);

      // …y la garantía, en «Opcional».
      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      expect(_enFormulario('Garantía'), findsOneWidget);
      expect(_enFormulario('12 meses'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      // El Pan no tiene marca ni garantía: ambos campos en «Sin asignar».
      await tester.tap(find.byTooltip('Ver detalle').last);
      await tester.pumpAndSettle();

      expect(find.text('Detalle: Pan'), findsOneWidget);

      // Sin marca (aunque sea obligatoria, en solo lectura no se puede
      // editar y el hueco en blanco solo confunde)…
      final marca = find.ancestor(
        of: _enFormulario('Marca *'),
        matching: find.byType(DesplegableBuscable),
      );
      expect(
        find.descendant(of: marca, matching: find.text('— Sin asignar —')),
        findsOneWidget,
      );

      // …y sin garantía: cada campo enseña «— Sin asignar —».
      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      final garantia = find.ancestor(
        of: _enFormulario('Garantía'),
        matching: find.byType(DesplegableBuscable),
      );
      expect(
        find.descendant(of: garantia, matching: find.text('— Sin asignar —')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
