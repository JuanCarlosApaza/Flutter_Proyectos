import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/fechas.dart';
import '../../core/formatos.dart';
import '../../domain/entities/reporte.dart';

/// Exportación del informe de ventas: **CSV** y **PDF**.
///
/// Las dos salidas llevan las mismas secciones y los mismos formatos que la
/// pantalla (resumen/KPI, serie, ranking de productos y reparto por
/// categorías), de modo que lo que se ve y lo que se descarga no pueden
/// discrepar.
///
/// El CSV va en UTF-8 con BOM (Excel lo necesita para los acentos) y usa
/// comas con comillas escapadas; el PDF es un documento A4 del paquete
/// `pdf`.

/// Nombre de fichero compartido por ambas salidas:
/// `informe_ventas_2026-10-01_2026-10-31.csv|pdf`.
String nombreInforme(DateTime desde, DateTime hasta) =>
    'informe_ventas_${fechaCorta(desde)}_${fechaCorta(hasta)}';

/// Texto de la agrupación para títulos (`dia` → `Día`).
String agrupacionTexto(String agrupacion) => switch (agrupacion) {
  'mes' => 'Mes',
  'anio' => 'Año',
  _ => 'Día',
};

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

/// Cuerpo del CSV del informe (sin codificar).
String csvInforme({
  required InformeVentas informe,
  required InformeProductos productos,
  required DateTime desde,
  required DateTime hasta,
  required String agrupacion,
}) {
  final b = StringBuffer();
  final resumen = informe.resumen;

  b.writeln('Informe de ventas');
  b.writeln('Desde,${fechaCorta(desde)}');
  b.writeln('Hasta,${fechaCorta(hasta)}');
  b.writeln('Agrupación,${agrupacionTexto(agrupacion)}');
  b.writeln();

  b.writeln('Resumen');
  b.writeln('Concepto,Valor');
  b.writeln('Total (Bs),${bsNumero(resumen.total)}');
  b.writeln('Órdenes pagadas,${resumen.ordenes}');
  b.writeln('Utilidad (Bs),${bsNumero(resumen.utilidad)}');
  b.writeln('Ticket medio (Bs),${bsNumero(resumen.ticketMedio)}');
  b.writeln('Unidades,${unidadesTexto(resumen.unidades)}');
  b.writeln();

  b.writeln('Serie');
  b.writeln('Periodo,Órdenes,Unidades,Total (Bs),Utilidad (Bs)');
  for (final periodo in informe.serie) {
    b.writeln(
      [
        periodo.etiqueta,
        periodo.ordenes,
        unidadesTexto(periodo.unidades),
        bsNumero(periodo.total),
        bsNumero(periodo.utilidad),
      ].join(','),
    );
  }
  b.writeln(
    'Total del rango,${resumen.ordenes},'
    '${unidadesTexto(resumen.unidades)},${bsNumero(resumen.total)},'
    '${bsNumero(resumen.utilidad)}',
  );
  b.writeln();

  b.writeln('Productos más vendidos');
  b.writeln('#,Producto,Categoría,Unidades,Total (Bs)');
  var totalesUnidades = 0.0;
  var totalesMonto = 0.0;
  for (var i = 0; i < productos.productos.length; i++) {
    final producto = productos.productos[i];
    totalesUnidades += producto.unidades;
    totalesMonto += producto.monto;
    b.writeln(
      [
        i + 1,
        _celda(producto.nombre),
        _celda(producto.categoria ?? '(sin categoría)'),
        unidadesTexto(producto.unidades),
        bsNumero(producto.monto),
      ].join(','),
    );
  }
  b.writeln(
    'Total,,,${unidadesTexto(totalesUnidades)},'
    '${bsNumero(totalesMonto)}',
  );
  b.writeln();

  b.writeln('Reparto por categorías');
  b.writeln('Categoría,Unidades,Total (Bs),%');
  for (final categoria in productos.categorias) {
    b.writeln(
      [
        _celda(categoria.nombre ?? '(sin categoría)'),
        unidadesTexto(categoria.unidades),
        bsNumero(categoria.monto),
        porcentajeTexto(porcentajeDe(categoria.monto, resumen.total)),
      ].join(','),
    );
  }
  b.writeln(
    'Total,${unidadesTexto(resumen.unidades)},'
    '${bsNumero(resumen.total)},'
    '${porcentajeTexto(porcentajeDe(resumen.total, resumen.total))}',
  );

  return b.toString();
}

/// Escapa una celda de CSV (comillas si contiene coma, comilla o salto de
/// línea).
String _celda(String texto) =>
    (texto.contains(',') || texto.contains('"') || texto.contains('\n'))
    ? '"${texto.replaceAll('"', '""')}"'
    : texto;

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

