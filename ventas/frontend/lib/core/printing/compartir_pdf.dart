/// Compartir el PDF de un recibo con la hoja del propio equipo.
///
/// En web se usa la **Web Share API** del navegador (`navigator.share`), la
/// misma hoja que ofrece WhatsApp, Gmail, Drive o «descargar» en el celular;
/// en el resto de plataformas se delega en `Printing.sharePdf`, que abre la
/// hoja nativa de Android/iOS.
library;

export 'compartir_pdf_stub.dart'
    if (dart.library.js_interop) 'compartir_pdf_web.dart';
