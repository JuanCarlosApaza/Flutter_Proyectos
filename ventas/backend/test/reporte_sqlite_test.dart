import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/repositories/reporte_repository_impl.dart';
import 'package:ventas_backend/src/domain/usecases/reporte_usecases.dart';
import 'package:test/test.dart';

// Los informes de «Reportes» **contra la BD real** (SQLite en memoria): aquí
// se comprueba el `GROUP BY`, no un doble en memoria.
//
// Cubre lo que un falso no puede ver: que el filtro y la etiqueta del
// periodo caen en el mismo día, que solo entran órdenes PAGADAS, que el
// resumen cuadra con la serie y que el ranking trae la categoría.
//
// Ojo: al abrir `SqliteDatabase` el proceso pasa a `Dialecto.sqlite = true`
// (es un marcador global), por eso este fichero es solo de SQLite.

/// Etiqueta `2026-10-01` de una fecha guardada en UTC, calculada como lo
/// hace el SQL: convirtiendo a la hora local de la máquina.
String dia(String utc) {
  final local = DateTime.parse('${utc.replaceFirst(' ', 'T')}Z').toLocal();
  String p(int v, [int ancho = 2]) => v.toString().padLeft(ancho, '0');
  return '${p(local.year, 4)}-${p(local.month)}-${p(local.day)}';
}

