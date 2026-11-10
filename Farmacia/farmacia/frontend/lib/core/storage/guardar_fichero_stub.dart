import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Guarda [bytes] en el equipo de quien lo pide.
///
/// * **Móvil (Android/iOS)**: no existe el diálogo «Guardar como», así que
///   se escribe en la carpeta temporal y se abre la **hoja nativa de
///   compartir** (Archivos, Drive, WhatsApp, Gmail…): la persona elige
///   dónde dejarlo. La carpeta privada de la app no es accesible, así que
///   compartir es la única vía real en el celular.
/// * **Escritorio**: diálogo «Guardar como» del sistema (como siempre).
///
/// `false` = la hoja/dialogo se canceló. En web manda
/// [guardar_fichero_web.dart].
Future<bool> guardarFichero(Uint8List bytes, String nombre) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final temporal = await getTemporaryDirectory();
    final fichero = File(
      '${temporal.path}${Platform.pathSeparator}$nombre',
    );
    await fichero.writeAsBytes(bytes, flush: true);

    final resultado = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(fichero.path, mimeType: 'application/octet-stream')],
        fileNameOverrides: [nombre],
        title: 'Respaldo de la base de datos',
      ),
    );
    return resultado.status != ShareResultStatus.dismissed;
  }

  final ubicacion = await getSaveLocation(
    suggestedName: nombre,
    acceptedTypeGroups: [
      XTypeGroup(label: 'Respaldo de la base de datos', extensions: ['dump']),
    ],
  );
  // La persona cerró el diálogo: no hay nada que guardar.
  if (ubicacion == null) return false;

  await File(ubicacion.path).writeAsBytes(bytes, flush: true);
  return true;
}
