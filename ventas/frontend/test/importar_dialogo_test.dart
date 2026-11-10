import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:ventas/core/network/api_client.dart';
import 'package:ventas/core/widgets/sesion_scope.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/entities/usuario.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/importar/plantilla_excel.dart';
import 'package:ventas/presentation/pages/productos_page.dart';
import 'package:ventas/presentation/widgets/importar_excel.dart';
import 'package:ventas/presentation/widgets/opciones_formulario.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';

/// Catálogo en memoria: el alta de catálogos devuelve un id y se guarda el
/// último cuerpo, para poder asertar que las relaciones por crear llegaron
/// resueltas a la API.
class _CatalogoFalso implements RecursoRepository {
  int _siguienteId = 100;

  final Map<String, List<Recurso>> _listados = {
    'categorias': [],
    'presentaciones': [],
    'marcas': [],
    'proveedores': [],
    'productos': [],
  };

  Map<String, Object?>? ultimoCuerpo;
  String? ultimaRuta;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async => ListadoRecurso(
    total: _listados[recurso]?.length ?? 0,
    items: _listados[recurso] ?? const [],
  );

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoCuerpo = body;
    final creado = Recurso.fromJson({'id': _siguienteId++, ...body});
    _listados.putIfAbsent(ruta, () => []).add(creado);
    return creado;
  }

  @override
  Future<Recurso> obtener(String ruta) async => Recurso(id: 0, datos: const {});

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) async =>
      crear(ruta, body);

  @override
  Future<void> eliminar(String ruta) async {}
}

