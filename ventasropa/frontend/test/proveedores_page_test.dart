import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/proveedores_page.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Catálogo en memoria de proveedores (sin tocar la red): guarda el cuerpo
/// del alta para comprobar qué manda la interfaz a la API.
class _RepositorioFalso implements RecursoRepository {
  final List<Recurso> registros = [
    Recurso.fromJson({
      'id': 1,
      'nombre': 'Distribuidora Norte',
      'nit': '1023456027',
      'email': 'contactos@norte.com.bo',
      'ciudad': 'La Paz',
      'telefono': '274-0000',
      'estado': 'ACTIVO',
    }),
  ];

  Map<String, Object?>? ultimoCuerpo;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async => ListadoRecurso(total: registros.length, items: registros);

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimoCuerpo = body;
    final creado = Recurso.fromJson({'id': registros.length + 10, ...body});
    registros.add(creado);
    return creado;
  }

  @override
  Future<Recurso> obtener(String ruta) async => registros.first;

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) async {
    ultimoCuerpo = body;
    return Recurso.fromJson({...registros.first.datos, ...body});
  }

  @override
  Future<void> eliminar(String ruta) async {}
}

Widget _pagina({required RecursoRepository repositorio}) {
  return ChangeNotifierProvider<ProveedoresController>.value(
    value: ProveedoresController(Crud(repository: repositorio)),
    child: MaterialApp(
      home: ProveedoresPage(selectedNav: 7, onNavSelect: (_) {}),
    ),
  );
}

void _tamano(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Elige «Activo» en el desplegable de Estado (obligatorio y sin valor por
/// defecto en el alta de un proveedor, ver `Ajustes.defectos`).
Future<void> _eligeEstado(WidgetTester tester) async {
  final estado = find.byType(DesplegableBuscable).last;
  await tester.ensureVisible(estado);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: estado, matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Activo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('la tabla pinta las columnas NIT y Email con sus valores', (
    tester,
  ) async {
    _tamano(tester, const Size(1200, 800));
    await tester.pumpWidget(_pagina(repositorio: _RepositorioFalso()));
    await tester.pumpAndSettle();

    expect(find.text('Gestión de Proveedores (1)'), findsOneWidget);
    expect(find.text('NIT'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('1023456027'), findsOneWidget);
    expect(find.text('contactos@norte.com.bo'), findsOneWidget);
  });

  testWidgets('el alta incluye email y NIT en el cuerpo enviado a la API', (
    tester,
  ) async {
    _tamano(tester, const Size(1200, 1400));
    final repositorio = _RepositorioFalso();
    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nuevo Proveedor'));
    await tester.pumpAndSettle();

    // Orden del formulario: nombre, dirección, ciudad, teléfono, email, NIT.
    final campos = find.byType(TextFormField);
    expect(tester.widgetList<TextFormField>(campos), hasLength(6));
    await tester.enterText(campos.at(0), 'Textiles Andinos');
    await tester.enterText(campos.at(4), 'ventas@andinos.bo');
    await tester.enterText(campos.at(5), '3012345018');
    await _eligeEstado(tester);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
    await tester.pumpAndSettle();

    expect(repositorio.ultimoCuerpo?['nombre'], 'Textiles Andinos');
    expect(repositorio.ultimoCuerpo?['email'], 'ventas@andinos.bo');
    expect(repositorio.ultimoCuerpo?['nit'], '3012345018');
  });

  testWidgets('un email mal escrito bloquea el envío del formulario', (
    tester,
  ) async {
    _tamano(tester, const Size(1200, 1400));
    final repositorio = _RepositorioFalso();
    await tester.pumpWidget(_pagina(repositorio: repositorio));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nuevo Proveedor'));
    await tester.pumpAndSettle();

    final campos = find.byType(TextFormField);
    await tester.enterText(campos.at(0), 'Mala Forma');
    await tester.enterText(campos.at(4), 'sin-arroba');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Crear'));
    await tester.pumpAndSettle();

    expect(repositorio.ultimoCuerpo, isNull);
    expect(find.textContaining('correo válido'), findsOneWidget);
  });
}
