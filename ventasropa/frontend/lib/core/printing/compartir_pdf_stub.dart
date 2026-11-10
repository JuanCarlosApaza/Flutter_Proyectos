import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Comparte el PDF con la hoja nativa del dispositivo (Android/iOS) o lo
/// descarga donde esa hoja no existe. Es la variante de escritorio/móvil
/// nativo; en web manda [compartir_pdf_web.dart].
Future<bool> compartirPdf(Uint8List bytes, String nombre) {
  return Printing.sharePdf(bytes: bytes, filename: nombre);
}
