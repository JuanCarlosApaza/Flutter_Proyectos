import 'package:farmacia/core/network/api_client.dart';
import 'package:farmacia/core/permisos.dart';
import 'package:farmacia/core/widgets/ajustes_scope.dart';
import 'package:farmacia/core/widgets/sesion_scope.dart';
import 'package:farmacia/domain/entities/recurso.dart';
import 'package:farmacia/domain/entities/usuario.dart';
import 'package:farmacia/domain/repositories/recurso_repository.dart';
import 'package:farmacia/domain/usecases/crud.dart';
import 'package:farmacia/presentation/controllers/chat_controller.dart';
import 'package:farmacia/presentation/controllers/recurso_controller.dart';
import 'package:farmacia/presentation/controllers/respaldos_controller.dart';
import 'package:farmacia/presentation/pages/ajustes_page.dart';
import 'package:farmacia/presentation/pages/ventas_page.dart';
import 'package:farmacia/presentation/widgets/desplegable_buscable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Estado que devuelve el backend fingido del asistente: Ollama y el modelo
/// listos, para que el panel «Asistente IA» pinte su caso bueno.
final http.Response _estadoAsistente = http.Response(
  '{"ollamaActivo":true,"modeloListo":true,"modelo":"farmacia-x",'
  '"descarga":{"fase":"inactivo","bytes":0}}',
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// Backend falso del módulo: lee los ajustes guardados y anota lo que llega
/// por el `PUT` (que es lo que hay que comprobar al guardar).
class _RepositorioAjustes implements RecursoRepository {
  /// Lo que devolvería `GET /ajustes`.
  final List<Recurso> guardados = [];

  final clientes = [
    Recurso.fromJson({'id': 1, 'nombre': 'María Pérez'}),
  ];

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

  /// Ruta y cuerpo del último `PUT`.
  String? ultimaRuta;
  Map<String, Object?>? ultimoBody;

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
      case 'ajustes':
        return ListadoRecurso(
          total: guardados.length,
          items: guardados.skip(offset).take(limit).toList(),
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
  Future<Recurso> editar(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoBody = body;
    return const Recurso(id: 0, datos: {});
  }

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

/// Pinta `AjustesPage` con los controladores que consume (los cuatro del
/// CRUD más el del asistente) y con la sesión indicada (por defecto, la que
/// sí puede editar).
Widget _ajustes({
  RecursoRepository? repositorio,
  String nivel = 'ADMIN',
  Usuario? usuario,
  http.Response? estadoAsistente,
}) {
  final crud = Crud(repository: repositorio ?? _RepositorioAjustes());
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AjustesController>.value(
        value: AjustesController(crud),
      ),
      ChangeNotifierProvider<RespaldosController>.value(
        value: RespaldosController(crud, ApiClient()),
      ),
      ChangeNotifierProvider<ClientesController>.value(
        value: ClientesController(crud),
      ),
      ChangeNotifierProvider<EmpleadosController>.value(
        value: EmpleadosController(crud),
      ),
      // Catálogos de la sección «Valores por defecto de los formularios»
      // (categoría, presentación, proveedor y rol). El repositorio falso
      // devuelve listas vacías para estas rutas.
      ChangeNotifierProvider<CategoriasController>.value(
        value: CategoriasController(crud),
      ),
      ChangeNotifierProvider<PresentacionesController>.value(
        value: PresentacionesController(crud),
      ),
      ChangeNotifierProvider<ProveedoresController>.value(
        value: ProveedoresController(crud),
      ),
      ChangeNotifierProvider<RolesController>.value(
        value: RolesController(crud),
      ),
      // El panel «Asistente IA» solo lee este estado; se le finge un backend
      // para que la página no abra una petición de verdad.
      ChangeNotifierProvider<ChatController>.value(
        value: ChatController(
          ApiClient(
            baseUrl: 'http://test',
            client: MockClient(
              (_) async => estadoAsistente ?? _estadoAsistente,
            ),
          ),
        ),
      ),
    ],
    child: SesionScope(
      datos: DatosSesion(
        usuario:
            usuario ??
            Usuario(
              id: 9,
              nombreUsuario: 'ana',
              nivelUsuario: nivel,
              // El permiso `ajustes.editar` es lo que habilita la escritura
              // (solo lo tiene el rol ADMIN por defecto).
              permisos: nivel == 'ADMIN' ? todosPermisos : const [],
              empleadoId: 7,
            ),
        cerrarSesion: () async {},
      ),
      child: MaterialApp(
        home: AjustesPage(selectedNav: 9, onNavSelect: (_) {}),
      ),
    ),
  );
}

/// Desplegable que lleva el rótulo dado (los de la página, no los de una
/// hoja ya abierta).
Finder _campo(String etiqueta) => find.ancestor(
  of: find.text(etiqueta),
  matching: find.byType(DesplegableBuscable),
);

void main() {
  /// Escritorio alto: la pantalla tiene cuatro tarjetas, y para tocar un
  /// campo este tiene que estar dentro del viewport.
  void escritorio(WidgetTester tester, {double alto = 1400}) {
    tester.view.physicalSize = Size(1200, alto);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('arranca con lo guardado y pinta sus cinco secciones', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioAjustes()
      // Solo uno guardado: el resto debe mostrar su valor de fábrica.
      ..guardados.add(
        Recurso.fromJson({'id': 1, 'clave': 'porPagina', 'valor': '30'}),
      );

    await tester.pumpWidget(_ajustes(repositorio: repositorio));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ajustes del sistema'), findsOneWidget);
    expect(find.text('Ventas por defecto'), findsOneWidget);
    expect(find.text('Catálogo y tablas'), findsOneWidget);
    expect(find.text('Avisos del dashboard'), findsOneWidget);
    expect(find.text('Navegación'), findsOneWidget);
    expect(find.text('Respaldos de la base de datos'), findsOneWidget);

    // Guardado en la BD…
    expect(find.text('30 filas'), findsOneWidget);
    // …y el resto, con sus valores de fábrica (idénticos a la app antigua).
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('— Usar la cuenta conectada —'), findsOneWidget);
    expect(find.text('90 días'), findsOneWidget);
    expect(find.text('5 unidades'), findsOneWidget);
    // «Dashboard» también lo pinta el sidebar: cuenta con que esté uno.
    expect(find.text('Dashboard'), findsAtLeastNWidgets(1));
    expect(find.text('Destacados'), findsOneWidget);

    // Respaldo: automático diario por defecto y botón listo para usar.
    expect(find.text('Cada día'), findsOneWidget);
    expect(find.text('Respaldar ahora'), findsOneWidget);
    expect(
      find.text(
        'Aún no hay respaldos. Pulsa «Respaldar ahora» para crear el primero.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sin nivel ADMIN se ve en solo lectura y no deja escribir', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioAjustes();

    await tester.pumpWidget(
      _ajustes(repositorio: repositorio, nivel: 'CAJERO'),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Sin botón de guardar y con el aviso de solo lectura…
    expect(find.text('Guardar'), findsNothing);
    expect(
      find.text(
        'Solo una cuenta con el permiso ajustes.editar puede modificar '
        'los ajustes. Se muestran en solo lectura.',
      ),
      findsOneWidget,
    );

    // …y los desplegables no abren su hoja.
    await tester.tap(_campo('Tipo de pago por defecto *'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(repositorio.ultimoBody, isNull);

    // Sin `ajustes.ver` no se piden ni se pintan los respaldos.
    expect(find.text('Respaldos de la base de datos'), findsNothing);
    expect(find.text('Respaldar ahora'), findsNothing);
  });

  testWidgets('ADMIN cambia un ajuste y lo guarda con todos los valores', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioAjustes();

    await tester.pumpWidget(_ajustes(repositorio: repositorio));
    await tester.pumpAndSettle();

    // Cambio «Filas por página» de 10 a 20: se toca el **centro** del campo
    // (regresión: el `InkWell` tenía que envolver rótulo y auxiliar, no solo
    // la línea del valor).
    await tester.tap(_campo('Filas por página (tablas)'));
    await tester.pumpAndSettle();
    expect(
      find.byType(BottomSheet),
      findsWidgets,
      reason: 'no se abrió la hoja de opciones',
    );
    await tester.tap(find.text('20 filas'));
    await tester.pumpAndSettle();
    expect(find.text('20 filas'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    // Tras guardar se dispara `alertaExito` (QuickAlert + GIF): solo pumps
    // acotados, `pumpAndSettle` se quedaría esperando el GIF.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Ajustes guardados'), findsOneWidget);

    // Lo que llega a `PUT /ajustes` es el lote completo con el cambio.
    expect(repositorio.ultimaRuta, 'ajustes');
    final valores =
        (repositorio.ultimoBody?['valores'] ?? const {})
            as Map<String, Object?>;
    expect(valores['porPagina'], '20');
    expect(valores['tipoPagoPorDefecto'], 'EFECTIVO');
    // El intervalo de respaldo viaja en el mismo lote (diario por defecto).
    expect(valores[Ajustes.respaldoIntervalo], '1440');
    expect(valores.length, Ajustes.defectos.length);
  });

  testWidgets('la sección del asistente cuenta el estado de Ollama', (
    tester,
  ) async {
    escritorio(tester);
    final repositorio = _RepositorioAjustes();

    await tester.pumpWidget(_ajustes(repositorio: repositorio));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Asistente IA'), findsOneWidget);
    expect(
      find.textContaining('Listo: farmacia-x está instalado en Ollama'),
      findsOneWidget,
    );
    // Con el modelo ya puesto no se vuelve a ofrecer la descarga de 1 GB…
    expect(find.textContaining('Descargar Qwen2.5-1.5B'), findsNothing);
    // …y el panel deja claro que nada sale del equipo.
    expect(
      find.textContaining('ni los datos ni las preguntas salen'),
      findsOneWidget,
    );
  });

  testWidgets(
    'sin Ollama el panel solo pide instalarlo (un problema cada vez)',
    (tester) async {
      escritorio(tester);
      final repositorio = _RepositorioAjustes();

      // El caso que se ve en pantalla real: el modelo llegó al 100 % pero
      // `ollama create` no encontró el binario, y además Ollama no corre.
      await tester.pumpWidget(
        _ajustes(
          repositorio: repositorio,
          estadoAsistente: http.Response(
            '{"ollamaActivo":false,"modeloListo":false,'
            '"modelo":"farmacia-x",'
            '"descarga":{"fase":"error","bytes":1073741824,'
            '"error":"No encuentro el comando `ollama`."}}',
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('No detecto Ollama'), findsOneWidget);
      // El error del create y el botón de reintentar son el mismo problema de
      // origen: enseñarlos solo añade un segundo aviso y el botón no llevaría
      // a ninguna parte hasta instalar Ollama.
      expect(find.textContaining('No encuentro el comando'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.textContaining('Descargar Qwen2.5-1.5B'), findsNothing);
    },
  );

  testWidgets('los ajustes de ventas mandan en «Nueva Orden»', (tester) async {
    escritorio(tester);
    final repositorio = _RepositorioAjustes();
    final crud = Crud(repository: repositorio);

    await tester.pumpWidget(
      MultiProvider(
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
        // El scope va **sobre** `MaterialApp`: la hoja modal vive en el
        // `Navigator` y por eso se pone en la raíz de la app real.
        child: AjustesScope(
          valores: const {
            'vendedorPorDefecto': '8',
            'tipoPagoPorDefecto': 'QR',
            'clientePorDefecto': '1',
          },
          child: SesionScope(
            datos: DatosSesion(
              // La sesión es el vendedor 7: si el ajuste funciona, en el
              // formulario debe salir el 8 (Rosa), no Ana.
              usuario: const Usuario(
                id: 9,
                nombreUsuario: 'ana',
                nivelUsuario: 'CAJERO',
                permisos: [
                  'ventas.ver',
                  'ventas.crear',
                  'catalogo.ver',
                  'catalogo.crear',
                ],
                empleadoId: 7,
              ),
              cerrarSesion: () async {},
            ),
            child: MaterialApp(
              home: VentasPage(selectedNav: 3, onNavSelect: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nueva Orden'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rosa Gómez'), findsOneWidget);
    // El cobro solo admite Efectivo/QR hoy: el ajuste debe arrancar la
    // única fila de pago en QR.
    expect(find.text('QR'), findsOneWidget);
    expect(find.text('María Pérez'), findsOneWidget);
  });
}
