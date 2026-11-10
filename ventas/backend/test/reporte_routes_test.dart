import 'dart:convert';

import 'package:ventas_backend/src/domain/entities/reporte.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/repositories/reporte_repository.dart';
import 'package:ventas_backend/src/domain/usecases/reporte_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/reporte_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Doble en memoria del repositorio: devuelve un informe fijo y anota las
/// llamadas para comprobar los parámetros que llegan desde la URL.
///
/// El SQL ya tiene su sitio en `reporte_sqlite_test.dart` (se ejecuta contra
/// una BD real); aquí se comprueba la capa HTTP: permisos, códigos, lectura
/// de query y forma de la respuesta.
class _FakeReporteRepository implements ReporteRepository {
  int llamadas = 0;
  DateTime? desde;
  DateTime? hasta;
  String? agrupacion;

  @override
  Future<List<VentaProducto>> ventasPorProducto({
    required int limite,
    required bool descendente,
  }) async {
    llamadas++;
    return [
      VentaProducto(productoId: 1, nombre: 'Aspirina', unidades: 3, monto: 30),
    ];
  }

  @override
  Future<InformeVentas> ventasPorPeriodo({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) async {
    llamadas++;
    this.desde = desde;
    this.hasta = hasta;
    this.agrupacion = agrupacion;
    return InformeVentas.resumiendo(const [
      PeriodoVenta(
        etiqueta: '2026-10-01',
        ordenes: 1,
        total: 27.5,
        unidades: 2.5,
        utilidad: 8,
      ),
      PeriodoVenta(
        etiqueta: '2026-10-03',
        ordenes: 1,
        total: 10,
        unidades: 1,
        utilidad: 6,
      ),
    ]);
  }

  @override
  Future<InformeProductos> productosPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    llamadas++;
    this.desde = desde;
    this.hasta = hasta;
    return const InformeProductos(
      productos: [
        ProductoRango(
          productoId: 1,
          nombre: 'Aspirina',
          unidades: 3,
          monto: 30,
          categoria: 'Analgésicos',
        ),
        ProductoRango(
          productoId: 2,
          nombre: 'Pan',
          unidades: 0.5,
          monto: 7.5,
          categoria: null,
        ),
      ],
      categorias: [
        VentaCategoria(nombre: 'Analgésicos', monto: 30, unidades: 3),
        VentaCategoria(nombre: null, monto: 7.5, unidades: 0.5),
      ],
    );
  }
}

