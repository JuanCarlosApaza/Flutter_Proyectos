import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ventas/domain/entities/reporte.dart';
import 'package:ventas/presentation/widgets/informes_export.dart';

/// Texto legible de un PDF: las cabeceras vienen en claro y los streams de
/// página van con `/FlateDecode`, así que se descomprimen antes de buscar.
String _textoDelPdf(List<int> bytes) {
  final bruto = String.fromCharCodes(bytes);
  final salida = StringBuffer(bruto);

  var posicion = 0;
  while (true) {
    final inicio = bruto.indexOf('stream', posicion);
    if (inicio < 0) break;
    var desde = inicio + 'stream'.length;
    if (bruto.startsWith('\r\n', desde)) {
      desde += 2;
    } else if (bruto.startsWith('\n', desde)) {
      desde += 1;
    }
    final fin = bruto.indexOf('endstream', desde);
    if (fin < 0) break;
    final trozo = bytes.sublist(desde, fin);
    // Cada stream se emite como `(...)TJ` por palabra: la búsqueda se hace
    // sobre palabras sueltas, no sobre frases.
    try {
      salida.write(String.fromCharCodes(ZLibDecoder().convert(trozo)));
    } catch (_) {
      try {
        salida.write(
          String.fromCharCodes(ZLibDecoder(raw: true).convert(trozo)),
        );
      } catch (_) {}
    }
    posicion = fin + 'endstream'.length;
  }
  return salida.toString();
}

/// Informe de ejemplo con acentos, categorías sin nombre y dos días de
/// rango (las mismas cifras que ve la pantalla).
final _informe = InformeVentas(
  resumen: const ResumenVentas(
    total: 1234.5,
    ordenes: 3,
    unidades: 5,
    utilidad: 250,
  ),
  serie: const [
    PeriodoVenta(
      etiqueta: '2026-10-01',
      ordenes: 1,
      total: 30,
      unidades: 3,
      utilidad: 12,
    ),
    PeriodoVenta(
      etiqueta: '2026-10-02',
      ordenes: 2,
      total: 1204.5,
      unidades: 2,
      utilidad: 238,
    ),
  ],
);

final _productos = InformeProductos(
  productos: const [
    ProductoRango(
      productoId: 1,
      nombre: 'Aspirina 500mg',
      unidades: 3,
      monto: 30,
      categoria: 'Analgésicos',
    ),
    ProductoRango(
      productoId: 2,
      nombre: 'Ibuprofeno, 400 mg',
      unidades: 2,
      monto: 18.5,
      categoria: null,
    ),
  ],
  categorias: const [
    VentaCategoria(nombre: 'Analgésicos', monto: 30, unidades: 3),
    VentaCategoria(nombre: null, monto: 18.5, unidades: 2),
  ],
);

void main() {
  test('nombreInforme usa el rango en el nombre del fichero', () {
    expect(
      nombreInforme(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
      'informe_ventas_2026-10-01_2026-10-31',
    );
  });

  test('csvInforme trae resumen, serie, productos y categorías', () {
    final csv = csvInforme(
      informe: _informe,
      productos: _productos,
      desde: DateTime(2026, 10, 1),
      hasta: DateTime(2026, 10, 2),
      agrupacion: 'dia',
    );

    expect(csv, contains('Informe de ventas'));
    expect(csv, contains('Desde,2026-10-01'));
    expect(csv, contains('Hasta,2026-10-02'));
    expect(csv, contains('Agrupación,Día'));
    // Resumen (mismos formatos que la pantalla).
    expect(csv, contains('Total (Bs),1234.50'));
    expect(csv, contains('Órdenes pagadas,3'));
    expect(csv, contains('Utilidad (Bs),250.00'));
    expect(csv, contains('Ticket medio (Bs),411.50'));
    expect(csv, contains('Unidades,5'));
    // Serie con su pie, que debe cuadrar con el resumen.
    expect(csv, contains('Periodo,Órdenes,Unidades,Total (Bs),Utilidad (Bs)'));
    expect(csv, contains('2026-10-01,1,3,30.00,12.00'));
    expect(csv, contains('Total del rango,3,5,1234.50,250.00'));
    // Productos (el nombre con coma va entrecomillado) y su categoría.
    expect(csv, contains('1,Aspirina 500mg,Analgésicos,3,30.00'));
    expect(csv, contains('"Ibuprofeno, 400 mg",(sin categoría),2,18.50'));
    expect(csv, contains('Total,,,5,48.50'));
    // Reparto por categorías con su porcentaje.
    expect(csv, contains('Categoría,Unidades,Total (Bs),%'));
    expect(csv, contains('Analgésicos,3,30.00,2.4%'));
    expect(csv, contains('(sin categoría),2,18.50,1.5%'));
  });

  test('pdfInforme genera un PDF con las mismas secciones', () async {
    final documento = pdfInforme(
      informe: _informe,
      productos: _productos,
      desde: DateTime(2026, 10, 1),
      hasta: DateTime(2026, 10, 2),
      agrupacion: 'mes',
    );

    final bytes = await documento.save();

    expect(bytes, isNotEmpty);
    // Cabecera de fichero PDF: «%PDF».
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

    final texto = _textoDelPdf(bytes);
    for (final fragmento in [
      'Informe',
      'Agrupación', // con acento: comprueba que no revienta la codificación
      'Mes',
      'Total',
      'rango',
      'vendidos',
      'categorías',
      '1234.50', // KPI total
      'Utilidad', // KPI + cabecera de la serie
      '250.00', // utilidad del rango
      '411.50', // ticket medio
      '2.4%', // reparto por categoría
      'Analgésicos',
      '2026-10-01',
    ]) {
      expect(texto, contains(fragmento), reason: 'falta «$fragmento»');
    }
  });
}
