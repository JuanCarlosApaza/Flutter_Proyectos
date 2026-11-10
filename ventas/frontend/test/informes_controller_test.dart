import 'package:flutter_test/flutter_test.dart';

import 'package:ventas/core/errors/failure.dart';
import 'package:ventas/core/fechas.dart';
import 'package:ventas/domain/entities/reporte.dart';
import 'package:ventas/domain/repositories/reporte_repository.dart';
import 'package:ventas/domain/usecases/reporte_usecases.dart';
import 'package:ventas/presentation/controllers/informes_controller.dart';
import 'package:ventas/presentation/controllers/load_state.dart';

/// Doble de [ReporteRepository]: cuenta las peticiones de cada endpoint y
/// devuelve un informe fijo (o falla mientras `fallo` esté activo).
final class _RepositorioFalso implements ReporteRepository {
  Object? fallo;
  List<PeriodoVenta> serie = const [];

  int llamadasInforme = 0;
  int llamadasProductos = 0;
  DateTime? ultimoDesde;
  DateTime? ultimoHasta;
  String? ultimaAgrupacion;

  void reiniciarContadores() {
    llamadasInforme = 0;
    llamadasProductos = 0;
  }

  @override
  Future<InformeVentas> ventasPorRango({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    llamadasInforme++;
    ultimoDesde = desde;
    ultimoHasta = hasta;
    ultimaAgrupacion = agrupacion;
    final error = fallo;
    if (error != null) throw error;
    return InformeVentas(
      resumen: const ResumenVentas(total: 0, ordenes: 0, unidades: 0),
      serie: serie,
    );
  }

  @override
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    llamadasProductos++;
    final error = fallo;
    if (error != null) throw error;
    return const InformeProductos(productos: [], categorias: []);
  }

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    int limite = 6,
    String orden = 'desc',
  }) async => const [];
}

