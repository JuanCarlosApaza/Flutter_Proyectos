import 'dart:io';

import 'package:test/test.dart';
import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/repositories/reporte_repository_impl.dart';
import 'package:ventas_backend/src/domain/usecases/reporte_usecases.dart';

/// Informes de ventas por rango de fechas (pantalla «Reportes») sobre una
/// base SQLite recién migrada.
///
/// Lo que se cubre aquí:
///
/// * agrupar por **día**, **mes** y **año** en **hora de Bolivia (UTC−4)**:
///   `03:30 UTC` de un día sigue siendo `23:30` del día anterior;
/// * incluir el día `hasta` entero y **solo** órdenes `PAGADO`;
/// * excluir las líneas `ELIMINADO` del recuento de unidades;
/// * ventas por producto (con su categoría) y por categoría;
/// * las validaciones del caso de uso (fechas, orden del rango, agrupación
///   y nº máximo de periodos).
void main() {
  late Directory dir;
  late SqliteDatabase db;
  late Reportes reportes;

  /// Ejecuta un `INSERT ... RETURNING columna` y devuelve ese valor.
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
    String estado = 'ACTIVO',
  }) async {
    await db.query(
      'INSERT INTO detalles_ordenes_pedidos '
      '(producto_id, orden_id, variante_id, nombre_producto, cantidad, '
      'precio_venta, monto_total, estado) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8)',
      [producto, orden, variante, 'producto', cantidad, monto, monto, estado],
    );
  }

  /// Datos de prueba.
  ///
  /// * `orden(fecha)`: la fecha está en **UTC** (así se guarda
  ///   `CURRENT_TIMESTAMP`), así que `03:30` ya es el día siguiente en
  ///   Bolivia;
  /// * solo `PAGADO` es venta: `PENDIENTE`, `CANCELADO` y `DEVUELTO` no;
  /// * cada producto tiene su variante, porque el detalle se agrega por
  ///   variante (PK `(variante_id, orden_id)`).
  Future<void> sembrar() async {
    final categoria = await insertar(
      'INSERT INTO categorias (nombre_categoria) VALUES (\$1) '
      'RETURNING categoria_id',
      ['Pantalones'],
    );
    final camisas = await insertar(
      'INSERT INTO categorias (nombre_categoria) VALUES (\$1) '
      'RETURNING categoria_id',
      ['Camisas'],
    );
    final talla = await insertar(
      'INSERT INTO tallas (nombre) VALUES (\$1) RETURNING talla_id',
      ['M'],
    );
    final color = await insertar(
      'INSERT INTO colores (nombre) VALUES (\$1) RETURNING color_id',
      ['Negro'],
    );

    /// `(producto, variante)` de un producto con una sola variante.
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
    final camisa = await producto('Camisa Oxford', camisas);
    final gorra = await producto('Gorra deportiva', null);

    Future<int> orden(String fecha, String estado, double total) => insertar(
      'INSERT INTO ordenes_pedidos (fecha_orden, estado, total) '
      'VALUES (\$1, \$2, \$3) RETURNING orden_id',
      [fecha, estado, total],
    );

    // 2026-10-01 20:30 UTC = 2026-10-01 16:30 en Bolivia.
    final pagada1 = await orden('2026-10-01 20:30:00', 'PAGADO', 100);
    await linea(
      pagada1,
      producto: jeans.$1,
      variante: jeans.$2,
      cantidad: 2,
      monto: 100,
    );
    // Una línea borrada no suma unidades ni dinero.
    await linea(
      pagada1,
      producto: gorra.$1,
      variante: gorra.$2,
      cantidad: 9,
      monto: 1,
      estado: 'ELIMINADO',
    );

    // 23:00 UTC sigue siendo el mismo día en Bolivia (19:00).
    final pagada2 = await orden('2026-10-01 23:00:00', 'PAGADO', 50);
    await linea(
      pagada2,
      producto: camisa.$1,
      variante: camisa.$2,
      cantidad: 1,
      monto: 50,
    );

    // Pendiente, cancelada y devuelta: no son ventas.
    final pendiente = await orden('2026-10-01 12:00:00', 'PENDIENTE', 999);
    await linea(
      pendiente,
      producto: gorra.$1,
      variante: gorra.$2,
      cantidad: 3,
      monto: 999,
    );
    await orden('2026-10-02 15:00:00', 'CANCELADO', 77);
    final devuelta = await orden('2026-10-03 04:00:00', 'DEVUELTO', 30);
    await linea(
      devuelta,
      producto: gorra.$1,
      variante: gorra.$2,
      cantidad: 1,
      monto: 30,
    );

    // Venta del producto sin categoría, en mitad del rango.
    final sinCategoria = await orden('2026-10-04 12:00:00', 'PAGADO', 30);
    await linea(
      sinCategoria,
      producto: gorra.$1,
      variante: gorra.$2,
      cantidad: 1,
      monto: 30,
    );

    // 03:30 UTC = 23:30 del día anterior: entra en el 7 (día `hasta`).
    final ultima = await orden('2026-10-08 03:30:00', 'PAGADO', 40);
    await linea(
      ultima,
      producto: jeans.$1,
      variante: jeans.$2,
      cantidad: 2,
      monto: 40,
    );

    // Medianoche exacta en Bolivia: ya pertenece al 8, fuera del rango.
    await orden('2026-10-08 04:00:00', 'PAGADO', 60);

    // Antes del `desde`: 03:30 UTC = 29/09 23:30 en Bolivia.
    final anterior = await orden('2026-09-30 03:30:00', 'PAGADO', 45);
    await linea(
      anterior,
      producto: camisa.$1,
      variante: camisa.$2,
      cantidad: 1,
      monto: 45,
    );

    // Un mes anterior, para las agrupaciones mes y año.
    final vieja = await orden('2025-11-15 12:00:00', 'PAGADO', 70);
    await linea(
      vieja,
      producto: jeans.$1,
      variante: jeans.$2,
      cantidad: 1,
      monto: 70,
    );
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('reporte_periodo');
    db = SqliteDatabase('${dir.path}${Platform.pathSeparator}ventas.db');
    await Migrator(db, engine: 'sqlite').migrate();
    reportes = Reportes(repository: ReporteRepositoryImpl(db));
    await sembrar();
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  group('ventas por día (hora de Bolivia)', () {
    test('agrupa por día, cuenta solo PAGADO y el resumen es la suma', () async {
      final informe = await reportes.ventas(
        desde: '2026-10-01',
        hasta: '2026-10-07',
        agrupacion: 'dia',
      );

      expect(informe.agrupacion, 'dia');
      expect(informe.desde, '2026-10-01');
      expect(informe.hasta, '2026-10-07');

      // Los días vacíos no viajan: el frontend los rellena con ceros.
      expect(informe.serie.map((f) => f.etiqueta), [
        '2026-10-01',
        '2026-10-04',
        '2026-10-07',
      ]);

      final primero = informe.serie.first;
      expect(primero.ordenes, 2);
      expect(primero.total, 100 + 50);
      // 2 unidades de la línea activa: la `ELIMINADO` no cuenta.
      expect(primero.unidades, 2 + 1);

      final medio = informe.serie[1];
      expect(medio.etiqueta, '2026-10-04');
      expect(medio.total, 30);
      expect(medio.unidades, 1);

      final ultima = informe.serie.last;
      // 03:30 UTC del 8 en Bolivia es el 7 a las 23:30.
      expect(ultima.etiqueta, '2026-10-07');
      expect(ultima.total, 40);
      expect(ultima.unidades, 2);

      // 100 + 50 + 30 + 40 = 220: ni el 999 pendiente, ni el 77
      // cancelado, ni el 30 devuelto, ni el 60 de la medianoche del 8,
      // ni el 45 anterior al `desde`.
      expect(informe.resumen.total, 220);
      expect(informe.resumen.ordenes, 4);
      expect(informe.resumen.unidades, 6);
      expect(informe.resumen.ticketMedio, 55);
    });

    test('incluye el día hasta entero y no el siguiente', () async {
      final informe = await reportes.ventas(
        desde: '2026-10-07',
        hasta: '2026-10-07',
      );
      expect(informe.serie.single.etiqueta, '2026-10-07');
      expect(informe.resumen.total, 40);

      final siguiente = await reportes.ventas(
        desde: '2026-10-08',
        hasta: '2026-10-08',
      );
      // Solo la orden de las 04:00 UTC (00:00 en Bolivia).
      expect(siguiente.resumen.total, 60);
      expect(siguiente.resumen.ordenes, 1);
    });

    test('por defecto toma el último mes hasta hoy', () async {
      final hoy = DateTime.now();
      String dia(DateTime f) =>
          '${f.year.toString().padLeft(4, '0')}-'
          '${f.month.toString().padLeft(2, '0')}-'
          '${f.day.toString().padLeft(2, '0')}';

      final informe = await reportes.ventas();

      expect(informe.hasta, dia(hoy));
      expect(informe.desde, dia(DateTime(hoy.year, hoy.month, hoy.day - 29)));
      expect(informe.agrupacion, 'dia');
    });
  });

  group('ventas por mes y año', () {
    test('agrupa por mes con etiquetas YYYY-MM', () async {
      final informe = await reportes.ventas(
        desde: '2025-11-01',
        hasta: '2026-10-31',
        agrupacion: 'mes',
      );

      expect(informe.serie.map((f) => f.etiqueta), [
        '2025-11',
        '2026-09',
        '2026-10',
      ]);
      expect(informe.serie.first.total, 70);
      expect(informe.serie.last.ordenes, 5);
      expect(informe.serie.last.total, 100 + 50 + 40 + 60 + 30);
      expect(informe.resumen.ordenes, 7);
    });

    test('agrupa por año con etiquetas YYYY', () async {
      final informe = await reportes.ventas(
        desde: '2025-01-01',
        hasta: '2026-12-31',
        agrupacion: 'anio',
      );

      expect(informe.serie.map((f) => f.etiqueta), ['2025', '2026']);
      expect(informe.serie.first.total, 70);
      expect(informe.serie.last.ordenes, 6);
      expect(informe.serie.last.total, 100 + 50 + 30 + 40 + 60 + 45);
    });
  });

  group('ventas por producto y categoría', () {
    test('suma unidades y monto por producto con su categoría', () async {
      final informe = await reportes.productosDelRango(
        desde: '2026-10-01',
        hasta: '2026-10-07',
      );

      expect(informe.productos.map((p) => p.nombre), [
        'Jeans mezclillo',
        'Camisa Oxford',
        'Gorra deportiva',
      ]);
      expect(informe.productos.first.categoria, 'Pantalones');
      expect(informe.productos.first.unidades, 4); // 2 + 2
      expect(informe.productos.first.monto, 140);
      expect(informe.productos[1].categoria, 'Camisas');
      // La gorra solo se vendió en la propia tienda sin categoría asignada.
      expect(informe.productos.last.unidades, 1);
      expect(informe.productos.last.monto, 30);
      expect(informe.productos.last.categoria, '(sin categoría)');
    });

    test('reparte por categorías, de mayor a menor', () async {
      final informe = await reportes.productosDelRango(
        desde: '2026-10-01',
        hasta: '2026-10-07',
      );

      expect(informe.categorias.map((c) => c.nombre), [
        'Pantalones',
        'Camisas',
        '(sin categoría)',
      ]);
      expect(informe.categorias.first.monto, 140);
      expect(informe.categorias.first.unidades, 4);
      // El reparto cuadra con el total del informe de periodos.
      expect(
        informe.categorias.fold<double>(0, (suma, c) => suma + c.monto),
        220,
      );
    });
  });

  group('validaciones', () {
    test('la agrupación desconocida es un 400', () {
      expect(
        () => reportes.ventas(agrupacion: 'trimestre'),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'agrupacion_invalida'),
        ),
      );
    });

    test('una fecha que no sea yyyy-MM-dd es un 400', () {
      expect(
        () => reportes.ventas(desde: '01/10/2026'),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'fecha_invalida'),
        ),
      );
      expect(
        () => reportes.productosDelRango(hasta: 'ayer'),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'fecha_invalida'),
        ),
      );
    });

    test('desde posterior a hasta es un 400', () {
      expect(
        () => reportes.ventas(desde: '2026-10-07', hasta: '2026-10-01'),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'rango_invalido'),
        ),
      );
    });

    test('un rango que pediría más de 400 periodos se rechaza', () {
      expect(
        () => reportes.ventas(
          desde: '2020-01-01',
          hasta: '2026-12-31',
          agrupacion: 'dia',
        ),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'rango_demasiado_grande'),
        ),
      );
      // El mismo rango por año sí cabe.
      expect(
        () => reportes.ventas(
          desde: '2020-01-01',
          hasta: '2026-12-31',
          agrupacion: 'anio',
        ),
        returnsNormally,
      );
    });

    test('el límite de productos del informe es de 500', () {
      expect(Reportes.limiteProductos, 500);
      expect(Reportes.limiteGrupos, 400);
    });
  });

  group('toJson', () {
    test('el informe lleva resumen y serie serializables', () async {
      final informe = await reportes.ventas(
        desde: '2026-10-01',
        hasta: '2026-10-07',
      );
      final json = informe.toJson();

      expect(json['desde'], '2026-10-01');
      expect(json['agrupacion'], 'dia');
      expect((json['resumen'] as Map<String, Object?>)['total'], 220);
      expect(
        (json['resumen'] as Map<String, Object?>)['ticketMedio'],
        closeTo(55, 0.0001),
      );
      expect(json['serie'], hasLength(3));
      expect(
        (json['serie'] as List<Object?>).first,
        isA<Map<String, Object?>>().having(
          (f) => f['etiqueta'],
          'etiqueta',
          '2026-10-01',
        ),
      );
    });
  });
}
