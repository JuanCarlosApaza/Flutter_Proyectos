import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/printing/vista_pdf.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../domain/entities/reporte.dart';

/// Genera el informe de ventas en PDF y lo abre con los botones de
/// imprimir/compartir del propio equipo (mismo flujo que los recibos y las
/// cotizaciones).
///
/// La hoja lleva: rango y agrupación, resumen (total, órdenes, unidades y
/// ticket medio), la serie por periodo, el ranking de productos y el reparto
/// por categoría —los mismos datos que la pantalla y el CSV— más una nota
/// con los criterios (solo órdenes pagadas, total bruto, hora de Bolivia).
Future<void> mostrarInformePdf(
  BuildContext context, {
  required InformeVentas ventas,
  required InformeProductos detalle,
}) async {
  final doc = construirInformePdf(
    ventas: ventas,
    detalle: detalle,
    nombreTienda: AjustesScope.de(context).valor(Ajustes.nombreTienda),
  );
  if (!context.mounted) return;
  await mostrarVistaPdf(
    context,
    bytes: doc.save(),
    titulo: 'Informe de ventas',
    archivo: 'informe_ventas_${ventas.desde}_${ventas.hasta}.pdf',
  );
}

/// Construye el documento (función pura: sin red ni `BuildContext`).
///
/// [detalle] puede venir vacío (rango sin ventas): las secciones de
/// productos y categorías simplemente no salen.
pw.Document construirInformePdf({
  required InformeVentas ventas,
  required InformeProductos detalle,
  required String nombreTienda,
}) {
  final doc = pw.Document();
  final resumen = ventas.resumen;
  final serie = ventas.serieCompleta;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => _cabecera(nombreTienda),
      footer: (context) => pw.Center(
        child: pw.Text(
          'Página ${context.pageNumber}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 6),
        pw.Text(
          'Informe de ventas',
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        _dato('Rango', '${ventas.desde} al ${ventas.hasta}'),
        _dato('Agrupación', 'por ${_agrupacion(ventas.agrupacion)}'),
        _dato('Generado', _ahora()),
        pw.SizedBox(height: 12),

        // --- Resumen -------------------------------------------------------
        _titulo('Resumen'),
        _dato('Total', 'Bs ${resumen.total.toStringAsFixed(2)}'),
        _dato('Órdenes', '${resumen.ordenes}'),
        _dato('Unidades', resumen.unidades.toStringAsFixed(2)),
        _dato(
          'Ticket medio',
          'Bs ${resumen.ticketMedio.toStringAsFixed(2)}',
        ),
        pw.SizedBox(height: 12),

        // --- Serie por periodo --------------------------------------------
        _titulo('Ventas por ${_agrupacion(ventas.agrupacion)}'),
        pw.SizedBox(height: 4),
        _tabla(
          cabeceras: const ['Periodo', 'Órdenes', 'Unidades', 'Total'],
          flexos: const [3, 2, 2, 3],
          derecha: const [false, true, true, true],
          filas: [
            for (final periodo in serie)
              [
                periodo.etiqueta,
                '${periodo.ordenes}',
                periodo.unidades.toStringAsFixed(2),
                'Bs ${periodo.total.toStringAsFixed(2)}',
              ],
          ],
        ),
        if (serie.length > 60)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              'Se listan todos los periodos del rango (los que no tienen '
              'ventas aparecen con cero).',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ),
        pw.SizedBox(height: 12),

        // --- Productos -----------------------------------------------------
        if (detalle.productos.isNotEmpty) ...[
          _titulo('Productos más vendidos'),
          pw.SizedBox(height: 4),
          _tabla(
            cabeceras: const ['Producto', 'Categoría', 'Unidades', 'Total'],
            flexos: const [5, 3, 2, 3],
            derecha: const [false, false, true, true],
            filas: [
              for (final producto in _acotar(detalle.productos))
                [
                  producto.nombre,
                  producto.categoria ?? '(sin categoría)',
                  producto.unidades.toStringAsFixed(2),
                  'Bs ${producto.monto.toStringAsFixed(2)}',
                ],
            ],
          ),
          if (detalle.productos.length > _topeProductos)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Y ${detalle.productos.length - _topeProductos} productos '
                'más (el CSV los incluye todos).',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          pw.SizedBox(height: 12),
        ],

        // --- Categorías ----------------------------------------------------
        if (detalle.categorias.isNotEmpty) ...[
          _titulo('Reparto por categoría'),
          pw.SizedBox(height: 4),
          _tabla(
            cabeceras: const ['Categoría', 'Unidades', 'Total', '% total'],
            flexos: const [4, 2, 3, 2],
            derecha: const [false, true, true, true],
            filas: [
              for (final categoria in detalle.categorias)
                [
                  categoria.nombre,
                  categoria.unidades.toStringAsFixed(2),
                  'Bs ${categoria.monto.toStringAsFixed(2)}',
                  '${_porcentaje(categoria.monto, resumen.total)} %',
                ],
            ],
          ),
        ],

        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.6, color: PdfColors.grey400),
        pw.SizedBox(height: 4),
        pw.Text(
          'Criterios: solo órdenes PAGADO; líneas no eliminadas; total bruto '
          '(antes de rebajas e IVA); fechas en hora de Bolivia (UTC-4).',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return doc;
}

/// El PDF se queda con los primeros [_topeProductos]: una hoja con 500
/// productos no la lee nadie (el CSV sí los trae todos).
const int _topeProductos = 50;

List<VentaProducto> _acotar(List<VentaProducto> productos) =>
    productos.length <= _topeProductos
    ? productos
    : productos.sublist(0, _topeProductos);

// --- Piezas de la hoja -------------------------------------------------------

/// Marca en la cabecera de cada página (nombre de la tienda, configurable
/// en Ajustes).
pw.Widget _cabecera(String nombreTienda) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          nombreTienda,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Informe de ventas',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
}

pw.Widget _titulo(String texto) => pw.Text(
  texto,
  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
);

pw.Widget _dato(String etiqueta, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 30 * PdfPageFormat.mm,
          child: pw.Text(
            etiqueta,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            valor,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

/// Tabla sencilla (cabecera en negrita + filas de 8pt) con columnas
/// repartidas por [flexos] y alineadas según [derecha].
pw.Widget _tabla({
  required List<String> cabeceras,
  required List<List<String>> filas,
  required List<int> flexos,
  required List<bool> derecha,
}) {
  final estilo = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

  pw.Widget fila(List<String> celdas, pw.TextStyle texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          for (var i = 0; i < celdas.length; i++)
            pw.Expanded(
              flex: flexos[i],
              child: pw.Text(
                celdas[i],
                textAlign: derecha[i] ? pw.TextAlign.right : pw.TextAlign.left,
                style: texto,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      fila(cabeceras, estilo),
      pw.Divider(thickness: 0.8, color: PdfColors.grey600),
      for (final celdas in filas)
        fila(celdas, const pw.TextStyle(fontSize: 8)),
    ],
  );
}

// --- Texto compartido --------------------------------------------------------

/// `dia` → `día`, `mes` → `mes`, `anio` → `año`.
String _agrupacion(String agrupacion) => switch (agrupacion) {
  'mes' => 'mes',
  'anio' => 'año',
  _ => 'día',
};

/// Porcentaje de [valor] sobre el total del rango, sin decimales inútiles.
String _porcentaje(double valor, double total) =>
    total == 0 ? '0' : (valor * 100 / total).toStringAsFixed(1);

/// Fecha y hora locales de generación del informe.
String _ahora() {
  final momento = DateTime.now();
  String dos(int valor) => valor.toString().padLeft(2, '0');
  return '${momento.year}-${dos(momento.month)}-${dos(momento.day)} '
      '${dos(momento.hour)}:${dos(momento.minute)}';
}
