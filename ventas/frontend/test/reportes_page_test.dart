import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ventas/core/errors/failure.dart';
import 'package:ventas/domain/entities/reporte.dart';
import 'package:ventas/domain/repositories/reporte_repository.dart';
import 'package:ventas/domain/usecases/reporte_usecases.dart';
import 'package:ventas/presentation/controllers/informes_controller.dart';
import 'package:ventas/presentation/pages/reportes_page.dart';
import 'package:ventas/presentation/widgets/grafico_serie.dart';
import 'package:ventas/presentation/widgets/graficos_ranking.dart';
import 'package:ventas/presentation/widgets/vistas_estado.dart';

/// Doble de [ReporteRepository] con datos fijos.
///
/// * [espera] → las peticiones no se resuelven hasta completar el future
///   (para observar el estado de carga);
/// * [fallo] → mientras exista, los dos endpoints fallan;
/// * [vacio] → informe sin ventas (para los textos de tabla vacía).
final class _RepositorioFalso implements ReporteRepository {
  _RepositorioFalso({this.espera, this.fallo, this.vacio = false});

  Future<void>? espera;
  Object? fallo;
  final bool vacio;

  static const _resumen = ResumenVentas(
    total: 1234.5,
    ordenes: 3,
    unidades: 5,
    utilidad: 250,
  );

  Future<void> _esperar() => espera ?? Future<void>.value();

  @override
  Future<InformeVentas> ventasPorRango({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    await _esperar();
    final error = fallo;
    if (error != null) throw error;
    if (vacio) {
      return const InformeVentas(
        resumen: ResumenVentas(total: 0, ordenes: 0, unidades: 0),
        serie: [],
      );
    }
    return const InformeVentas(
      resumen: _resumen,
      serie: [
        PeriodoVenta(
          etiqueta: '2026-10-01',
          ordenes: 3,
          total: 1234.5,
          unidades: 5,
          utilidad: 250,
        ),
      ],
    );
  }

  @override
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    await _esperar();
    final error = fallo;
    if (error != null) throw error;
    if (vacio) {
      return const InformeProductos(productos: [], categorias: []);
    }
    return const InformeProductos(
      productos: [
        ProductoRango(
          productoId: 1,
          nombre: 'Aspirina 500mg',
          unidades: 3,
          monto: 30,
          categoria: 'Analgésicos',
        ),
        ProductoRango(
          productoId: 2,
          nombre: 'Ibuprofeno',
          unidades: 2,
          monto: 18.5,
          categoria: null,
        ),
      ],
      categorias: [
        VentaCategoria(nombre: 'Analgésicos', monto: 30, unidades: 3),
        VentaCategoria(nombre: null, monto: 18.5, unidades: 2),
      ],
    );
  }

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  }) async => const [];
}

Widget _pagina(InformesController controller) {
  return ChangeNotifierProvider<InformesController>.value(
    value: controller,
    child: MaterialApp(
      home: ReportesPage(selectedNav: 13, onNavSelect: _sinNavegacion),
    ),
  );
}

void _sinNavegacion(int _) {}

