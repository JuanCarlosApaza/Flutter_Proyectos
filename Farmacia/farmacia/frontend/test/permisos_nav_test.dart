import 'package:farmacia/core/permisos.dart';
import 'package:farmacia/core/widgets/sidebar.dart';
import 'package:farmacia/domain/entities/recurso.dart';
import 'package:farmacia/domain/entities/usuario.dart';
import 'package:farmacia/domain/repositories/recurso_repository.dart';
import 'package:farmacia/domain/usecases/crud.dart';
import 'package:farmacia/presentation/controllers/recurso_controller.dart';
import 'package:farmacia/presentation/pages/usuarios_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

DatosSesion _sesion(List<String> permisos, {String nivel = 'VENDEDOR'}) =>
    DatosSesion(
      usuario: Usuario(
        id: 1,
        nombreUsuario: 'vpruebas',
        nivelUsuario: nivel,
        permisos: permisos,
      ),
      cerrarSesion: () async {},
    );

/// VENDEDOR de la semilla `009_roles_permisos`.
const List<String> _permisosVendedor = [
  'ventas.ver',
  'ventas.crear',
  'catalogo.ver',
  'catalogo.crear',
  'clientes.ver',
];

void main() {
  group('Usuario.puede', () {
    final usuario = Usuario(
      id: 1,
      nombreUsuario: 'ana',
      nivelUsuario: 'CAJERO',
      permisos: const ['ventas.ver', 'ventas.crear'],
    );

    test('concede la acción exacta', () {
      expect(usuario.puede('ventas'), isTrue);
      expect(usuario.puede('ventas', Acciones.ver), isTrue);
      expect(usuario.puede('ventas', Acciones.crear), isTrue);
    });

    test('la acción por defecto es "ver"', () {
      expect(usuario.puede('ventas', Acciones.editar), isFalse);
      expect(usuario.puede('ventas', Acciones.eliminar), isFalse);
    });

    test('"ver" no concede "editar" ni viceversa', () {
      expect(usuario.puede('productos'), isFalse);
      expect(usuario.puede('productos', Acciones.editar), isFalse);
    });

    test('sin permisos no concede nada', () {
      const vacio = Usuario(id: 2, nombreUsuario: 'sin', nivelUsuario: 'X');
      expect(vacio.puede('dashboard'), isFalse);
    });
  });

  group('indicesVisibles', () {
    test('sin sesión (tests aislados) se ve todo', () {
      expect(indicesVisibles(null), List.generate(navItems.length, (i) => i));
    });

    test('con sesión solo los módulos con permiso "ver"', () {
      final sesion = _sesion(_permisosVendedor);
      // Catálogo (2), Clientes (3) y Ventas (4).
      expect(indicesVisibles(sesion), [2, 3, 4]);
    });

    test('un rol sin permisos nunca deja el menú vacío', () {
      final sesion = _sesion(const []);
      expect(indicesVisibles(sesion), [0]);
    });

    test('ADMIN ve todos los módulos (incluida Auditoría)', () {
      final sesion = _sesion(todosPermisos, nivel: 'ADMIN');
      expect(indicesVisibles(sesion).length, navItems.length);
      expect(indicesVisibles(sesion), contains(10)); // Auditoría
    });
  });

  group('bottomNavIndices', () {
    test('con sesión completa respeta el orden móvil', () {
      final sesion = _sesion(todosPermisos, nivel: 'ADMIN');
      // Dashboard, Catálogo, Productos, Ventas (orden del bottom nav móvil).
      expect(bottomNavIndices(sesion), [0, 2, 1, 4]);
    });

    test('con VENDEDOR solo incluye módulos visibles', () {
      final sesion = _sesion(_permisosVendedor);
      // Preferencia [0,2,1,4]: Catálogo (2) y Ventas (4) son visibles;
      // se rellena con Clientes (3).
      expect(bottomNavIndices(sesion), [2, 4, 3]);
    });

    test('sin sesión usa el mismo orden móvil', () {
      expect(bottomNavIndices(null), [0, 2, 1, 4]);
    });
  });

  group('Sidebar filtrado', () {
    testWidgets('un vendedor solo ve sus módulos', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Sidebar(
              selectedIndex: 4,
              onSelect: (_) {},
              sesion: _sesion(_permisosVendedor),
            ),
          ),
        ),
      );

      expect(find.text('Ventas'), findsOneWidget);
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Productos'), findsNothing);
      expect(find.text('Usuarios'), findsNothing);
      expect(find.text('Auditoría'), findsNothing);
      expect(find.text('Ajustes'), findsNothing);
    });

    testWidgets('un admin con todos los permisos ve Auditoría', (tester) async {
      // Superficie alta: los 12 ítems del menú no caben en 600px.
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Sidebar(
              selectedIndex: 10,
              onSelect: (_) {},
              sesion: _sesion(todosPermisos, nivel: 'ADMIN'),
            ),
          ),
        ),
      );

      expect(find.text('Auditoría'), findsOneWidget);
      // Ajustes sigue al final (índice 11).
      expect(find.text('Ajustes'), findsOneWidget);
    });
  });

  group('pestaña Roles de Usuarios', () {
    testWidgets('la matriz pinta todos los módulos × 4 acciones', (
      tester,
    ) async {
      await tester.pumpWidget(_usuarios(repositorio: _RepositorioRoles()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Roles'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Roles y permisos'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('VENDEDOR'), findsOneWidget);
      // Solo el ADMIN muestra la insignia de acceso total.
      expect(find.text('Acceso total'), findsOneWidget);

      // Abrir el editor del VENDEDOR (el de ADMIN tiene el lápiz deshabilitado).
      final lapices = find.byIcon(Icons.edit_outlined);
      expect(lapices, findsNWidgets(2));
      await tester.tap(lapices.last);
      await tester.pumpAndSettle();

      // Matriz: 11 módulos × 4 acciones con sus cabeceras.
      expect(find.text('Categorías'), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Eliminar'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(Modulos.todos.length * 4));
    });
  });

  group('alta de empleado desde Usuarios', () {
    testWidgets('«Nuevo empleado» abre la ficha completa y la crea', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repositorio = _RepositorioRoles();
      await tester.pumpWidget(_usuarios(repositorio: repositorio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo Usuario'));
      await tester.pumpAndSettle();

      // El alta vive en el campo «Empleado vinculado», tras su botón «+».
      final botonMas = find.byTooltip('Nuevo empleado');
      await tester.ensureVisible(botonMas);
      await tester.pumpAndSettle();
      await tester.tap(botonMas);
      await tester.pumpAndSettle();

      // Su hoja trae la ficha entera: los campos de texto van por orden
      // (nombre, apellido, edad, ciudad, dirección y teléfono).
      final campos = find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.byType(TextFormField),
      );
      await tester.enterText(campos.at(0), 'Luis');
      await tester.enterText(campos.at(1), 'Soto');
      final crear = find.descendant(
        of: find.byType(BottomSheet).last,
        matching: find.widgetWithText(ElevatedButton, 'Crear'),
      );
      await tester.ensureVisible(crear);
      await tester.pumpAndSettle();
      await tester.tap(crear);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // El alta llegó a la API con la ficha entera y naciendo ACTIVO…
      expect(repositorio.altaEmpleado?['nombre'], 'Luis');
      expect(repositorio.altaEmpleado?['apellido'], 'Soto');
      expect(repositorio.altaEmpleado?['estado'], 'ACTIVO');
      // …y el formulario de usuario se queda con «Nombre Apellido» elegido.
      expect(find.text('Luis Soto'), findsOneWidget);
    });
  });
}

/// Arnés de la pestaña Usuarios: los tres controllers que la página lee.
Widget _usuarios({required RecursoRepository repositorio}) {
  final crud = Crud(repository: repositorio);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UsuariosController>.value(
        value: UsuariosController(crud),
      ),
      ChangeNotifierProvider<EmpleadosController>.value(
        value: EmpleadosController(crud),
      ),
      ChangeNotifierProvider<RolesController>.value(
        value: RolesController(crud),
      ),
    ],
    child: MaterialApp(home: UsuariosPage(selectedNav: 9, onNavSelect: _sin)),
  );
}

