import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Descarga [bytes] con el propio navegador (variante web).
///
/// Se monta un `Blob` y se dispara un enlace con `download`: es lo mismo que
/// hace el navegador al recibir `content-disposition: attachment`, pero sin
/// exponer el token de sesión en la URL.
///
/// [etiqueta] y [extensiones] solo existen para compartir firma con la
/// variante nativa; aquí manda el propio nombre del fichero.
Future<bool> guardarFichero(
  Uint8List bytes,
  String nombre, {
  String etiqueta = 'Respaldo de la base de datos',
  List<String> extensiones = const ['dump'],
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
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