void main() {
  group('ReportesPage', () {
    testWidgets('pinta los 5 KPI y las tres tarjetas del informe', (
      tester,
    ) async {
      final controller =
          InformesController(Reportes(repository: _RepositorioFalso()))
            ..desde = DateTime(2026, 10, 1)
            ..hasta = DateTime(2026, 10, 3);

      await tester.pumpWidget(_pagina(controller));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // KPI: etiquetas del panel y el ticket medio (1234.5 / 3).
      expect(find.text('Total vendido'), findsOneWidget);
      expect(find.text('Órdenes pagadas'), findsOneWidget);
      expect(find.text('Ticket medio'), findsOneWidget);
      expect(find.text('Bs 411.50'), findsOneWidget);
      expect(find.text('Bs 1234.50'), findsWidgets);
      // Utilidad: la etiqueta del KPI + la cabecera de la tabla de la serie.
      expect(find.text('Utilidad'), findsNWidgets(2));
      // KPI + fila del periodo + fila «Total del rango».
      expect(find.text('Bs 250.00'), findsNWidgets(3));

      // Tarjetas: serie, productos y categorías.
      expect(find.byType(GraficoSerie), findsOneWidget);
      expect(find.byType(GraficoHorizontal), findsOneWidget);
      expect(find.text('Productos más vendidos'), findsOneWidget);
      expect(find.text('Reparto por categorías'), findsOneWidget);
      expect(find.text('Total del rango'), findsOneWidget);
      expect(find.text('Aspirina 500mg'), findsWidgets);
      expect(find.text('(sin categoría)'), findsWidgets);
      // 30 / 1234.5 = 2,4% (el reparto se calcula sobre el total del rango).
      expect(find.text('2.4%'), findsOneWidget);
    });

    testWidgets('estado de carga inicial: VistaCargando', (tester) async {
      final controller = InformesController(
        Reportes(
          repository: _RepositorioFalso(espera: Completer<void>().future),
        ),
      );

      await tester.pumpWidget(_pagina(controller));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(VistaError), findsNothing);
    });

    testWidgets('error sin datos: VistaError y «Reintentar» recupera', (
      tester,
    ) async {
      final repo = _RepositorioFalso(
        fallo: const ServerFailure('Sin conexión con el servidor'),
      );
      final controller = InformesController(Reportes(repository: repo))
        ..desde = DateTime(2026, 10, 1)
        ..hasta = DateTime(2026, 10, 3);

      await tester.pumpWidget(_pagina(controller));
      await tester.pumpAndSettle();

      expect(find.byType(VistaError), findsOneWidget);
      expect(
        find.textContaining('Error: Sin conexión con el servidor'),
        findsOneWidget,
      );

      // El servidor vuelve: Reintentar pide el informe otra vez.
      repo.fallo = null;
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(VistaError), findsNothing);
      expect(find.text('Total vendido'), findsOneWidget);
    });

    testWidgets('sin ventas: cada tarjeta escribe su propio texto y las '
        'exportaciones quedan deshabilitadas', (tester) async {
      final controller =
          InformesController(
              Reportes(repository: _RepositorioFalso(vacio: true)),
            )
            ..desde = DateTime(2026, 10, 1)
            ..hasta = DateTime(2026, 10, 3);

      await tester.pumpWidget(_pagina(controller));
      await tester.pumpAndSettle();

      expect(find.text('Sin ventas en este rango'), findsOneWidget);
      expect(
        find.text('Sin ventas de productos en este rango'),
        findsOneWidget,
      );
      expect(
        find.text('Sin ventas por categorías en este rango'),
        findsOneWidget,
      );
      expect(find.byType(VistaError), findsNothing);

      final csv = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'CSV'),
      );
      final pdf = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'PDF'),
      );
      expect(csv.onPressed, isNull);
      expect(pdf.onPressed, isNull);
    });

    testWidgets('error al actualizar con datos: banner naranja sin vaciar el '
        'informe', (tester) async {
      final repo = _RepositorioFalso();
      final controller = InformesController(Reportes(repository: repo))
        ..desde = DateTime(2026, 10, 1)
        ..hasta = DateTime(2026, 10, 3);

      await tester.pumpWidget(_pagina(controller));
      await tester.pumpAndSettle();
      expect(find.text('Total vendido'), findsOneWidget);

      repo.fallo = const ServerFailure('503');
      await controller.cargar();
      await tester.pumpAndSettle();

      expect(find.textContaining('No se pudo actualizar: 503'), findsOneWidget);
      // Los datos siguen en pantalla.
      expect(find.text('Total vendido'), findsOneWidget);
      expect(find.byType(VistaError), findsNothing);

      repo.fallo = null;
      await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo actualizar'), findsNothing);
      expect(find.text('Total vendido'), findsOneWidget);
    });
  });
}
