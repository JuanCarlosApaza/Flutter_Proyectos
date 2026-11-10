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
/// [extensiones] filtra el tipo de fichero del diálogo (el respaldo pasa
/// `dump`, el informe de ventas `csv`) y [etiqueta] es el nombre de ese
/// filtro y el título de la hoja de compartir.
///
/// `false` = la hoja/dialogo se canceló. En web manda
/// [guardar_fichero_web.dart].
Future<bool> guardarFichero(
  Uint8List bytes,
  String nombre, {
  List<String> extensiones = const ['dump'],
  String etiqueta = 'Respaldo de la base de datos',
  String mimeType = 'application/octet-stream',
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final temporal = await getTemporaryDirectory();
    final fichero = File(
      '${temporal.path}${Platform.pathSeparator}$nombre',
    );
    await fichero.writeAsBytes(bytes, flush: true);

    final resultado = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(fichero.path, mimeType: mimeType)],
        fileNameOverrides: [nombre],
        title: etiqueta,
      ),
    );
    return resultado.status != ShareResultStatus.dismissed;
  }

  final ubicacion = await getSaveLocation(
    suggestedName: nombre,
    acceptedTypeGroups: [
      XTypeGroup(label: etiqueta, extensions: extensiones),
    ],
  );
  // La persona cerró el diálogo: no hay nada que guardar.
  if (ubicacion == null) return false;

  await File(ubicacion.path).writeAsBytes(bytes, flush: true);
  return true;
}
