import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/printing/vista_pdf.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../domain/entities/recurso.dart';
import 'imagen_recurso.dart';

/// Genera la hoja de cotización en A4 y la abre con los botones de
/// imprimir/compartir del propio equipo (mismo flujo que los recibos).
///
/// La hoja lleva lo que exige el usuario: **imagen** del producto,
/// **precio**, **cantidad** y **fecha**, más quién la creó y para quién.
/// Sin desglose de IGV (decisión de negocio): solo el total.
Future<void> mostrarHojaCotizacion(
  BuildContext context, {
  required Recurso cotizacion,
  required List<Recurso> lineas,
  required String cliente,
  required String creadoPor,
}) async {
  final doc = await construirHojaCotizacion(
    cotizacion: cotizacion,
    lineas: lineas,
    cliente: cliente,
    creadoPor: creadoPor,
    nombreTienda: AjustesScope.de(context).valor(Ajustes.nombreTienda),
  );
  // Las imágenes se descargaron: si la hoja ya se cerró, no hay nada que
  // abrir (context tras `await` necesita su comprobación de montaje).
  if (!context.mounted) return;
  await mostrarVistaPdf(
    context,
    bytes: doc.save(),
    titulo: 'Cotización #${cotizacion.id}',
    archivo: 'cotizacion-${cotizacion.id}.pdf',
  );
}

/// Construye el documento: descarga las imágenes de los productos (si una
/// falla, su fila sigue presente sin ella).
Future<pw.Document> construirHojaCotizacion({
  required Recurso cotizacion,
  required List<Recurso> lineas,
  required String cliente,
  required String creadoPor,
  required String nombreTienda,
}) async {
  final imagenes = <int, pw.MemoryImage?>{};
  for (final linea in lineas) {
    imagenes[linea.id] = await _imagenDe(linea.texto('imagen', vacio: ''));
  }

  final doc = pw.Document();
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
        ..._datos(cotizacion, cliente, creadoPor),
        pw.SizedBox(height: 12),
        _cabeceraTabla(),
        pw.Divider(thickness: 0.8, color: PdfColors.grey600),
        for (final linea in lineas) _filaProducto(linea, imagenes[linea.id]),
        pw.Divider(thickness: 0.8, color: PdfColors.grey600),
        pw.SizedBox(height: 4),
        _total(cotizacion.numero('total') ?? 0),
        pw.SizedBox(height: 20),
        pw.Center(
          child: pw.Text(
            'Gracias por su preferencia',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'Cotización emitida el ${_fecha(cotizacion.texto('fechaCotizacion', vacio: ''))}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ],
    ),
  );
  return doc;
}

/// Descarga la imagen del producto desde el backend; `null` si no hay o
/// falla (la fila de la cotización sigue siendo válida sin ella).
Future<pw.MemoryImage?> _imagenDe(String? ruta) async {
  final url = ImagenRecurso.absoluta(ruta);
  if (url == null) return null;
  try {
    final respuesta = await http.get(Uri.parse(url));
    if (respuesta.statusCode != 200 || respuesta.bodyBytes.isEmpty) {
      return null;
    }
    return pw.MemoryImage(respuesta.bodyBytes);
  } catch (_) {
    return null;
  }
}

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
          'Cotización',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
}

/// Datos generales: número, fecha, cliente y quién atendió.
List<pw.Widget> _datos(Recurso cotizacion, String cliente, String creadoPor) {
  return [
    _dato('Cotización', '#${cotizacion.id}'),
    _dato('Fecha', _fecha(cotizacion.texto('fechaCotizacion', vacio: ''))),
    _dato('Cliente', cliente),
    _dato('Atendido por', creadoPor),
    _dato('Estado', _legible(cotizacion.texto('estado', vacio: 'VIGENTE'))),
  ];
}

pw.Widget _dato(String etiqueta, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 32 * PdfPageFormat.mm,
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

/// Fila de encabezados de la tabla de productos (misma anchura que las
/// filas: hueco de la imagen + Cant. + P. unitario + Importe).
pw.Widget _cabeceraTabla() {
  final estilo = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      children: [
        pw.SizedBox(width: 19 * PdfPageFormat.mm),
        pw.Expanded(child: pw.Text('Producto', style: estilo)),
        pw.SizedBox(
          width: 14 * PdfPageFormat.mm,
          child: pw.Text(
            'Cant.',
            style: estilo,
            textAlign: pw.TextAlign.center,
          ),
        ),
        pw.SizedBox(width: 4 * PdfPageFormat.mm),
        pw.SizedBox(
          width: 24 * PdfPageFormat.mm,
          child: pw.Text(
            'P. unitario',
            style: estilo,
            textAlign: pw.TextAlign.right,
          ),
        ),
        pw.SizedBox(width: 3 * PdfPageFormat.mm),
        pw.SizedBox(
          width: 26 * PdfPageFormat.mm,
          child: pw.Text(
            'Importe',
            style: estilo,
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

/// Una línea: imagen, nombre, cantidad, precio unitario e importe.
pw.Widget _filaProducto(Recurso linea, pw.MemoryImage? imagen) {
  final cantidad = cantidadTexto(linea.numero('cantidad') ?? 0);
  final precio = linea.numero('precioVenta') ?? 0;
  final monto = linea.numero('montoTotal') ?? 0;

  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 16 * PdfPageFormat.mm,
          height: 16 * PdfPageFormat.mm,
          child: imagen == null
              ? null
              : pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Image(imagen, fit: pw.BoxFit.cover),
                ),
        ),
        pw.SizedBox(width: 3 * PdfPageFormat.mm),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                linea.texto('nombreProducto', vacio: 'Producto'),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '$cantidad ${linea.texto('unidad', vacio: 'UN')} × '
                'Bs ${precio.toStringAsFixed(2)}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 4 * PdfPageFormat.mm),
        pw.SizedBox(
          width: 14 * PdfPageFormat.mm,
          child: pw.Text(
            cantidad,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.SizedBox(width: 4 * PdfPageFormat.mm),
        pw.SizedBox(
          width: 24 * PdfPageFormat.mm,
          child: pw.Text(
            'Bs ${precio.toStringAsFixed(2)}',
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.SizedBox(width: 3 * PdfPageFormat.mm),
        pw.SizedBox(
          width: 26 * PdfPageFormat.mm,
          child: pw.Text(
            'Bs ${monto.toStringAsFixed(2)}',
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _total(double total) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'TOTAL',
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.Text(
        'Bs ${total.toStringAsFixed(2)}',
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

// --- Texto compartido --------------------------------------------------------

/// `VIGENTE` → `Vigente` (en la hoja se lee mejor que en mayúsculas).
String _legible(String texto) {
  if (texto.isEmpty) return 'N/D';
  final minus = texto.toLowerCase();
  return minus[0].toUpperCase() + minus.substring(1);
}

/// ISO de la API → `2026-09-29 14:03` en hora local (`N/D` si no hay fecha).
///
/// Evita «—» (U+2014): la fuente estándar del PDF tira los runes > U+00FF.
String _fecha(String iso) {
  final momento = DateTime.tryParse(iso)?.toLocal();
  if (momento == null) return 'N/D';
  String dos(int valor) => valor.toString().padLeft(2, '0');
  return '${momento.year}-${dos(momento.month)}-${dos(momento.day)} '
      '${dos(momento.hour)}:${dos(momento.minute)}';
}
