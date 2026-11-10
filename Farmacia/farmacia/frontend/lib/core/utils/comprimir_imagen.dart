import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Imagen reducida lista para subir: [bytes] finales, [nombre] (puede cambiar
/// la extensión al re-codificarse) y [bytesOriginales] para informar al
/// usuario del ahorro.
typedef ImagenComprimida = ({
  Uint8List bytes,
  String nombre,
  int bytesOriginales,
});

/// Lado máximo (px) que se conserva al recodificar: más resolución no se ve
/// en pantalla y solo encarece la subida.
const int resolucionMaximaImagen = 2048;

/// Reduce una imagen que supera [maxBytes] para que quepa en la subida.
///
/// * **Estáticas (JPG/PNG/WebP)**: se limitan a [resolucionMaximaImagen] px y
///   se recodifican como JPEG con calidad decreciente; si aún así no caben,
///   se escala un 70 % y se reintenta. Los PNG con transparencia se
///   recodifican primero como PNG (JPEG no admite alfa) y, si no caben, se
///   vuelcan sobre fondo blanco en JPEG.
/// * **Animaciones GIF**: se recodifican con menos colores **conservando los
///   frames** (no se convierten en foto fija).
///
/// Devuelve `null` cuando el formato no se puede decodificar o no es posible
/// bajar de [maxBytes]; en ese caso el llamador muestra el aviso de límite.
///
/// Si la imagen ya cabe, se devuelve tal cual (sin decodificar).
Future<ImagenComprimida?> comprimirImagen({
  required Uint8List bytes,
  required String nombre,
  int maxBytes = 3 * 1024 * 1024,
}) async {
  if (bytes.length <= maxBytes) {
    return (bytes: bytes, nombre: nombre, bytesOriginales: bytes.length);
  }

  // Cede un frame para que se pinte el estado "Comprimiendo…" antes del
  // trabajo pesado de decodificación.
  await Future<void>.delayed(Duration.zero);

  final imagen = img.decodeImage(bytes);
  if (imagen == null) return null;

  final resultado = imagen.hasAnimation
      ? _comprimirAnimacion(imagen, maxBytes)
      : _comprimirEstatica(imagen, maxBytes);

  if (resultado == null) return null;
  return (
    bytes: resultado.bytes,
    nombre: _renombrar(nombre, resultado.extension),
    bytesOriginales: bytes.length,
  );
}

/// Formatea bytes como megabytes con un decimal (`"4.7 MB"`).
String megas(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Recodifica una imagen fija como JPEG (o PNG si conserva transparencia).
({Uint8List bytes, String extension})? _comprimirEstatica(
  img.Image imagen,
  int maxBytes,
) {
  var actual = imagen;

  if (actual.width > resolucionMaximaImagen ||
      actual.height > resolucionMaximaImagen) {
    actual = actual.width >= actual.height
        ? img.copyResize(
            actual,
            width: resolucionMaximaImagen,
            maintainAspect: true,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            actual,
            height: resolucionMaximaImagen,
            maintainAspect: true,
            interpolation: img.Interpolation.average,
          );
  }

  // Con transparencia: primero PNG, que sí admite alfa.
  if (actual.hasAlpha) {
    final png = img.encodePng(actual);
    if (png.length <= maxBytes) return (bytes: png, extension: 'png');

    // JPEG no soporta alfa: se vuelca sobre fondo blanco para no dejar
    // negro donde había transparencia.
    final opaca = img.Image(
      width: actual.width,
      height: actual.height,
      numChannels: 3,
    );
    img.fill(opaca, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(opaca, actual);
    actual = opaca;
  }

  for (var ronda = 0; ronda < 6; ronda++) {
    for (final calidad in const [85, 70, 55, 40, 30, 20]) {
      final salida = img.encodeJpg(actual, quality: calidad);
      if (salida.length <= maxBytes) return (bytes: salida, extension: 'jpg');
    }
    // Ni siquiera al 20 % cabe: se reduce la resolución y se reintenta.
    if (actual.width <= 160 && actual.height <= 160) break;
    actual = img.copyResize(
      actual,
      width: (actual.width * 0.7).round(),
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
  }
  return null;
}

/// Recodifica una animación como GIF con menos colores, **sin** perder los
/// frames (redimensionar rompería la animación, así que solo se ajusta la
/// paleta de colores).
({Uint8List bytes, String extension})? _comprimirAnimacion(
  img.Image imagen,
  int maxBytes,
) {
  for (final factor in const [10, 8, 6, 4]) {
    final salida = img.encodeGif(imagen, samplingFactor: factor);
    if (salida.length <= maxBytes) return (bytes: salida, extension: 'gif');
  }
  return null;
}

/// Cambia la extensión de [nombre] (el backend además renombra el fichero
/// según los *magic bytes*, pero así el nombre queda coherente).
String _renombrar(String nombre, String extension) {
  final punto = nombre.lastIndexOf('.');
  final base = punto > 0 ? nombre.substring(0, punto) : nombre;
  return '$base.$extension';
}
