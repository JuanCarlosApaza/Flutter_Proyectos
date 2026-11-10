import 'package:farmacia/core/errors/failure.dart';
import 'package:farmacia/core/widgets/sidebar.dart';
import 'package:farmacia/domain/entities/recurso.dart';
import 'package:farmacia/domain/repositories/recurso_repository.dart';
import 'package:farmacia/domain/usecases/crud.dart';
import 'package:farmacia/presentation/controllers/recurso_controller.dart';
import 'package:farmacia/presentation/pages/clientes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Doble en memoria del repositorio (sin tocar la red).
class _RepositorioFalso implements RecursoRepository {
  _RepositorioFalso({this.fallar = false})
    : registros = [
        for (var i = 1; i <= 12; i++)
          Recurso.fromJson({
            'id': i,
            'nombre': 'Cliente ${i.toString().padLeft(2, '0')}',
            'ci': '404040$i',
            'ciudad': 'Lima',
            'telefono': '999888$i',
            'estado': i.isEven ? 'ACTIVO' : 'INACTIVO',
          }),
      ];

  bool fallar;
  final List<Recurso> registros;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    if (fallar) throw const NetworkFailure('El servidor no responde');
    final fuente = estado == null
        ? registros
        : registros.where((r) => r.texto('estado') == estado).toList();
    return ListadoRecurso(
      total: fuente.length,
      items: fuente.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

Widget _pagina({required RecursoRepository repositorio}) {
  return ChangeNotifierProvider<ClientesController>.value(
    value: ClientesController(Crud(repository: repositorio)),
    child: MaterialApp(home: ClientesPage(selectedNav: 2, onNavSelect: (_) {})),
  );
}

void _tamano(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('desktop: sidebar, tabla completa y paginación', (tester) async {
    _tamano(tester, const Size(1200, 800));
    await tester.pumpWidget(_pagina(repositorio: _RepositorioFalso()));
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('Gestión de Clientes (12)'), findsOneWidget);
    expect(find.text('Nombre'), findsOneWidget);
    expect(find.text('Cliente 01'), findsOneWidget);
    expect(find.text('Cliente 11'), findsNothing);

    // Paginación: 12 registros -> 2 páginas de 10 (queda bajo el pliegue).
    await tester.ensureVisible(find.text('2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente 11'), findsOneWidget);
  });

  testWidgets('móvil: bottom nav y tarjetas apiladas', (tester) async {
    _tamano(tester, const Size(390, 844));
    await tester.pumpWidget(_pagina(repositorio: _RepositorioFalso()));
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Gestión de Clientes (12)'), findsOneWidget);
    expect(find.text('CI: '), findsWidgets);
    expect(find.text('Cliente 01'), findsOneWidget);
  });

  testWidgets('error de red: muestra el estado de error con Reintentar', (
    tester,
  ) async {
    _tamano(tester, const Size(1200, 800));
    await tester.pumpWidget(
      _pagina(repositorio: _RepositorioFalso(fallar: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Error: El servidor no responde'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
