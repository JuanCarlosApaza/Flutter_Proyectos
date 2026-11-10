import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/repositories/reporte_repository_impl.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/usecases/reporte_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/reporte_routes.dart';

import 'fakes.dart';

/// Rutas HTTP de los informes (`/reportes/ventas` y
/// `/reportes/ventas-productos`) sobre una base SQLite recién migrada.
///
/// Lo que se cubre aquí —lo que `reporte_periodo_test` no ve, porque llama al
/// caso de uso sin pasar por la red—:
///
/// * **sesión y permisos**: sin sesión `401`, con sesión pero sin
///   `reportes.ver` → `403 permiso_denegado`, y `productos-vendidos` sigue
///   exigiendo `dashboard.ver` (no se «hereda» el del nuevo módulo);
/// * el paso de los **query parameters** al caso de uso (rango, agrupación y
///   sus `400`);
/// * la **forma del JSON** que consume la pantalla de Reportes.
void main() {
  late Directory dir;
  late SqliteDatabase db;
  late Handler handler;

  Future<int> insertar(String sql, List<Object?> params) async {
    final filas = await db.query(sql, params);
    return filas.first.values.first as int;
  }

  Future<void> linea(
    int orden, {
    required int producto,
    required int variante,
    required int cantidad,
    required double monto,
  }) => db.query(
    'INSERT INTO detalles_ordenes_pedidos '
    '(producto_id, orden_id, variante_id, nombre_producto, cantidad, '
    'precio_venta, monto_total, estado) '
    'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \'ACTIVO\')',
    [producto, orden, variante, 'producto', cantidad, monto, monto],
  );

  /// Dos ventas (una con producto sin categoría) y una pendiente que no
  /// debe contar.
  Future<void> sembrar() async {
    final categoria = await insertar(
      'INSERT INTO categorias (nombre_categoria) VALUES (\$1) '
      'RETURNING categoria_id',
      ['Pantalones'],
    );
    final talla = await insertar(
      'INSERT INTO tallas (nombre) VALUES (\$1) RETURNING talla_id',
      ['M'],
    );
    final color = await insertar(
      'INSERT INTO colores (nombre) VALUES (\$1) RETURNING color_id',
      ['Negro'],
    );

    Future<(int, int)> producto(String nombre, int? cat) async {
      final id = await insertar(
        'INSERT INTO productos (nombre_producto, precio_venta, stock, '
        'categoria_id) VALUES (\$1, \$2, \$3, \$4) RETURNING producto_id',
        [nombre, 50, 10, cat],
      );
      final variante = await insertar(
        'INSERT INTO producto_variantes (producto_id, talla_id, color_id, '
        'stock) VALUES (\$1, \$2, \$3, \$4) RETURNING variante_id',
        [id, talla, color, 10],
      );
      return (id, variante);
    }

    final jeans = await producto('Jeans mezclillo', categoria);
    final gorra = await producto('Gorra deportiva', null);

    Future<int> orden(String fecha, String estado, double total) => insertar(
      'INSERT INTO ordenes_pedidos (fecha_orden, estado, total) '
      'VALUES (\$1, \$2, \$3) RETURNING orden_id',
      [fecha, estado, total],
    );

    final pagada1 = await orden('2026-10-01 20:30:00', 'PAGADO', 100);
    await linea(
      pagada1,
      producto: jeans.$1,
      variante: jeans.$2,
      cantidad: 2,
      monto: 100,
    );

    final pagada2 = await orden('2026-10-04 12:00:00', 'PAGADO', 30);
    await linea(
      pagada2,
      producto: gorra.$1,
      variante: gorra.$2,
      cantidad: 1,
      monto: 30,
    );

    final pendiente = await orden('2026-10-01 12:00:00', 'PENDIENTE', 999);
    await linea(
      pendiente,
      producto: gorra.$1,
      variante: gorra.$2,
      cantidad: 3,
      monto: 999,
    );
  }

  /// `GET` a [ruta]: `permisos == null` = petición **sin sesión**.
  Future<Response> get(String ruta, {Set<String>? permisos}) async {
    var peticion = Request('GET', Uri.parse('http://localhost$ruta'));
    if (permisos != null) {
      final usuario = usuarioDePrueba(permisos: permisos);
      final sesion = Sesion(
        token: 'token-de-prueba',
        usuarioId: usuario.id,
        expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
        usuario: usuario,
      );
      peticion = peticion.change(context: {'sesion': sesion});
    }
    return handler(peticion);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('reporte_rutas');
    db = SqliteDatabase('${dir.path}${Platform.pathSeparator}ventas.db');
    await Migrator(db, engine: 'sqlite').migrate();
    await sembrar();

    final router = Router();
    addReporteRoutes(router, reportes: Reportes(repository: ReporteRepositoryImpl(db)));
    handler = errorHandler()(router.call);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  group('sesión y permisos', () {
    test('sin sesión los dos informes responden 401', () async {
      for (final ruta in [
        '/api/v1/reportes/ventas',
        '/api/v1/reportes/ventas-productos',
      ]) {
        final respuesta = await get(ruta);
        expect(respuesta.statusCode, 401, reason: ruta);
      }
    });

    test('con sesión pero sin permiso responden 403 permiso_denegado', () async {
      for (final ruta in [
        '/api/v1/reportes/ventas',
        '/api/v1/reportes/ventas-productos',
      ]) {
        final respuesta = await get(ruta, permisos: {'ventas.ver'});
        expect(respuesta.statusCode, 403, reason: ruta);
        expect(await respuesta.readAsString(), contains('permiso_denegado'));
      }
    });

    test('ver Reportes no da acceso al ranking del dashboard', () async {
      final respuesta = await get(
        '/api/v1/reportes/productos-vendidos',
        permisos: const {'reportes.ver'},
      );

      expect(respuesta.statusCode, 403);
      expect(await respuesta.readAsString(), contains('dashboard.ver'));
    });
  });

  group('GET /api/v1/reportes/ventas', () {
    test('devuelve resumen y serie en la forma que espera la pantalla', () async {
      final respuesta = await get(
        '/api/v1/reportes/ventas?desde=2026-10-01&hasta=2026-10-07',
        permisos: const {'reportes.ver'},
      );

      expect(respuesta.statusCode, 200);
      final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;

      expect(cuerpo['desde'], '2026-10-01');
      expect(cuerpo['hasta'], '2026-10-07');
      expect(cuerpo['agrupacion'], 'dia');

      final resumen = cuerpo['resumen'] as Map;
      expect(resumen['total'], 130); // 100 + 30: la pendiente no suma
      expect(resumen['ordenes'], 2);
      expect(resumen['unidades'], 3);
      expect(resumen['ticketMedio'], 65);

      // Solo los periodos con datos: el frontend rellena los ceros.
      final serie = cuerpo['serie'] as List;
      expect(serie.map((f) => (f as Map)['etiqueta']), [
        '2026-10-01',
        '2026-10-04',
      ]);
    });

    test('el parámetro agrupación llega al caso de uso', () async {
      final respuesta = await get(
        '/api/v1/reportes/ventas?desde=2026-10-01&hasta=2026-10-07'
        '&agrupacion=mes',
        permisos: const {'reportes.ver'},
      );

      expect(respuesta.statusCode, 200);
      final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;
      expect(cuerpo['agrupacion'], 'mes');
      expect((cuerpo['serie'] as List).single['etiqueta'], '2026-10');
    });

    test('rango invertido o agrupación desconocida responden 400', () async {
      final invertido = await get(
        '/api/v1/reportes/ventas?desde=2026-10-07&hasta=2026-10-01',
        permisos: const {'reportes.ver'},
      );
      expect(invertido.statusCode, 400);
      expect(await invertido.readAsString(), contains('rango'));

      final mala = await get(
        '/api/v1/reportes/ventas?agrupacion=trimestre',
        permisos: const {'reportes.ver'},
      );
      expect(mala.statusCode, 400);
      expect(await mala.readAsString(), contains('agrupacion'));
    });
  });

  group('GET /api/v1/reportes/ventas-productos', () {
    test('devuelve productos (con su categoría) y el reparto', () async {
      final respuesta = await get(
        '/api/v1/reportes/ventas-productos'
        '?desde=2026-10-01&hasta=2026-10-07',
        permisos: const {'reportes.ver'},
      );

      expect(respuesta.statusCode, 200);
      final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;

      final productos = cuerpo['productos'] as List;
      expect(productos, hasLength(2));
      // Ordenados por monto descendente.
      expect(productos.first['nombre'], 'Jeans mezclillo');
      expect(productos.first['categoria'], 'Pantalones');
      expect(productos.first['monto'], 100);
      expect(productos.last['nombre'], 'Gorra deportiva');
      expect(productos.last['categoria'], '(sin categoría)');

      final categorias = cuerpo['categorias'] as List;
      expect((categorias.first as Map)['nombre'], 'Pantalones');
      expect(categorias.first['monto'], 100);
      // Sin categoría no se pierde dinero: agrupa en «(sin categoría)».
      expect(categorias.last['nombre'], '(sin categoría)');
      expect(categorias.last['monto'], 30);
    });

    test('las dos sumas cuadran con el resumen del otro informe', () async {
      final detalle = jsonDecode(
        await (
          await get(
            '/api/v1/reportes/ventas-productos'
            '?desde=2026-10-01&hasta=2026-10-07',
            permisos: const {'reportes.ver'},
          )
        ).readAsString(),
      ) as Map;
      final porPeriodo = jsonDecode(
        await (
          await get(
            '/api/v1/reportes/ventas?desde=2026-10-01&hasta=2026-10-07',
            permisos: const {'reportes.ver'},
          )
        ).readAsString(),
      ) as Map;

      double suma(List<dynamic> filas) => filas.fold<double>(
        0,
        (total, fila) => total + ((fila as Map)['monto'] as num).toDouble(),
      );

      expect(
        suma(detalle['productos'] as List),
        (porPeriodo['resumen'] as Map)['total'],
      );
      expect(
        suma(detalle['categorias'] as List),
        (porPeriodo['resumen'] as Map)['total'],
      );
    });
  });
}
