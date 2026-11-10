import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ventas/domain/entities/reporte.dart';
import 'package:ventas/domain/repositories/reporte_repository.dart';
import 'package:ventas/domain/usecases/reporte_usecases.dart';
import 'package:ventas/presentation/controllers/informe_controller.dart';
import 'package:ventas/presentation/pages/reportes_page.dart';

/// Doble de repositorio: devuelve siempre el mismo informe y anota la
/// última petición, para comprobar que los filtros que se ven en la barra
/// de herramientas llegan al servidor tal cual.
class _RepositorioInforme implements ReporteRepository {
  _RepositorioInforme({this.fallar = false});

  /// `true` = los dos informes fallan (para el estado de error).
  final bool fallar;

  int llamadas = 0;
  ({DateTime desde, DateTime hasta, String agrupacion})? ultima;

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  }) async => const [];

  @override
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    llamadas++;
    ultima = (desde: desde, hasta: hasta, agrupacion: agrupacion);
    if (fallar) throw Exception('sin red');

    return InformeVentas(
      desde: _dia(desde),
      hasta: _dia(hasta),
      agrupacion: agrupacion,
      resumen: const ResumenVentas(total: 220, ordenes: 4, unidades: 6),
      serie: [
        VentaPeriodo(
          etiqueta: _etiqueta(desde, agrupacion),
          ordenes: 4,
          total: 220,
          unidades: 6,
        ),
      ],
    );
  }

  @override
  Future<InformeProductos> ventasPorProductoYCategoria({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    if (fallar) throw Exception('sin red');
    return const InformeProductos(
      productos: [
        VentaProducto(
          productoId: 1,
          nombre: 'Jeans mezclillo',
          unidades: 4,
          monto: 140,
          categoria: 'Pantalones',
        ),
        VentaProducto(
          productoId: 2,
          nombre: 'Camisa Oxford',
          unidades: 1,
          monto: 50,
          categoria: 'Camisas',
        ),
      ],
      categorias: [
        VentaCategoria(nombre: 'Pantalones', unidades: 4, monto: 140),
        VentaCategoria(nombre: 'Camisas', unidades: 1, monto: 50),
      ],
    );
  }
}

