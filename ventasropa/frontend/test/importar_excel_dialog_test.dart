import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:ventas/core/network/api_client.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/widgets/importar_excel_dialog.dart';

import 'archivo_excel_prueba.dart';

/// Diálogo de importación de Excel: los 3 pasos (elegir archivo → vista
/// previa → resultado) con un fichero `.xlsx` de verdad y la API simulada.
void main() {
  /// Catálogo con «Ropa» y «Textil Andina» ya creados (como en la BD real).
  final repositorio = _RepositorioFalso();

  late String? rutaPost;
  late Map<String, Object?>? cuerpoPost;
  late Set<String> nombresExistentes;

  /// API en memoria: el GET de nombres devuelve [nombresExistentes] y el
  /// POST de importación responde con lo que se le envía.
  late ApiClient api;

  setUp(() {
    rutaPost = null;
    cuerpoPost = null;
    nombresExistentes = {};
    api = ApiClient(
      baseUrl: 'http://prueba',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'total': nombresExistentes.length,
              'items': [
                for (final nombre in nombresExistentes)
                  {'id': 9, 'nombre': nombre},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        rutaPost = request.url.path;
        cuerpoPost = jsonDecode(request.body) as Map<String, Object?>;
        final productos = (cuerpoPost!['productos'] as List).length;
        return http.Response(
          jsonEncode({
            'id': 0,
            'creados': productos,
            'errores': <Object>[],
            'omitidos': <Object>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  /// Abre el diálogo con [elegirFichero] inyectado (devuelve [archivo]).
  Future<void> importador(
    WidgetTester tester, {
    required Uint8List archivo,
    Future<void> Function()? onImportado,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final crud = Crud(repository: repositorio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<CategoriasController>.value(
            value: CategoriasController(crud),
          ),
          ChangeNotifierProvider<MarcasController>.value(
            value: MarcasController(crud),
          ),
          ChangeNotifierProvider<ProveedoresController>.value(
            value: ProveedoresController(crud),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => mostrarImportadorExcel(
                  context,
                  elegirFichero: () async => archivo,
                  onImportado: onImportado,
                ),
                child: const Text('Abrir importador'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir importador'));
    await tester.pumpAndSettle();
  }

  /// Dos productos válidos: uno con variantes (y marca) y otro sin tallas.
  Uint8List dosProductos() => archivoExcel([
    fila({
      'nombre': 'Pantalón Mezclillo',
      'categoria': 'Ropa',
      'marca': 'Denver', // marca nueva: se da de alta sola
      'proveedor': 'Textil Andina',
      'precioCompra': 59.9,
      'precioVenta': 89.9,
      'variantes': 'S|Negro|5;M|Negro|3',
    }),
    fila({
      'nombre': 'Medias Clásicas',
      'categoria': 'Medias', // categoría nueva: se da de alta sola
      'proveedor': 'Textil Andina',
      'precioCompra': 15,
      'precioVenta': 25,
      'variantes': '',
      'stock': 24,
    }),
  ]);

  testWidgets('flujo completo: elegir → previa → importar → resultado', (
    tester,
  ) async {
    var recargado = false;
    await importador(
      tester,
      archivo: dosProductos(),
      onImportado: () async {
        recargado = true;
      },
    );

    expect(find.text('Importar productos con Excel'), findsOneWidget);

    // ── Paso 1 → 2: elegir el archivo ─────────────────────────────────
    await tester.tap(find.text('Elegir archivo .xlsx'));
    await tester.pumpAndSettle();

    expect(find.text('Vista previa de la importación'), findsOneWidget);
    expect(find.text('✓ 2 productos'), findsOneWidget);
    expect(find.text('2 variantes'), findsOneWidget);
    expect(find.text('Fila 2 · Pantalón Mezclillo'), findsOneWidget);
    expect(find.text('Fila 3 · Medias Clásicas'), findsOneWidget);

    // ── Paso 2 → 3: importar ──────────────────────────────────────────
    await tester.tap(find.text('Importar 2 productos'));
    await tester.pumpAndSettle();

    expect(rutaPost, '/api/v1/productos/importar');
    final productos = (cuerpoPost!['productos'] as List).cast<Map>();
    expect(productos, hasLength(2));

    // «Ropa» y «Textil Andina» ya existían → ids resueltos; «Medias» se
    // creó en el catálogo (id 11) y su producto apunta ahí.
    expect(productos[0]['fila'], 2);
    expect(productos[0]['nombre'], 'Pantalón Mezclillo');
    expect(productos[0]['categoriaId'], '1');
    expect(productos[0]['proveedorId'], '1');
    // «Denver» no existía → se creó en el catálogo de marcas (id 10).
    expect(productos[0]['marcaId'], '10');
    expect(productos[0]['stock'], isNull); // con variantes se ignora
    final variantes = (productos[0]['variantes'] as List).cast<Map>();
    expect(variantes, hasLength(2));
    expect(variantes.first, {'talla': 'S', 'color': 'Negro', 'stock': 5.0});

    expect(productos[1]['categoriaId'], '11'); // «Medias», creada ahora
    expect(productos[1].containsKey('marcaId'), isFalse); // sin marca
    expect(productos[1]['variantes'], isEmpty);
    expect(productos[1]['stock'], 24.0);
    expect(productos[1]['estado'], 'DISPONIBLE');

    // ── Resultado ─────────────────────────────────────────────────────
    expect(find.text('Importación terminada'), findsOneWidget);
    expect(find.text('Se crearon 2 productos'), findsOneWidget);
    expect(recargado, isTrue); // la pantalla recarga su listado

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('las filas con error se ven en la previa y no se envían', (
    tester,
  ) async {
    await importador(
      tester,
      archivo: archivoExcel([
        fila({
          'nombre': 'Barato Raro',
          'categoria': 'Ropa',
          'proveedor': 'Textil Andina',
          'precioCompra': 50,
          'precioVenta': 30, // por debajo de la compra
          'variantes': 'M|Blanco|4',
        }),
        fila({
          'nombre': 'Gorra Lana',
          'categoria': 'Accesorios',
          'proveedor': 'Textil Andina',
          'precioCompra': 20,
          'precioVenta': 35,
          'variantes': 'Única|Verde|9',
        }),
      ]),
    );

    await tester.tap(find.text('Elegir archivo .xlsx'));
    await tester.pumpAndSettle();

    expect(find.text('✓ 1 productos'), findsOneWidget);
    expect(find.text('✖ 1 con error'), findsOneWidget);
    expect(
      find.textContaining('no puede ser menor'),
      findsOneWidget, // el motivo de la fila mala, en su fila
    );
    expect(find.text('Importar 1 productos'), findsOneWidget);

    await tester.tap(find.text('Importar 1 productos'));
    await tester.pumpAndSettle();

    expect(rutaPost, '/api/v1/productos/importar');
    final productos = (cuerpoPost!['productos'] as List).cast<Map>();
    expect(productos, hasLength(1));
    expect(productos.single['nombre'], 'Gorra Lana');
    expect(find.text('Se crearon 1 productos'), findsOneWidget);
  });

  testWidgets('un nombre ya en el inventario se avisa y no se importa', (
    tester,
  ) async {
    nombresExistentes = {'pantalón mezclillo'};

    await importador(
      tester,
      archivo: archivoExcel([
        fila({
          'nombre': 'Pantalón Mezclillo', // misma prenda, otros acentos
          'categoria': 'Ropa',
          'proveedor': 'Textil Andina',
          'precioCompra': 59.9,
          'precioVenta': 89.9,
          'variantes': 'S|Negro|5',
        }),
      ]),
    );

    await tester.tap(find.text('Elegir archivo .xlsx'));
    await tester.pumpAndSettle();

    expect(find.text('⚠ 1 repetidas (se saltan)'), findsOneWidget);
    expect(find.textContaining('Ya existe un producto'), findsOneWidget);

    // Nada importable → botón deshabilitado y sin envío.
    final boton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Importar 0 productos'),
    );
    expect(boton.onPressed, isNull);
    expect(rutaPost, isNull);
  });

  testWidgets('un archivo sin columnas obligatorias no pasa del paso 1', (
    tester,
  ) async {
    await importador(
      tester,
      archivo: archivoExcel(
        [
          ['Pantalón Mezclillo', 89.9],
        ],
        cabeceras: const ['Nombre', 'Precio de venta (Bs)'],
      ),
    );

    await tester.tap(find.text('Elegir archivo .xlsx'));
    await tester.pumpAndSettle();

    expect(find.text('Vista previa de la importación'), findsNothing);
    expect(find.textContaining('Faltan columnas obligatorias'), findsOneWidget);
    expect(find.textContaining('Proveedor'), findsOneWidget);
  });
}

/// Catálogo en memoria con «Ropa» y «Textil Andina» (los que usa el test).
class _RepositorioFalso implements RecursoRepository {
  final Map<String, List<Recurso>> _listados = {
    'productos': <Recurso>[],
    'categorias': [
      Recurso.fromJson({'id': 1, 'nombre': 'Ropa', 'estado': 'ACTIVO'}),
    ],
    'marcas': <Recurso>[], // «Denver» se da de alta durante la importación
    'proveedores': [
      Recurso.fromJson({'id': 1, 'nombre': 'Textil Andina'}),
    ],
  };

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
