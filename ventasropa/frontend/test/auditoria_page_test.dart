import 'package:ventas/core/widgets/nav_scope.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/pages/auditoria_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Doble que registra los últimos parámetros del listado y de la purga.
final class _RepositorioCaptura implements RecursoRepository {
  Map<String, String>? ultimoFiltros;
  String? ultimaRutaListado;
  String? ultimaRutaEliminada;
  int llamadasListado = 0;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    llamadasListado++;
    ultimaRutaListado = recurso;
    ultimoFiltros = filtros;
    const fuente = <Recurso>[];
    return ListadoRecurso(
      total: fuente.length,
      items: fuente.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> obtener(String ruta) => throw UnimplementedError();

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) async {
    ultimaRutaEliminada = ruta;
  }
}

void main() {
  group('AuditoriaController', () {
    late _RepositorioCaptura repo;
    late AuditoriaController controller;

    setUp(() {
      repo = _RepositorioCaptura();
      controller = AuditoriaController(Crud(repository: repo));
    });

    test('buscar monta los filtros de servidor (usuario y fechas)', () async {
      await controller.buscar(
        usuario: '  ana  ',
        desde: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 30),
      );

      expect(repo.ultimaRutaListado, 'auditoria');
      expect(repo.ultimoFiltros, {
        'usuario': 'ana',
        'desde': '2026-09-01',
        'hasta': '2026-09-30',
      });
    });

    test('buscar por entidad y acción (¿quién ocultó productos?)', () async {
      await controller.buscar(entidad: 'productos', accion: 'ELIMINAR');
      expect(repo.ultimoFiltros, {
        'entidad': 'productos',
        'accion': 'ELIMINAR',
      });

      await controller.limpiarFiltros();
      await controller.buscar(entidad: 'productos', accion: 'CREAR');
      expect(repo.ultimoFiltros, {'entidad': 'productos', 'accion': 'CREAR'});
    });

    test('buscar sin nada no envía filtros', () async {
      await controller.buscar(usuario: '   ');
      expect(repo.ultimoFiltros, isNull);
    });

    test('limpiarFiltros quita los filtros y recarga', () async {
      await controller.buscar(usuario: 'ana');
      await controller.limpiarFiltros();
      expect(repo.ultimoFiltros, isNull);
    });

    test('limpiarAntesDe purga por la ruta con la fecha yyyy-MM-dd', () async {
      await controller.limpiarAntesDe(DateTime(2026, 3, 5));
      expect(repo.ultimaRutaEliminada, 'auditoria/antes-de/2026-03-05');
    });

    test('vaciar purga por la ruta auditoria/todo', () async {
      await controller.vaciar();
      expect(repo.ultimaRutaEliminada, 'auditoria/todo');
    });
  });

  group('AuditoriaPage', () {
    testWidgets('pinta cabecera, toolbar y estado vacío (solo lectura)', (
      tester,
    ) async {
      final controller = AuditoriaController(
        Crud(repository: _RepositorioCaptura()),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuditoriaController>.value(
          value: controller,
          child: MaterialApp(
            home: AuditoriaPage(selectedNav: 10, onNavSelect: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // PageHeader pinta el contador: "Auditoría de cambios (0)".
      expect(find.textContaining('Auditoría de cambios'), findsOneWidget);
      expect(find.text('Sin registros de auditoría'), findsOneWidget);

      // Toolbar de búsqueda por usuario, fecha, entidad y acción.
      expect(find.text('Usuario'), findsOneWidget);
      expect(find.text('Desde'), findsOneWidget);
      expect(find.text('Hasta'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
      expect(find.text('Entidad'), findsOneWidget);
      expect(find.text('Acción'), findsOneWidget);

      // Solo lectura: no hay botón de alta.
      expect(find.textContaining('Nuevo'), findsNothing);

      // Limpieza disponible (sin sesión en el test → visible por defecto).
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);
    });

    testWidgets('se recarga al volver a la pestaña y con «Actualizar»', (
      tester,
    ) async {
      final repo = _RepositorioCaptura();
      final controller = AuditoriaController(Crud(repository: repo));
      final nav = ValueNotifier<int>(0);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuditoriaController>.value(
          value: controller,
          child: MaterialApp(
            home: NavScope(
              seleccionado: nav,
              onSeleccionar: (i) => nav.value = i,
              child: AuditoriaPage(selectedNav: 10, onNavSelect: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.llamadasListado, 1); // carga inicial

      nav.value = 3; // se va a otro módulo
      await tester.pumpAndSettle();
      expect(repo.llamadasListado, 1); // no recarga estando fuera

      nav.value = 10; // vuelve a Auditoría
      await tester.pumpAndSettle();
      expect(repo.llamadasListado, 2); // ← refresco al volver

      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();
      expect(repo.llamadasListado, 3);
    });
  });
}
