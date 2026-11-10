import 'dart:js_interop';
import 'dart:typed_data';

import 'package:printing/printing.dart';
import 'package:web/web.dart' as web;

/// Comparte el PDF con la **Web Share API** del navegador: en el celular
/// abre la hoja nativa (WhatsApp, Gmail, Drive, imprimir, descargar…) y en
/// equipos o navegadores sin ella se descarga el archivo, como hacía
/// `Printing.sharePdf`.
Future<bool> compartirPdf(Uint8List bytes, String nombre) async {
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final archivo = web.File(
      [blob].toJS,
      nombre,
      web.FilePropertyBag(type: 'application/pdf'),
    );
    final datos = web.ShareData(files: [archivo].toJS, title: nombre);

    if (web.window.navigator.canShare(datos)) {
      await web.window.navigator.share(datos).toDart;
      return true;
    }
  } catch (error) {
    // La persona cerró la hoja de compartir: no hay nada que guardar.
    if (error.toString().contains('AbortError')) return false;
    // Sin Web Share (navegador antiguo o sin contexto seguro/HTTPS): se
    // continúa con la descarga del navegador.
  }

  return Printing.sharePdf(bytes: bytes, filename: nombre);
}
