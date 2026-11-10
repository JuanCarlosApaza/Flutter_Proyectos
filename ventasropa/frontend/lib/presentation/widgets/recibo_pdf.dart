import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/printing/vista_pdf.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../domain/entities/recurso.dart';

/// Construye el PDF del recibo de una orden en papel de 80 mm: el alto se
/// ajusta al contenido ([PdfPageFormat.roll80] no tiene alto fijo), así que
/// sale en una sola tira por venta.
pw.Document reciboOrden(
  Recurso orden, {
  required List<Recurso> lineas,
  required String cliente,
  required String empleado,
  required String nombreTienda,
}) {
  final pagos = <pw.Widget>[];
  final crudos = orden['pagos'];
  if (crudos is List) {
    for (final pago in crudos) {
      if (pago is Map) pagos.add(_filaPago(pago));
    }
  }

  return _documento(
    titulo: 'Orden #${orden.id}',
    nombreTienda: nombreTienda,
    datos: [
      ('Cliente', cliente),
      ('Vendedor', empleado),
      ('Fecha', _fecha(orden.texto('fechaOrden', vacio: ''))),
      ('Estado', _legible(orden.texto('estado', vacio: ''))),
    ],
    productos: [for (final linea in lineas) _filaProducto(linea)],
    pagos: pagos,
    importes: const [],
    total: orden.numero('total') ?? 0,
  );
}

/// Muestra el recibo de una orden como vista previa del PDF con las
/// acciones del propio equipo (de `PdfPreview`): **imprimir** con la
/// impresora del sistema o la del navegador y **compartir** para guardar o
/// enviar el archivo desde el equipo (PC o celular).
Future<void> mostrarReciboOrden(
  BuildContext context,
  Recurso orden, {
  required List<Recurso> lineas,
  required String cliente,
  required String empleado,
}) {
  return mostrarVistaPdf(
    context,
    bytes: reciboOrden(
      orden,
      lineas: lineas,
      cliente: cliente,
      empleado: empleado,
      nombreTienda: AjustesScope.de(context).valor(Ajustes.nombreTienda),
    ).save(),
    titulo: 'Recibo · Orden #${orden.id}',
    archivo: 'recibo-orden-${orden.id}.pdf',
  );
}

/// Construye el PDF del recibo de una factura: sus importes, **cómo se
/// pagó** ([pagos], el desglose de la orden asociada) y sus datos (las
/// líneas de producto viven en la orden).
pw.Document reciboFactura(
  Recurso factura, {
  required String cliente,
  required String empleado,
  required String nombreTienda,
  Object? pagos,
}) {
  final filasPago = <pw.Widget>[];
  if (pagos is List) {
    for (final pago in pagos) {
      if (pago is Map) filasPago.add(_filaPago(pago));
    }
  }

  return _documento(
    titulo: 'Boleta #${factura.id}',
    nombreTienda: nombreTienda,
    datos: [
      // `N/D` y no «—»: la fuente estándar del PDF tira U+2014 (> U+00FF).
      ('Orden', factura['ordenId'] == null ? 'N/D' : '#${factura['ordenId']}'),
      ('Cliente', cliente),
      ('Vendedor', empleado),
      ('Fecha', _fecha(factura.texto('fechaFactura', vacio: ''))),
      ('Estado', _legible(factura.texto('estado', vacio: ''))),
    ],
    productos: const [],
    pagos: filasPago,
    importes: [
      ('Subtotal', factura.numero('subtotal') ?? 0),
      if ((factura.numero('rebaja') ?? 0) > 0)
        ('Rebaja', -(factura.numero('rebaja') ?? 0)),
      if ((factura.numero('iva') ?? 0) > 0)
        ('IVA 14.94%', factura.numero('iva') ?? 0),
    ],
    total: factura.numero('total') ?? 0,
  );
}

/// Vista previa de la factura (mismas acciones de imprimir y compartir).
Future<void> mostrarReciboFactura(
  BuildContext context,
  Recurso factura, {
  required String cliente,
  required String empleado,
  Object? pagos,
}) {
  return mostrarVistaPdf(
    context,
    bytes: reciboFactura(
      factura,
      cliente: cliente,
      empleado: empleado,
      nombreTienda: AjustesScope.de(context).valor(Ajustes.nombreTienda),
      pagos: pagos,
    ).save(),
    titulo: 'Recibo · Boleta #${factura.id}',
    archivo: 'recibo-factura-${factura.id}.pdf',
  );
}

/// Arma el documento de una sola página-tira con el contenido del recibo.
pw.Document _documento({
  required String titulo,
  required String nombreTienda,
  required List<(String, String)> datos,
  required List<pw.Widget> productos,
  required List<pw.Widget> pagos,
  required List<(String, double)> importes,
  required double total,
}) {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (_) => _recibo(
        titulo: titulo,
        nombreTienda: nombreTienda,
        datos: datos,
        productos: productos,
        pagos: pagos,
        importes: importes,
        total: total,
      ),
    ),
  );
  return doc;
}

