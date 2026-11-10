import 'package:flutter_test/flutter_test.dart';

import 'package:ventas/core/exportar/informe_csv.dart';
import 'package:ventas/domain/entities/reporte.dart';

/// Informe de prueba: un rango de tres días con ventas solo en el primero
/// y un producto cuyo nombre lleva `;` (para comprobar el escapado).
const _ventas = InformeVentas(
  desde: '2026-10-01',
  hasta: '2026-10-03',
  agrupacion: 'dia',
  resumen: ResumenVentas(total: 1540.5, ordenes: 7, unidades: 12),
  serie: [
    VentaPeriodo(etiqueta: '2026-10-01', ordenes: 7, total: 1540.5, unidades: 12),
  ],
);

const _detalle = InformeProductos(
  productos: [
    VentaProducto(
      productoId: 1,
      nombre: 'Camisa; azul',
      unidades: 12,
      monto: 1540.5,
      categoria: 'Camisas',
    ),
  ],
  categorias: [VentaCategoria(nombre: 'Camisas', unidades: 12, monto: 1540.5)],
);

void main() {
  group('construirInformeCsv', () {
    late String csv;

    setUp(() {
      csv = construirInformeCsv(ventas: _ventas, detalle: _detalle);
    });

    test('empieza por BOM UTF-8 y usa fin de línea Windows', () {
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Informe de ventas\r\n'));
      expect(csv, contains('\n'));
      expect('\r\n'.allMatches(csv).length, greaterThan(5));
    });

    test('separa con «;» y escribe los números al estilo español', () {
      expect(csv, contains('Rango;2026-10-01 al 2026-10-03\r\n'));
      expect(csv, contains('Agrupación;por día\r\n'));
      expect(csv, contains('Total (Bs);1.540,50\r\n'));
      expect(csv, contains('Órdenes;7\r\n'));
      expect(csv, contains('Unidades;12,00\r\n'));
      // Ticket medio: 1540,5 / 7 = 220,07.
      expect(csv, contains('Ticket medio (Bs);220,07\r\n'));
      // Sin comas decimales: Excel con «;» las daría por miles.
      expect(csv, isNot(contains('1540.50')));
    });

    test('incluye los tres bloques del informe', () {
      expect(csv, contains('Resumen\r\n'));
      expect(csv, contains('Ventas por día\r\n'));
      expect(csv, contains('Ventas por producto\r\n'));
      expect(csv, contains('Reparto por categoría\r\n'));
    });

    test('rellena con ceros los días sin ventas del rango', () {
      expect(csv, contains('2026-10-01;7;12,00;1.540,50;100,00\r\n'));
      expect(csv, contains('2026-10-02;0;0,00;0,00;0,00\r\n'));
      expect(csv, contains('2026-10-03;0;0,00;0,00;0,00\r\n'));
    });

    test('escapa los campos con «;» entre comillas', () {
      expect(csv, contains('"Camisa; azul";Camisas;12,00;1.540,50;100,00\r\n'));
    });

    test('el reparto por categoría cuadra con el total', () {
      expect(csv, contains('Camisas;12,00;1.540,50;100,00\r\n'));
    });
  });

  group('InformeVentas.serieCompleta', () {
    test('por día rellena los huecos manteniendo lo que sí había', () {
      final completa = _ventas.serieCompleta;

      expect(completa.map((f) => f.etiqueta), [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
      ]);
      expect(completa.first.total, 1540.5);
      expect(completa.first.ordenes, 7);
      expect(completa[1].total, 0);
      expect(completa[2].ordenes, 0);
      expect(completa[2].unidades, 0);
    });

    test('por mes atraviesa el cambio de año', () {
      const mensual = InformeVentas(
        desde: '2026-11-05',
        hasta: '2027-02-15',
        agrupacion: 'mes',
        resumen: ResumenVentas(total: 0, ordenes: 0, unidades: 0),
        serie: [],
      );

      expect(mensual.serieCompleta.map((f) => f.etiqueta), [
        '2026-11',
        '2026-12',
        '2027-01',
        '2027-02',
      ]);
    });

    test('por año devuelve un año por etiqueta', () {
      const anual = InformeVentas(
        desde: '2025-01-01',
        hasta: '2026-12-31',
        agrupacion: 'anio',
        resumen: ResumenVentas(total: 0, ordenes: 0, unidades: 0),
        serie: [],
      );

      expect(anual.serieCompleta.map((f) => f.etiqueta), ['2025', '2026']);
    });

    test('un rango ilegible se queda en la serie del servidor', () {
      const roto = InformeVentas(
        desde: 'ayer',
        hasta: 'hoy',
        agrupacion: 'dia',
        resumen: ResumenVentas(total: 0, ordenes: 0, unidades: 0),
        serie: [VentaPeriodo(etiqueta: 'x', ordenes: 1, total: 1, unidades: 1)],
      );

      expect(roto.serieCompleta.map((f) => f.etiqueta), ['x']);
    });
  });

  group('ResumenVentas', () {
    test('el ticket medio es el total entre las órdenes', () {
      const conVentas = ResumenVentas(total: 220, ordenes: 4, unidades: 6);
      expect(conVentas.ticketMedio, 55);

      const sinVentas = ResumenVentas(total: 0, ordenes: 0, unidades: 0);
      expect(sinVentas.ticketMedio, 0);
    });
  });
}