void main() {
  group('InformesController: filtros', () {
    late _RepositorioFalso repo;
    late InformesController controller;

    setUp(() {
      repo = _RepositorioFalso();
      controller = InformesController(
        Reportes(repository: repo),
        // Reloj fijo: 8 de octubre de 2026 a mediodía.
        ahora: () => DateTime(2026, 10, 8, 12),
      );
    });

    tearDown(() => controller.dispose());

    test('arranca en «Este mes» y en estado initial', () {
      expect(controller.state, LoadState.initial);
      expect(fechaCorta(controller.desde), '2026-10-01');
      expect(fechaCorta(controller.hasta), '2026-10-08');
      expect(controller.atajoActivo, AtajoRango.mes);
      expect(controller.agrupacion, 'dia');
      expect(controller.hayDatos, isFalse);
    });

    test('los atajos calculan su rango y se resaltan solo si coinciden', () {
      controller.aplicarAtajo(AtajoRango.ayer);
      expect(fechaCorta(controller.desde), '2026-10-07');
      expect(fechaCorta(controller.hasta), '2026-10-07');
      expect(controller.atajoActivo, AtajoRango.ayer);

      // Semana natural: lunes 5 → domingo 8.
      controller.aplicarAtajo(AtajoRango.semana);
      expect(fechaCorta(controller.desde), '2026-10-05');
      expect(fechaCorta(controller.hasta), '2026-10-08');

      controller.aplicarAtajo(AtajoRango.anio);
      expect(fechaCorta(controller.desde), '2026-01-01');
      expect(controller.atajoActivo, AtajoRango.anio);

      // Un rango elegido a mano no resalta ningún atajo.
      controller.cambiarHasta(DateTime(2026, 9, 30));
      expect(controller.atajoActivo, isNull);
    });

    test(
      'cada cambio de filtro hace UNA sola consulta de los dos endpoints',
      () async {
        await controller.cargar();
        expect(repo.llamadasInforme, 1);
        expect(repo.llamadasProductos, 1);

        // Cambiar UN extremo (el picker) → una consulta, con el rango nuevo.
        repo.reiniciarContadores();
        controller.cambiarDesde(DateTime(2026, 10, 5));
        await pumpEventQueue();
        expect(repo.llamadasInforme, 1);
        expect(repo.llamadasProductos, 1);
        expect(fechaCorta(repo.ultimoDesde!), '2026-10-05');
        expect(fechaCorta(repo.ultimoHasta!), '2026-10-08');

        // Cambiar la agrupación → otra consulta, una sola.
        repo.reiniciarContadores();
        controller.cambiarAgrupacion('mes');
        await pumpEventQueue();
        expect(repo.llamadasInforme, 1);
        expect(repo.llamadasProductos, 1);
        expect(repo.ultimaAgrupacion, 'mes');

        // Un atajo cambia los DOS extremos pero también pide una sola vez.
        repo.reiniciarContadores();
        controller.aplicarAtajo(AtajoRango.hoy);
        await pumpEventQueue();
        expect(repo.llamadasInforme, 1);
        expect(fechaCorta(repo.ultimoDesde!), '2026-10-08');
        expect(fechaCorta(repo.ultimoHasta!), '2026-10-08');
      },
    );

    test('elegir la agrupación que ya estaba no vuelve a consultar', () async {
      await controller.cargar();
      repo.reiniciarContadores();
      controller.cambiarAgrupacion('dia');
      await pumpEventQueue();
      expect(repo.llamadasInforme, 0);
    });

    test('el rango nunca queda invertido: el otro extremo se acerca', () async {
      await controller.cargar();
      controller.cambiarDesde(DateTime(2026, 12, 20));
      expect(fechaCorta(controller.hasta), '2026-12-20');

      controller.cambiarHasta(DateTime(2026, 1, 2));
      expect(fechaCorta(controller.desde), '2026-01-02');
      expect(controller.hasta.isBefore(controller.desde), isFalse);
    });

    test('rellena con ceros los periodos que el servidor no manda', () async {
      controller
        ..desde = DateTime(2026, 10, 1)
        ..hasta = DateTime(2026, 10, 3);
      // El servidor solo trae el día con ventas.
      repo.serie = const [
        PeriodoVenta(
          etiqueta: '2026-10-02',
          ordenes: 1,
          total: 30,
          unidades: 2,
          utilidad: 40,
        ),
      ];

      await controller.cargar();

      expect(controller.informe!.serie.map((p) => p.etiqueta), [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
      ]);
      expect(controller.informe!.serie.first.total, 0);
      expect(controller.informe!.serie.last.ordenes, 0);
      // Los huecos rellenan con 0 y el día real conserva su utilidad.
      expect(controller.informe!.serie.first.utilidad, 0);
      expect(controller.informe!.serie[1].utilidad, 40);
    });
  });

  group('InformesController: estados', () {
    late _RepositorioFalso repo;
    late InformesController controller;

    setUp(() {
      repo = _RepositorioFalso();
      controller = InformesController(
        Reportes(repository: repo),
        ahora: () => DateTime(2026, 10, 8, 12),
      );
    });

    tearDown(() => controller.dispose());

    test('error sin datos: estado de error con el motivo', () async {
      repo.fallo = const ServerFailure('Sin conexión con el servidor');

      await controller.cargar();

      expect(controller.state, LoadState.error);
      expect(controller.errorMessage, 'Sin conexión con el servidor');
      expect(controller.hayDatos, isFalse);
      expect(controller.avisoRefresco, isNull);
    });

    test(
      'error al actualizar con datos previos: no vacía nada y avisa',
      () async {
        await controller.cargar();
        final informePrevio = controller.informe;

        repo.fallo = const ServerFailure('El servidor está caído');
        await controller.cargar();

        expect(controller.state, LoadState.loaded);
        expect(controller.informe, same(informePrevio));
        expect(
          controller.avisoRefresco,
          'No se pudo actualizar: El servidor está caído',
        );

        // Una consulta correcta limpia el aviso.
        repo.fallo = null;
        await controller.cargar();
        expect(controller.avisoRefresco, isNull);

        // Y el usuario también puede cerrarlo a mano.
        repo.fallo = const ServerFailure('Otra vez caído');
        await controller.cargar();
        controller.cerrarAviso();
        expect(controller.avisoRefresco, isNull);
        expect(controller.hayDatos, isTrue);
      },
    );

    test('un fallo no esperado también se traduce a mensaje', () async {
      repo.fallo = StateError('boom');
      await controller.cargar();
      expect(controller.state, LoadState.error);
      expect(controller.errorMessage, contains('Error inesperado'));
    });
  });
}