void main() {
  /// Monta la pantalla (superficie alta: la barra tiene 10 controles) y
  /// devuelve su repositorio para inspeccionar las peticiones.
  Future<_RepositorioInforme> preparar(
    WidgetTester tester, {
    bool fallar = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repositorio = _RepositorioInforme(fallar: fallar);
    final informe = InformeController(Reportes(repository: repositorio));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InformeController>.value(value: informe),
        ],
        child: const MaterialApp(home: ReportesPage()),
      ),
    );
    await tester.pumpAndSettle();
    return repositorio;
  }

  testWidgets('carga el informe del mes en curso y pinta las tres tablas', (
    tester,
  ) async {
    final repositorio = await preparar(tester);

    // Rango por defecto: del día 1 del mes a hoy, agrupado por día.
    expect(repositorio.llamadas, 1);
    expect(repositorio.ultima?.agrupacion, 'dia');
    expect(repositorio.ultima?.desde.day, 1);
    final hoy = DateTime.now();
    expect(
      repositorio.ultima?.hasta,
      DateTime(hoy.year, hoy.month, hoy.day),
    );

    expect(find.text('Reportes de ventas'), findsOneWidget);

    // KPIs del resumen (el total también aparece en la fila de la serie).
    expect(find.text('Bs 220.00'), findsWidgets); // total
    expect(find.text('Bs 55.00'), findsOneWidget); // ticket medio
    expect(find.text('Órdenes pagadas'), findsOneWidget);

    // Serie, productos y categorías.
    expect(find.text('Ventas por día'), findsOneWidget);
    expect(find.text('Jeans mezclillo'), findsWidgets);
    expect(find.text('Camisa Oxford'), findsWidgets);
    expect(find.text('Pantalones'), findsWidgets);
    expect(find.text('Reparto por categoría'), findsOneWidget);
    expect(find.text('Bs 140.00'), findsWidgets);

    // El último día del rango sale en la tabla aunque el doble solo
    // devuelva datos del primero: los huecos se rellenan con ceros.
    expect(find.text(_dia(hoy)), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el atajo «Ayer» cambia el rango y repide el informe', (
    tester,
  ) async {
    final repositorio = await preparar(tester);

    await tester.tap(find.text('Ayer'));
    await tester.pumpAndSettle();

    expect(repositorio.llamadas, 2);
    final hoy = DateTime.now();
    final ayer = DateTime(hoy.year, hoy.month, hoy.day - 1);
    expect(repositorio.ultima?.desde, ayer);
    expect(repositorio.ultima?.hasta, ayer);
  });

  testWidgets('cambiar a «Mes» agrupa por mes sin tocar el rango', (
    tester,
  ) async {
    final repositorio = await preparar(tester);
    final rango = repositorio.ultima;

    await tester.tap(find.text('Mes'));
    await tester.pumpAndSettle();

    expect(repositorio.llamadas, 2);
    expect(repositorio.ultima?.agrupacion, 'mes');
    expect(repositorio.ultima?.desde, rango?.desde);
    expect(repositorio.ultima?.hasta, rango?.hasta);
    expect(find.text('Ventas por mes'), findsOneWidget);
  });

  testWidgets('acortar «Hasta» por debajo del «Desde» arrastra el «Desde»', (
    tester,
  ) async {
    final repositorio = await preparar(tester);

    // Rango de un solo día: «Hasta» no puede bajar sin arrastrar «Desde».
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
    expect(repositorio.llamadas, 2);

    await tester.tap(find.textContaining('Hasta'));
    await tester.pumpAndSettle();

    final calendario = find.byType(CalendarDatePicker);
    expect(calendario, findsOneWidget);
    final inicial =
        tester.widget<CalendarDatePicker>(calendario).initialDate ??
        DateTime.now();
    // Día 1 del mes visible: siempre anterior al rango de «Hoy» salvo que
    // hoy sea el día 1 (entonces no se arrastra y el rango no cambia).
    final primero = DateTime(inicial.year, inicial.month, 1);
    if (primero.isBefore(inicial)) {
      // El «1» del calendario (la tabla de reportes también numera filas,
      // así que el buscador se limita al diálogo).
      await tester.tap(
        find.descendant(of: calendario, matching: find.text('1')).first,
      );
      await tester.pumpAndSettle();
      final aceptar = find.text('Aceptar');
      final ok = aceptar.evaluate().isEmpty ? find.text('OK') : aceptar;
      expect(ok, findsOneWidget);
      await tester.tap(ok);
      await tester.pumpAndSettle();

      expect(repositorio.llamadas, 3);
      expect(repositorio.ultima?.hasta, primero);
      expect(
        repositorio.ultima!.desde.isAfter(repositorio.ultima!.hasta),
        isFalse,
      );
    } else {
      // El día 1 es hoy: cerrar sin cambios no debe pedir nada más.
      expect(repositorio.llamadas, 2);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('un error deja el aviso con botón de reintentar', (tester) async {
    await preparar(tester, fallar: true);

    expect(find.textContaining('Error inesperado'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la barra trae los atajos y los dos botones de exportación', (
    tester,
  ) async {
    await preparar(tester);

    for (final atajo in ['Hoy', 'Ayer', 'Esta semana', 'Este mes', 'Este año']) {
      expect(find.text(atajo), findsOneWidget);
    }
    final csv = find.widgetWithText(OutlinedButton, 'CSV');
    final pdf = find.widgetWithText(OutlinedButton, 'PDF');
    expect(csv, findsOneWidget);
    expect(pdf, findsOneWidget);
    expect(tester.widget<OutlinedButton>(csv).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(pdf).onPressed, isNotNull);
  });
}

String _dia(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// Etiqueta del periodo en la que agrupa el servidor (misma regla).
String _etiqueta(DateTime fecha, String agrupacion) => switch (agrupacion) {
  'mes' => '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}',
  'anio' => '${fecha.year}',
  _ => _dia(fecha),
};