void main() {
  late _FakeReporteRepository repo;
  late Handler handler;

  Handler montar() {
    final router = Router();
    addReporteRoutes(router, reportes: Reportes(repository: repo));
    return errorHandler()(router.call);
  }

  Request conSesion({
    Set<String> permisos = const {},
    String ruta = '/api/v1/reportes/ventas',
  }) {
    final usuario = usuarioDePrueba(permisos: permisos);
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    return Request(
      'GET',
      Uri.parse('http://localhost$ruta'),
    ).change(context: {'sesion': sesion});
  }

  Future<Map<String, Object?>> cuerpo(Response respuesta) async =>
      jsonDecode(await respuesta.readAsString()) as Map<String, Object?>;

  const rango = '/api/v1/reportes/ventas?desde=2026-10-01&hasta=2026-10-31';

  setUp(() {
    repo = _FakeReporteRepository();
    handler = montar();
  });

  group('GET /api/v1/reportes/ventas', () {
    test('devuelve resumen y serie con `reportes.ver`', () async {
      final respuesta = await handler(
        conSesion(permisos: {'reportes.ver'}, ruta: '$rango&agrupacion=dia'),
      );

      expect(respuesta.statusCode, 200);
      final json = await cuerpo(respuesta);
      expect(json.keys, containsAll(['resumen', 'serie']));
      final resumen = json['resumen']! as Map<String, Object?>;
      expect(resumen['ordenes'], 2);
      expect(resumen['total'], 37.5);
      // Utilidad del rango: la suma de la serie (8 + 6).
      expect(resumen['utilidad'], 14);
      expect(json['serie'], hasLength(2));
      final serie = json['serie']! as List;
      expect((serie.first! as Map<String, Object?>)['utilidad'], 8);
      expect((serie.last! as Map<String, Object?>)['utilidad'], 6);

      // El rango llega a dominio como fechas (incluidas) y con la
      // agrupación pedida.
      expect(repo.desde, DateTime(2026, 10, 1));
      expect(repo.hasta, DateTime(2026, 10, 31));
      expect(repo.agrupacion, 'dia');
    });

    test('sin `reportes.ver` → 403 permiso_denegado', () async {
      final respuesta = await handler(conSesion(ruta: rango));

      expect(respuesta.statusCode, 403);
      expect(await respuesta.readAsString(), contains('permiso_denegado'));
    });

    test('`dashboard.ver` ya no abre los reportes', () async {
      final respuesta = await handler(
        conSesion(permisos: {'dashboard.ver'}, ruta: rango),
      );

      expect(respuesta.statusCode, 403);
    });

    test('falta `desde` → 400 fecha_invalida', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'reportes.ver'},
          ruta: '/api/v1/reportes/ventas?hasta=2026-10-31',
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('fecha_invalida'));
      expect(repo.llamadas, 0);
    });

    test('agrupación desconocida → 400 agrupacion_invalida', () async {
      final respuesta = await handler(
        conSesion(permisos: {'reportes.ver'}, ruta: '$rango&agrupacion=semana'),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('agrupacion_invalida'));
    });

    test('rango invertido → 400 rango_invalido', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'reportes.ver'},
          ruta:
              '/api/v1/reportes/ventas'
              '?desde=2026-11-01&hasta=2026-10-01',
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('rango_invalido'));
    });
  });

  group('GET /api/v1/reportes/ventas-productos', () {
    test('devuelve productos y categorías', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'reportes.ver'},
          ruta:
              '/api/v1/reportes/ventas-productos'
              '?desde=2026-10-01&hasta=2026-10-31',
        ),
      );

      expect(respuesta.statusCode, 200);
      final json = await cuerpo(respuesta);
      final productos = json['productos']! as List;
      expect(productos, hasLength(2));
      expect(productos.first, containsPair('categoria', 'Analgésicos'));
      expect(productos.last, containsPair('categoria', null));

      final categorias = json['categorias']! as List;
      expect(categorias, hasLength(2));
      expect(categorias.last, containsPair('nombre', null));
    });

    test('sin `reportes.ver` → 403', () async {
      final respuesta = await handler(
        conSesion(
          ruta:
              '/api/v1/reportes/ventas-productos'
              '?desde=2026-10-01&hasta=2026-10-31',
        ),
      );

      expect(respuesta.statusCode, 403);
    });
  });

  group('GET /api/v1/reportes/productos-vendidos', () {
    test('el ranking del dashboard exige `reportes.ver`', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'reportes.ver'},
          ruta: '/api/v1/reportes/productos-vendidos?limite=6&orden=desc',
        ),
      );

      expect(respuesta.statusCode, 200);
      final json = await cuerpo(respuesta);
      expect(json['total'], 1);
      expect(
        (json['items']! as List).first,
        containsPair('nombre', 'Aspirina'),
      );
    });

    test('orden y límite inválidos → 400', () async {
      final orden = await handler(
        conSesion(
          permisos: {'reportes.ver'},
          ruta: '/api/v1/reportes/productos-vendidos?orden=loquesea',
        ),
      );
      expect(orden.statusCode, 400);

      final limite = await handler(
        conSesion(
          permisos: {'reportes.ver'},
          ruta: '/api/v1/reportes/productos-vendidos?limite=999',
        ),
      );
      expect(limite.statusCode, 400);
    });
  });
}
