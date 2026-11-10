import 'dart:io';
import 'dart:math';

import '../../core/errors/app_exception.dart';

/// Almacenamiento local de imágenes en disco.
///
/// La API **no** guarda binarios en la BD: solo la ruta
/// (`/api/v1/archivos/imagenes/<fichero>`) se escribe en la columna
/// correspondiente (p. ej. `productos.imagen`). Este tipo concentra las dos
/// operaciones físicas:
///
///  - [guardar]: valida que los bytes sean realmente una imagen y los escribe
///    en [rutaDirectorio] con un nombre propio (sin caracteres de usuario,
///    imposible inyectar rutas).
///  - [leer]: devuelve el fichero para servirlo por HTTP con su content-type.
final class AlmacenamientoImagenes {
  AlmacenamientoImagenes({
    required this.rutaDirectorio,
    this.maxBytes = 3 * 1024 * 1024,
  });

  /// Ruta del directorio de subidas (`UPLOADS_DIR`, relativa al CWD).
  final String rutaDirectorio;

  /// Tamaño máximo de una imagen (por defecto 3 MB).
  final int maxBytes;

  /// Prefijo público de las imágenes (la ruta que guarda la BD).
  static const String prefijo = '/api/v1/archivos/imagenes';

  /// Formatos admitidos: `extensión` -> `content-type`.
  static const Map<String, String> _mimePorExt = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
  };

  /// Nombre de fichero aceptado al servir (`<aleatorio>.<ext>`).
  ///
  /// Como el nombre sale de [guardar] y nunca del cliente, cualquier valor
  /// fuera de este patrón es un intento de *path traversal* → 404.
  static final RegExp _nombreValido = RegExp(
    r'^[a-z0-9]{10,32}\.[a-z0-9]{2,5}$',
  );

  /// Guarda los bytes como imagen y devuelve su ruta pública.
  ///
  /// Lanza `400` si el contenido está vacío, supera [maxBytes] o no es una
  /// imagen de los formatos admitidos (se comprueba por *magic bytes*, no por
  /// la extensión que declare el cliente).
  Future<({String nombre, String ruta})> guardar({
    required String nombreOriginal,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) {
      throw const BadRequestException(
        'La imagen está vacía.',
        code: 'imagen_vacia',
      );
    }
    if (bytes.length > maxBytes) {
      throw BadRequestException(
        'La imagen supera el límite de ${(maxBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
        code: 'imagen_grande',
      );
    }

    final formato = _detectar(bytes);
    if (formato == null) {
      throw BadRequestException(
        'Formato de imagen no admitido "$nombreOriginal": usa PNG, JPG, GIF o WEBP.',
        code: 'formato_invalido',
      );
    }

    final directorio = Directory(rutaDirectorio);
    if (!directorio.existsSync()) {
      directorio.createSync(recursive: true);
    }

    // Nombre propio: tiempo + aleatorio. No se usa nada del cliente, así que
    // no hay riesgo de escapar del directorio ni de pisar ficheros ajenos.
    final nombre = '${_aleatorio()}.${formato.$1}';
    await File('${directorio.path}${Platform.pathSeparator}$nombre')
        .writeAsBytes(bytes, flush: true);

    return (nombre: nombre, ruta: '$prefijo/$nombre');
  }

  /// Devuelve el fichero [nombre] para servirlo (`404` si no existe).
  Future<({String nombre, List<int> bytes, String contentType})> leer(
    String nombre,
  ) async {
    final normalizado = nombre.trim().toLowerCase();
    if (!_nombreValido.hasMatch(normalizado)) {
      throw const NotFoundException(
        'Imagen no encontrada.',
        code: 'imagen_no_encontrada',
      );
    }

    final fichero = File(
      '${Directory(rutaDirectorio).path}${Platform.pathSeparator}$normalizado',
    );
    if (!fichero.existsSync()) {
      throw const NotFoundException(
        'Imagen no encontrada.',
        code: 'imagen_no_encontrada',
      );
    }

    final bytes = await fichero.readAsBytes();
    final ext = normalizado.split('.').last;
    return (
      nombre: normalizado,
      bytes: bytes,
      contentType: _mimePorExt[ext] ?? 'application/octet-stream',
    );
  }

  /// Identifica el formato por los primeros bytes (*magic numbers*).
  ///
  /// Devuelve `(extensión, ...)` o `null` si no es una imagen admitida.
  static (String, String)? _detectar(List<int> bytes) {
    bool empiezaPor(List<int> firma, int offset) =>
        bytes.length >= offset + firma.length && _iguales(bytes, firma, offset);

    // PNG: \x89PNG\r\n\x1a\n
    if (empiezaPor(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], 0)) {
      return ('png', 'image/png');
    }
    // JPEG: FF D8 FF
    if (empiezaPor(const [0xFF, 0xD8, 0xFF], 0)) return ('jpg', 'image/jpeg');
    // GIF: "GIF87a" / "GIF89a"
    if (empiezaPor(const [0x47, 0x49, 0x46, 0x38], 0)) {
      return ('gif', 'image/gif');
    }
    // WEBP: "RIFF" .... "WEBP"
    if (empiezaPor(const [0x52, 0x49, 0x46, 0x46], 0) &&
        empiezaPor(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return ('webp', 'image/webp');
    }
    return null;
  }

  static bool _iguales(List<int> bytes, List<int> firma, int offset) {
    for (var i = 0; i < firma.length; i++) {
      if (bytes[offset + i] != firma[i]) return false;
    }
    return true;
  }

  /// Nombre aleatorio de 16 hex (`[0-9a-f]{16}`), válido para [_nombreValido].
  static String _aleatorio() {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