http.Response _json(Object cuerpo, int codigo) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  codigo,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// El diálogo con sus cuatro catálogos y un ApiClient falso que guarda el
/// cuerpo del `POST /importar` y contesta con [respuesta].
Widget _harness({
  required List<CampoFormulario> campos,
  required ApiClient api,
  required void Function(bool? importado) alCerrar,
  Future<FicheroElegido?> Function()? elegirArchivo,
  Future<bool> Function(Uint8List bytes, String nombre)? guardarPlantilla,
  required _CatalogoFalso repositorio,
}) {
  final crud = Crud(repository: repositorio);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<CategoriasController>.value(
        value: CategoriasController(crud),
      ),
      ChangeNotifierProvider<PresentacionesController>.value(
        value: PresentacionesController(crud),
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
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final importado = await mostrarImportarExcel(
                  context,
                  campos: campos,
                  categorias: context.read<CategoriasController>(),
                  presentaciones: context.read<PresentacionesController>(),
                  marcas: context.read<MarcasController>(),
                  proveedores: context.read<ProveedoresController>(),
                  api: api,
                  elegirArchivo: elegirArchivo,
                  guardarPlantilla: guardarPlantilla,
                );
                alCerrar(importado);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  /// Campos del diálogo: como los de `ProductosPage` (nueve obligatorios).
  final campos = <CampoFormulario>[
    CampoFormulario(
      clave: 'nombre',
      etiqueta: 'Nombre *',
      obligatorio: true,
      minCaracteres: 2,
      maxCaracteres: 150,
    ),
    CampoFormulario(
      clave: 'precioCompra',
      etiqueta: 'Precio de compra (Bs) *',
      obligatorio: true,
      tipo: TipoCampo.decimal,
      min: 0.01,
      max: 99999999.99,
    ),
    CampoFormulario(
      clave: 'precioVenta',
      etiqueta: 'Precio de venta (Bs) *',
      obligatorio: true,
      tipo: TipoCampo.decimal,
      min: 0.01,
      max: 99999999.99,
    ),
    CampoFormulario(
      clave: 'gananciaPct',
      etiqueta: 'Ganancia %',
      tipo: TipoCampo.porcentaje,
      min: 0,
      max: 999,
      porcentajeSobre: 'precioCompra',
      porcentajeDestino: 'precioVenta',
    ),
    CampoFormulario(
      clave: 'stock',
      etiqueta: 'Stock *',
      obligatorio: true,
      tipo: TipoCampo.decimal,
      min: 0,
      max: 999999.999,
      decimales: 3,
    ),
    CampoFormulario(
      clave: 'unidad',
      etiqueta: 'Unidad de venta *',
      obligatorio: true,
      tipo: TipoCampo.opcion,
      opcionesDinamicas: () => unidadesVenta,
    ),
    CampoFormulario(
      clave: 'estado',
      etiqueta: 'Estado *',
      obligatorio: true,
      tipo: TipoCampo.opcion,
      opciones: [
        Opccion('DISPONIBLE', 'Disponible'),
        Opccion('AGOTADO', 'Agotado'),
        Opccion('POR_VENCER', 'Por vencer'),
        Opccion('DESCONTINUADO', 'Descontinuado'),
      ],
    ),
    CampoFormulario(
      clave: 'variantes',
      etiqueta: 'Colores (stock por variante)',
      tipo: TipoCampo.variantes,
    ),
    CampoFormulario(clave: 'codigo', etiqueta: 'Código', maxCaracteres: 60),
    CampoFormulario(
      clave: 'descripcion',
      etiqueta: 'Descripción',
      maxCaracteres: 255,
    ),
    CampoFormulario(
      clave: 'precioRebaja',
      etiqueta: 'Máximo a rebajar por unidad (Bs)',
      tipo: TipoCampo.decimal,
      min: 0,
      max: 99999999.99,
    ),
    CampoFormulario(
      clave: 'stockMinimo',
      etiqueta: 'Stock mínimo',
      tipo: TipoCampo.decimal,
      min: 0,
      max: 999999.999,
      decimales: 3,
    ),
    CampoFormulario(
      clave: 'fechaVencimiento',
      etiqueta: 'Fecha de vencimiento',
      tipo: TipoCampo.fecha,
      minFecha: DateTime(2000, 1, 1),
    ),
    CampoFormulario(
      clave: 'categoriaId',
      etiqueta: 'Categoría *',
      obligatorio: true,
      tipo: TipoCampo.opcion,
      opcionesDinamicas: () => const [Opccion('1', 'Bebidas')],
      onCrear: (nombre) async => '1',
    ),
    CampoFormulario(
      clave: 'presentacionId',
      etiqueta: 'Presentación *',
      obligatorio: true,
      tipo: TipoCampo.opcion,
      opcionesDinamicas: () => const [Opccion('7', 'Botella')],
      onCrear: (nombre) async => '7',
    ),
    CampoFormulario(
      clave: 'marcaId',
      etiqueta: 'Marca *',
      obligatorio: true,
      tipo: TipoCampo.opcion,
      opcionesDinamicas: () => const [Opccion('3', 'Andina')],
      onCrear: (nombre) async => '3',
    ),
    CampoFormulario(
      clave: 'garantiaMeses',
      etiqueta: 'Garantía (meses)',
      tipo: TipoCampo.opcion,
      opciones: [Opccion('12', '12 meses')],
    ),
    CampoFormulario(
      clave: 'proveedorId',
      etiqueta: 'Proveedor',
      tipo: TipoCampo.opcion,
      opcionesDinamicas: () => const [],
      onCrear: (nombre) async => '9',
    ),
    CampoFormulario(
      clave: 'imagen',
      etiqueta: 'Imagen del producto',
      tipo: TipoCampo.imagen,
    ),
  ];

  void tamano(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// ApiClient falso que guarda el cuerpo del `POST /importar` en
  /// [alRecibir] y contesta con [respuesta].
  ApiClient apiFalsa({
    required void Function(Map<String, Object?> cuerpo) alRecibir,
    Map<String, Object?> respuesta = const {
      'creados': 2,
      'omitidos': <Object?>[],
      'errores': <Object?>[],
    },
  }) => ApiClient(
    baseUrl: 'http://test',
    client: MockClient((request) async {
      if (request.url.path == '/api/v1/products/importar') {
        alRecibir(jsonDecode(request.body) as Map<String, Object?>);
        return _json(respuesta, 200);
      }
      return _json({'error': 'no'}, 404);
    }),
  );

  testWidgets('los 3 pasos: plantilla, vista previa y resultado', (
    tester,
  ) async {
    tamano(tester);
    final repositorio = _CatalogoFalso();
    Map<String, Object?>? recibido;
    final api = apiFalsa(alRecibir: (cuerpo) => recibido = cuerpo);
    Uint8List? plantillaDescargada;
    String? nombrePlantilla;
    bool? cerrado;

    await tester.pumpWidget(
      _harness(
        campos: campos,
        api: api,
        repositorio: repositorio,
        alCerrar: (valor) => cerrado = valor,
        guardarPlantilla: (bytes, nombre) async {
          plantillaDescargada = bytes;
          nombrePlantilla = nombre;
          return true;
        },
        elegirArchivo: () async => (
          nombre: 'productos_plantilla.xlsx',
          bytes: plantillaProductos(campos: campos),
        ),
      ),
    );

    // ── Paso 1: archivo ────────────────────────────────────────────────
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Importar productos desde Excel'), findsOneWidget);
    expect(find.textContaining('se lee en tu equipo'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Descargar plantilla (.xlsx)'),
    );
    await tester.pumpAndSettle();
    expect(plantillaDescargada, isNotNull);
    expect(plantillaDescargada!.isNotEmpty, isTrue);
    expect(nombrePlantilla, 'productos_plantilla.xlsx');

    // ── Paso 2: vista previa ──────────────────────────────────────────
    await tester.tap(find.widgetWithText(FilledButton, 'Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('Vista previa de la importación'), findsOneWidget);
    // La plantilla trae dos filas de ejemplo, ambas válidas.
    expect(find.textContaining('✓ 2 válidas'), findsOneWidget);
    expect(find.textContaining('Fila 2'), findsOneWidget);
    expect(find.textContaining('Fila 3'), findsOneWidget);
    expect(find.textContaining('Lista para importar'), findsNWidgets(2));

    // ── Paso 3: resultado ─────────────────────────────────────────────
    await tester.tap(find.widgetWithText(ElevatedButton, 'Importar 2 válidas'));
    await tester.pumpAndSettle();

    expect(find.text('Importación terminada'), findsOneWidget);
    expect(find.textContaining('Se crearon 2'), findsOneWidget);

    // El cuerpo lleva las filas con su número REAL de Excel y las
    // relaciones ya resueltas a ID (creadas al vuelo: Bebidas, Botella,
    // Andina y el proveedor no existían).
    expect(recibido, isNotNull);
    expect(recibido!['archivo'], 'productos_plantilla.xlsx');
    final filas = recibido!['filas']! as List;
    expect(filas, hasLength(2));
    expect((filas.first as Map)['fila'], 2);
    expect((filas.first as Map)['nombre'], 'Gaseosa Cola 2 L');
    expect((filas.last as Map)['fila'], 3);
    expect((filas.last as Map)['fila'] is int, isTrue);
    expect((filas.last as Map)['variantes'], isA<List<Object?>>());
    // Los catálogos de la plantilla existen en los combos (Bebidas,
    // Botella, Andina), así que viajan directamente a su ID.
    expect((filas.first as Map)['categoriaId'], '1');
    expect((filas.first as Map)['presentacionId'], '7');
    expect((filas.first as Map)['marcaId'], '3');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar'));
    await tester.pumpAndSettle();
    expect(cerrado, isTrue);
    expect(find.text('Importar productos desde Excel'), findsNothing);
  });

  testWidgets('las filas con error se excluyen y se cuentan aparte', (
    tester,
  ) async {
    tamano(tester);
    final repositorio = _CatalogoFalso();
    // Unidades sin «LT»: la primera fila de la plantilla (Gaseosa, LT) pasa
    // a ser inválida y la segunda (Papas, UN) sigue siendo válida.
    final camposSinLt = [
      for (final campo in campos)
        campo.clave == 'unidad'
            ? CampoFormulario(
                clave: 'unidad',
                etiqueta: 'Unidad de venta *',
                obligatorio: true,
                tipo: TipoCampo.opcion,
                opcionesDinamicas: () => const [Opccion('UN', 'Unidad (UN)')],
              )
            : campo,
    ];
    Map<String, Object?>? recibido;
    final api = apiFalsa(
      alRecibir: (cuerpo) => recibido = cuerpo,
      respuesta: const {
        'creados': 1,
        'omitidos': <Object?>[],
        'errores': <Object?>[
          {'fila': 2, 'mensaje': 'No existe la unidad'},
        ],
      },
    );
    bool? cerrado;

    await tester.pumpWidget(
      _harness(
        campos: camposSinLt,
        api: api,
        repositorio: repositorio,
        alCerrar: (valor) => cerrado = valor,
        elegirArchivo: () async => (
          nombre: 'parcial.xlsx',
          bytes: plantillaProductos(campos: camposSinLt),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('✓ 1 válida'), findsOneWidget);
    expect(find.textContaining('✖ 1 con error'), findsOneWidget);
    expect(find.textContaining('No existe «LT»'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Importar 1 válida'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Se crearon 1'), findsOneWidget);
    expect(find.textContaining('1 con error'), findsOneWidget);
    expect(find.textContaining('Fila 2 –'), findsOneWidget);

    final filas = recibido!['filas']! as List;
    expect(filas, hasLength(1), reason: 'solo la fila válida');
    expect((filas.single as Map)['fila'], 3);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar'));
    await tester.pumpAndSettle();
    expect(cerrado, isTrue);
  });

  testWidgets('el botón «Importar Excel» sale en Productos y se oculta '
      'sin permiso de creación', (tester) async {
    tamano(tester);
    final crud = Crud(repository: _CatalogoFalso());
    final arbol = MultiProvider(
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
        home: ProductosPage(selectedNav: 1, onNavSelect: (_) {}),
      ),
    );

    // Sin SesionScope se permite por defecto: los dos botones juntos.
    await tester.pumpWidget(arbol);
    await tester.pumpAndSettle();

    expect(find.text('Nuevo Producto'), findsOneWidget);
    expect(find.text('Importar Excel'), findsOneWidget);

    // Un rol solo con `productos.ver`: no puede ni dar de alta ni importar.
    await tester.pumpWidget(
      SesionScope(
        datos: DatosSesion(
          usuario: Usuario(
            id: 1,
            nombreUsuario: 'solo_ver',
            nivelUsuario: 'CAJERO',
            permisos: const ['productos.ver'],
            empleadoId: null,
          ),
          cerrarSesion: () async {},
        ),
        child: arbol,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nuevo Producto'), findsNothing);
    expect(find.text('Importar Excel'), findsNothing);
  });
}
