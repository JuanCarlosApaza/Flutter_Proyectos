import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Descarga [bytes] con el propio navegador (variante web).
///
/// Se monta un `Blob` y se dispara un enlace con `download`: es lo mismo que
/// hace el navegador al recibir `content-disposition: attachment`, pero sin
/// exponer el token de sesión en la URL.
///
/// [extensiones], [etiqueta] y [mimeType] solo los usa la variante de
/// escritorio/móvil: aquí el nombre del fichero basta.
Future<bool> guardarFichero(
  Uint8List bytes,
  String nombre, {
  List<String> extensiones = const ['dump'],
  String etiqueta = 'Respaldo de la base de datos',
  String mimeType = 'application/octet-stream',
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  try {
    final enlace = web.HTMLAnchorElement()
      ..href = url
      ..download = nombre;
    web.document.body?.appendChild(enlace);
    enlace.click();
    enlace.remove();
  } finally {
    web.URL.revokeObjectURL(url);
  }
  return true;
}