void main() {
  late SqliteDatabase db;
  late Reportes reportes;

  Future<void> sembrar() async {
    await db.query(
      "INSERT INTO categorias (nombre_categoria) VALUES ('Analgésicos')",
    );
    await db.query(
      'INSERT INTO productos (nombre_producto, precio_venta, categoria_id) '
      "VALUES ('Aspirina', 10.0, 1)",
    );
    await db.query(
      'INSERT INTO productos (nombre_producto, precio_venta) '
      "VALUES ('Pan', 15.0)",
    );
    // Las migraciones no crean variantes de filas hechas a mano: todo
    // producto necesita su variante «Único» (FK de las líneas de orden).
    await db.query(
      "INSERT INTO producto_variantes (producto_id, color_id, nombre_color, "
      'stock) VALUES (1, NULL, \'Único\', 100), (2, NULL, \'Único\', 100)',
    );

    Future<void> orden(
      int id,
      String estado,
      String fecha,
      double total,
      // (productoId, cantidad, monto, costo unitario — `null` = línea
      // antigua sin costo, que no aporta utilidad).
      List<(int, double, double, double?)> lineas,
    ) async {
      await db.query(
        'INSERT INTO ordenes_pedidos (orden_id, fecha_orden, total, estado) '
        'VALUES (\$1, \$2, \$3, \$4)',
        [id, fecha, total, estado],
      );
      for (final (productoId, cantidad, monto, costo) in lineas) {
        await db.query(
          'INSERT INTO detalles_ordenes_pedidos '
          '(producto_id, orden_id, nombre_producto, cantidad, precio_venta, '
          'monto_total, variante_id, costo_unitario) '
          'SELECT \$1, \$2, \$3, \$4, \$5, \$6, v.variante_id, \$7 '
          'FROM producto_variantes v '
          'WHERE v.producto_id = \$1 AND v.color_id IS NULL',
          [productoId, id, 'x', cantidad, monto, monto, costo],
        );
      }
    }

    // El día 2 queda sin ventas (hueco que el cliente rellenará con ceros).
    // Utilidad esperada: orden 1 → 20 − 6×2 = 8 (la línea de Pan, sin
    // costo, NO suma su monto 7.5); orden 2 → 10 − 4×1 = 6.
    await orden(1, 'PAGADO', '2026-10-01 12:00:00', 27.5, [
      (1, 2, 20, 6.0),
      (2, 0.5, 7.5, null),
    ]);
    await orden(2, 'PAGADO', '2026-10-03 12:00:00', 10, [(1, 1, 10, 4.0)]);
    // Anulada: no cuenta aunque tenga fecha dentro del rango.
    await orden(3, 'CANCELADO', '2026-10-01 13:00:00', 50, [
      (1, 5, 50, 1.0),
    ]);
    // Pendiente de pagar: el informe es de ventas PAGADAS.
    await orden(4, 'PENDIENTE', '2026-10-02 12:00:00', 99, [
      (1, 3, 99, 1.0),
    ]);
    // Fuera del rango de octubre (utilidad 40 − 5×4 = 20 en noviembre).
    await orden(5, 'PAGADO', '2026-11-05 12:00:00', 40, [
      (1, 4, 40, 5.0),
    ]);
  }

  setUp(() async {
    // BD en memoria: mismas migraciones que la APK, sin ficheros temporales.
    db = SqliteDatabase(':memory:');
    await Migrator(db, engine: 'sqlite').migrate();
    reportes = Reportes(repository: ReporteRepositoryImpl(db));
    await sembrar();
  });

  tearDown(() async {
    await db.close();
  });

  group('GET informe de ventas (serie)', () {
    test('agrupa por día y solo devuelve los días con ventas', () async {
      final informe = await reportes.ventasPorRango(
        desde: '2026-10-01',
        hasta: '2026-10-31',
      );

      expect(
        [for (final p in informe.serie) p.etiqueta],
        [dia('2026-10-01 12:00:00'), dia('2026-10-03 12:00:00')],
      );
      expect(informe.serie.first.ordenes, 1);
      expect(informe.serie.first.total, 27.5);
      expect(informe.serie.first.unidades, 2.5);
      // Utilidad: 20 − 6×2 = 8. La línea de Pan (7.5) no tiene costo, así
      // que queda fuera del cálculo en lugar de sumar su monto íntegro.
      expect(informe.serie.first.utilidad, 8);
      expect(informe.serie.last.utilidad, 6);
    });

    test('el resumen cuadra con la suma de la serie', () async {
      final informe = await reportes.ventasPorRango(
        desde: '2026-10-01',
        hasta: '2026-10-31',
      );

      final total = informe.serie.fold<double>(0, (s, p) => s + p.total);
      final unidades = informe.serie.fold<double>(0, (s, p) => s + p.unidades);
      final utilidad = informe.serie.fold<double>(0, (s, p) => s + p.utilidad);
      final ordenes = informe.serie.fold<int>(0, (s, p) => s + p.ordenes);

      expect(informe.resumen.total, total);
      expect(informe.resumen.total, 37.5);
      expect(informe.resumen.unidades, unidades);
      expect(informe.resumen.unidades, 3.5);
      expect(informe.resumen.utilidad, utilidad);
      expect(informe.resumen.utilidad, 14);
      expect(informe.resumen.ordenes, ordenes);
      expect(informe.resumen.ordenes, 2);
    });

    test('agrupación por mes y por año', () async {
      final porMes = await reportes.ventasPorRango(
        desde: '2026-10-01',
        hasta: '2026-10-31',
        agrupacion: 'mes',
      );
      expect(porMes.serie, hasLength(1));
      expect(porMes.serie.single.etiqueta, '2026-10');
      expect(porMes.serie.single.ordenes, 2);
      expect(porMes.serie.single.total, 37.5);
      expect(porMes.serie.single.utilidad, 14);

      final porAnio = await reportes.ventasPorRango(
        desde: '2026-01-01',
        hasta: '2026-12-31',
        agrupacion: 'anio',
      );
      expect(porAnio.serie.single.etiqueta, '2026');
      // 2 de octubre + la de noviembre; la cancelada y la pendiente no.
      expect(porAnio.serie.single.ordenes, 3);
      expect(porAnio.serie.single.total, 77.5);
      expect(porAnio.serie.single.unidades, 7.5);
      // 14 de octubre + 20 de noviembre.
      expect(porAnio.serie.single.utilidad, 34);
    });

    test('un rango sin ventas devuelve serie vacía y ceros', () async {
      final informe = await reportes.ventasPorRango(
        desde: '2025-01-01',
        hasta: '2025-12-31',
      );

      expect(informe.serie, isEmpty);
      expect(informe.resumen.total, 0);
      expect(informe.resumen.ordenes, 0);
      expect(informe.resumen.unidades, 0);
      expect(informe.resumen.utilidad, 0);
    });
  });

  group('GET productos del rango', () {
    test('trae el ranking con su categoría (null = sin categoría)', () async {
      final informe = await reportes.productosPorRango(
        desde: '2026-10-01',
        hasta: '2026-10-31',
      );

      expect(informe.productos, hasLength(2));
      expect(informe.productos.first.nombre, 'Aspirina');
      expect(informe.productos.first.categoria, 'Analgésicos');
      expect(informe.productos.first.unidades, 3);
      expect(informe.productos.first.monto, 30);
      expect(informe.productos.last.nombre, 'Pan');
      expect(informe.productos.last.categoria, isNull);
      expect(informe.productos.last.monto, 7.5);
    });

    test('reparto por categorías con monto y unidades', () async {
      final informe = await reportes.productosPorRango(
        desde: '2026-10-01',
        hasta: '2026-10-31',
      );

      expect(informe.categorias, hasLength(2));
      expect(informe.categorias.first.nombre, 'Analgésicos');
      expect(informe.categorias.first.monto, 30);
      expect(informe.categorias.first.unidades, 3);
      expect(informe.categorias.last.nombre, isNull);
      expect(informe.categorias.last.monto, 7.5);
      expect(informe.categorias.last.unidades, 0.5);
    });
  });

  group('validaciones del caso de uso', () {
    test('agrupación desconocida → 400 agrupacion_invalida', () {
      expect(
        () => reportes.ventasPorRango(
          desde: '2026-10-01',
          hasta: '2026-10-31',
          agrupacion: 'semana',
        ),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'agrupacion_invalida',
          ),
        ),
      );
    });

    test('fecha mal formada → 400 fecha_invalida', () {
      expect(
        () => reportes.ventasPorRango(desde: '01/10/2026', hasta: '2026-10-31'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'fecha_invalida',
          ),
        ),
      );
      expect(
        () => reportes.ventasPorRango(desde: '2026-10-01', hasta: ''),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'fecha_invalida',
          ),
        ),
      );
    });

    test('rango invertido → 400 rango_invalido', () {
      expect(
        () => reportes.ventasPorRango(desde: '2026-11-01', hasta: '2026-10-01'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'rango_invalido',
          ),
        ),
      );
    });
  });
}
