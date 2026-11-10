import 'dart:convert';

import 'package:farmacia_backend/src/presentation/http/json_response.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  /// Cuerpo JSON de la respuesta como mapa decodificado.
  Future<Map<String, Object?>> cuerpo(Response respuesta) async =>
      jsonDecode(await respuesta.readAsString()) as Map<String, Object?>;

  group('listJsonResponse', () {
    test('sin total conserva el comportamiento antiguo', () async {
      final items = [
        {'id': 1},
        {'id': 2},
      ];

      final body = await cuerpo(listJsonResponse(items));

      expect(body['total'], 2);
      expect(body['items'], hasLength(2));
      // Sin `total` explícito no aparecen limit/offset (reportes, respaldos
      // y detalles siguen con la respuesta de siempre).
      expect(body.containsKey('limit'), isFalse);
      expect(body.containsKey('offset'), isFalse);
    });

    test('con total devuelve el COUNT real y eco de paginación', () async {
      final items = [
        {'id': 1},
      ];

      final body = await cuerpo(
        listJsonResponse(items, total: 37, limit: 10, offset: 20),
      );

      expect(body['total'], 37);
      expect(body['limit'], 10);
      expect(body['offset'], 20);
      // `total` es el total filtrado aunque la página traiga una sola fila.
      expect(body['items'], hasLength(1));
    });
  });
}