/// Documento PDF del informe.
pw.Document pdfInforme({
  required InformeVentas informe,
  required InformeProductos productos,
  required DateTime desde,
  required DateTime hasta,
  required String agrupacion,
}) {
  final doc = pw.Document();
  final resumen = informe.resumen;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        _cabecera(desde, hasta, agrupacion),
        pw.SizedBox(height: 16),
        _kpis(resumen),
        pw.SizedBox(height: 20),

        _titulo('Ventas del rango'),
        pw.SizedBox(height: 6),
        _tabla(
          cabecera: const [
            'Periodo',
            'Órdenes',
            'Unidades',
            'Total (Bs)',
            'Utilidad (Bs)',
          ],
          filas: [
            for (final periodo in informe.serie)
              [
                periodo.etiqueta,
                '${periodo.ordenes}',
                unidadesTexto(periodo.unidades),
                bsNumero(periodo.total),
                bsNumero(periodo.utilidad),
              ],
          ],
          pie: [
            'Total del rango',
            '${resumen.ordenes}',
            unidadesTexto(resumen.unidades),
            bsNumero(resumen.total),
            bsNumero(resumen.utilidad),
          ],
          alineaciones: const {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 20),

        _titulo('Productos más vendidos'),
        pw.SizedBox(height: 6),
        if (productos.productos.isEmpty)
          pw.Text('Sin ventas de productos en este rango')
        else
          _tabla(
            cabecera: const [
              '#',
              'Producto',
              'Categoría',
              'Unidades',
              'Total (Bs)',
            ],
            filas: [
              for (var i = 0; i < productos.productos.length; i++)
                [
                  '${i + 1}',
                  productos.productos[i].nombre,
                  productos.productos[i].categoria ?? '(sin categoría)',
                  unidadesTexto(productos.productos[i].unidades),
                  bsNumero(productos.productos[i].monto),
                ],
            ],
            alineaciones: const {
              0: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            pie: [
              'Total',
              '',
              '',
              unidadesTexto(
                productos.productos.fold<double>(
                  0,
                  (suma, producto) => suma + producto.unidades,
                ),
              ),
              bsNumero(
                productos.productos.fold<double>(
                  0,
                  (suma, producto) => suma + producto.monto,
                ),
              ),
            ],
            anchos: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(5),
              2: pw.FlexColumnWidth(4),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(3),
            },
          ),
        pw.SizedBox(height: 20),

        _titulo('Reparto por categorías'),
        pw.SizedBox(height: 6),
        if (productos.categorias.isEmpty)
          pw.Text('Sin ventas por categorías en este rango')
        else
          _tabla(
            cabecera: const ['Categoría', 'Unidades', 'Total (Bs)', '%'],
            filas: [
              for (final categoria in productos.categorias)
                [
                  categoria.nombre ?? '(sin categoría)',
                  unidadesTexto(categoria.unidades),
                  bsNumero(categoria.monto),
                  porcentajeTexto(porcentajeDe(categoria.monto, resumen.total)),
                ],
            ],
            alineaciones: const {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            pie: [
              'Total',
              unidadesTexto(resumen.unidades),
              bsNumero(resumen.total),
              porcentajeTexto(porcentajeDe(resumen.total, resumen.total)),
            ],
          ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Solo órdenes pagadas y no anuladas. La utilidad suma únicamente '
          'las líneas con costo conocido. La serie se agrupa en la hora '
          'local del negocio; el ticket medio y los porcentajes los calcula '
          'la aplicación.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc;
}

pw.Widget _cabecera(DateTime desde, DateTime hasta, String agrupacion) {
  const negro = PdfColor(0.12, 0.14, 0.16);
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColors.grey400),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Informe de ventas',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: negro,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Del ${fechaCorta(desde)} al ${fechaCorta(hasta)}  ·  '
                'Agrupación: ${agrupacionTexto(agrupacion)}',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _kpis(ResumenVentas resumen) {
  const valor = pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold);
  const etiqueta = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  final items = [
    ('Total vendido', bs(resumen.total)),
    ('Órdenes pagadas', '${resumen.ordenes}'),
    ('Utilidad', bs(resumen.utilidad)),
    ('Ticket medio', bs(resumen.ticketMedio)),
    ('Unidades', unidadesTexto(resumen.unidades)),
  ];
  return pw.Row(
    children: [
      for (final (rotulo, texto) in items)
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(texto, style: valor),
                pw.SizedBox(height: 2),
                pw.Text(rotulo, style: etiqueta),
              ],
            ),
          ),
        ),
    ],
  );
}

pw.Widget _titulo(String texto) => pw.Text(
  texto,
  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
);

/// Tabla A4 a mano (cabecera verde de marca, celdas con borde fino y fila de
/// totales resaltada): `TableHelper` no sabe dibujar un pie de totales.
pw.Widget _tabla({
  required List<String> cabecera,
  required List<List<String>> filas,
  List<String>? pie,
  Map<int, pw.Alignment> alineaciones = const {},
  Map<int, pw.TableColumnWidth>? anchos,
  pw.TableColumnWidth anchoPorDefecto = const pw.FlexColumnWidth(1),
}) {
  const estiloCelda = pw.TextStyle(fontSize: 9);

  pw.TableRow fila(
    List<String> celdas, {
    required bool esCabecera,
    required bool esPie,
  }) {
    return pw.TableRow(
      children: [
        for (var i = 0; i < celdas.length; i++)
          pw.Container(
            alignment: alineaciones[i] ?? pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: pw.BoxDecoration(
              color: esCabecera
                  ? const PdfColor(0.16, 0.42, 0.31)
                  : esPie
                  ? PdfColors.grey200
                  : PdfColors.white,
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Text(
              celdas[i],
              style: estiloCelda.copyWith(
                fontWeight: (esCabecera || esPie)
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: esCabecera ? PdfColors.white : PdfColors.black,
              ),
            ),
          ),
      ],
    );
  }

  return pw.Table(
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    columnWidths: anchos,
    defaultColumnWidth: anchoPorDefecto,
    tableWidth: pw.TableWidth.max,
    children: [
      fila(cabecera, esCabecera: true, esPie: false),
      for (var i = 0; i < filas.length; i++)
        fila(filas[i], esCabecera: false, esPie: false),
      if (pie != null) fila(pie, esCabecera: false, esPie: true),
    ],
  );
}