void _sin(int _) {}

/// Doble mínimo: reparte entre roles (el listado) y empleados (el alta desde
/// el formulario de usuario, que recarga el listado tras crear).
final class _RepositorioRoles implements RecursoRepository {
  /// Empleados en memoria; el alta de «Nuevo empleado» los añade.
  final List<Recurso> empleados = [];

  /// Último alta de empleado recibida, para la aserción.
  Map<String, Object?>? altaEmpleado;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    if (recurso == 'empleados') {
      return ListadoRecurso(
        total: empleados.length,
        items: empleados.skip(offset).take(limit).toList(),
      );
    }
    if (recurso != 'roles') {
      const fuente = <Recurso>[];
      return ListadoRecurso(
        total: fuente.length,
        items: fuente.skip(offset).take(limit).toList(),
      );
    }
    final roles = [
      Recurso.fromJson(const {
        'id': 1,
        'nombre': 'ADMIN',
        'descripcion': 'Acceso total al sistema',
        'esSistema': true,
        'estado': 'ACTIVO',
        'permisos': ['productos.ver'],
      }),
      Recurso.fromJson(const {
        'id': 3,
        'nombre': 'VENDEDOR',
        'descripcion': 'Solo ventas',
        'esSistema': true,
        'estado': 'ACTIVO',
        'permisos': ['ventas.ver'],
      }),
    ];
    return ListadoRecurso(
      total: roles.length,
      items: roles.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> obtener(String ruta) => throw UnimplementedError();

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    if (ruta != 'empleados') throw UnimplementedError();
    altaEmpleado = body;
    final creado = Recurso.fromJson({'id': 7, ...body});
    empleados.add(creado);
    return creado;
  }

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}