// --- Contenido del recibo ---------------------------------------------------

pw.Widget _recibo({
  required String titulo,
  required String nombreTienda,
  required List<(String, String)> datos,
  required List<pw.Widget> productos,
  required List<pw.Widget> pagos,
  required List<(String, double)> importes,
  required double total,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Center(
        child: pw.Text(
          nombreTienda,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          'Recibo de venta',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      pw.Center(
        child: pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Divider(thickness: 0.6, color: PdfColors.grey500),
      pw.SizedBox(height: 4),
      for (final (etiqueta, valor) in datos) _filaDato(etiqueta, valor),
      if (productos.isNotEmpty)
        _seccion('Productos', productos)
      else if (importes.isNotEmpty)
        pw.SizedBox(height: 4),
      if (pagos.isNotEmpty) _seccion('Pagos', pagos),
      if (importes.isNotEmpty)
        _seccion('Importes', [
          for (final (etiqueta, monto) in importes) _filaMonto(etiqueta, monto),
        ]),
      _total(total),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'Gracias por su compra',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(
          'Impreso el ${_fecha(DateTime.now().toIso8601String())}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
    ],
  );
}

/// `Cliente: María Pérez`: etiqueta y valor en la misma línea.
pw.Widget _filaDato(String etiqueta, String valor) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Text('$etiqueta: $valor', style: const pw.TextStyle(fontSize: 9)),
  );
}

pw.Widget _seccion(String titulo, List<pw.Widget> filas) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.SizedBox(height: 6),
      pw.Text(
        titulo,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      ...filas,
    ],
  );
}

/// Una línea de producto: nombre + «cantidad × precio» a la izquierda y su
/// monto a la derecha (mismo dato que la ficha de detalle).
pw.Widget _filaProducto(Recurso linea) {
  final cantidad = cantidadTexto(linea.numero('cantidad') ?? 0);
  final precio = linea.numero('precioVenta') ?? 0;
  final monto = linea.numero('montoTotal') ?? 0;

  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                linea.texto('nombreProducto', vacio: 'Producto'),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (linea.texto('talla', vacio: '').isNotEmpty)
                pw.Text(
                  '${linea.texto('talla')} · ${linea.texto('color')}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              pw.Text(
                '$cantidad ${linea.texto('unidad', vacio: 'UN')} × '
                'Bs ${precio.toStringAsFixed(2)}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(
          'Bs ${monto.toStringAsFixed(2)}',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

/// Una línea de pago: método a la izquierda, importe a la derecha y la
/// referencia (nº de operación) debajo si viene.
pw.Widget _filaPago(Map p) {
  final monto = p['monto'] is num ? (p['monto'] as num).toDouble() : 0.0;
  final referencia = p['referencia'];
  final ref = referencia is String && referencia.trim().isNotEmpty
      ? referencia.trim()
      : '';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      // `QR` va tal cual (`_legible` lo dejaría como «Qr»).
      _filaMonto(
        p['metodoPago'] == 'QR' ? 'QR' : _legible('${p['metodoPago'] ?? ''}'),
        monto,
        negrita: true,
      ),
      if (ref.isNotEmpty)
        pw.Text(
          'Ref: $ref',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
    ],
  );
}

/// Fila «etiqueta a la izquierda · importe a la derecha».
pw.Widget _filaMonto(String etiqueta, double monto, {bool negrita = false}) {
  final estilo = pw.TextStyle(
    fontSize: 9,
    fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(etiqueta, style: estilo),
        pw.Text(
          monto < 0
              ? '− Bs ${monto.abs().toStringAsFixed(2)}'
              : 'Bs ${monto.toStringAsFixed(2)}',
          style: estilo,
        ),
      ],
    ),
  );
}

pw.Widget _total(double total) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 6),
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey500, width: 0.7),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'TOTAL',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Bs ${total.toStringAsFixed(2)}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}

// --- Texto compartido -------------------------------------------------------

/// `EFECTIVO` → `Efectivo` (en el recibo se lee mejor que en mayúsculas);
/// vacío → `N/D` (la fuente estándar no admite el «—» del resto de la app).
String _legible(String texto) {
  if (texto.isEmpty) return 'N/D';
  final minus = texto.toLowerCase();
  return minus[0].toUpperCase() + minus.substring(1);
}

/// ISO de la API → `2026-09-29 14:03` en hora local (`N/D` si no hay fecha).
String _fecha(String iso) {
  final momento = DateTime.tryParse(iso)?.toLocal();
  if (momento == null) return 'N/D';
  String dos(int valor) => valor.toString().padLeft(2, '0');
  return '${momento.year}-${dos(momento.month)}-${dos(momento.day)} '
      '${dos(momento.hour)}:${dos(momento.minute)}';
}
