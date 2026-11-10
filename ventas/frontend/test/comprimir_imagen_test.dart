import 'dart:math';
import 'dart:typed_data';

import 'package:ventas/core/utils/comprimir_imagen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// PNG con ruido (incompresible) que pesa bastante para su tamaño.
Uint8List _pngRuidosa({int ancho = 800, int alto = 600, int semilla = 7}) {
  final random = Random(semilla);
  final imagen = img.Image(width: ancho, height: alto, numChannels: 3);
  for (final p in imagen) {
    p
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return img.encodePng(imagen);
}

void main() {
  test('si la imagen ya cabe en el límite se devuelve tal cual', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final resultado = await comprimirImagen(
      bytes: bytes,
      nombre: 'foto.png',
      maxBytes: 1024,
    );

    expect(resultado, isNotNull);
    expect(resultado!.bytes, same(bytes));
    expect(resultado.nombre, 'foto.png');
  });

  test('una imagen que supera el límite se reduce por debajo de él', () async {
    final bytes = _pngRuidosa();
    // Límite exigente pero alcanzable: una cuarta parte del PNG original.
    final limite = bytes.length ~/ 4;

    final resultado = await comprimirImagen(
      bytes: bytes,
      nombre: 'foto del producto.png',
      maxBytes: limite,
    );

    expect(resultado, isNotNull, reason: 'debe poder comprimirse');
    expect(resultado!.bytes.length, lessThan(limite));
    expect(resultado.bytesOriginales, bytes.length);
    // Se recodifica a JPEG, así que la extensión cambia.
    expect(resultado.nombre, 'foto del producto.jpg');
    // Y sigue siendo una imagen JPEG válida (magic bytes FF D8 FF).
    expect(resultado.bytes.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
  });

  test('un fichero que no es imagen devuelve null', () async {
    final basura = Uint8List.fromList(List.filled(4096, 65));

    final resultado = await comprimirImagen(
      bytes: basura,
      nombre: 'no-es-imagen.png',
      maxBytes: 1024,
    );

    expect(resultado, isNull);
  });

  test('el nombre sin extensión recibe la nueva', () async {
    final bytes = _pngRuidosa(ancho: 400, alto: 400);

    final resultado = await comprimirImagen(
      bytes: bytes,
      nombre: 'logotipo',
      maxBytes: bytes.length ~/ 4,
    );

    expect(resultado, isNotNull);
    expect(resultado!.nombre, 'logotipo.jpg');
  });
}
