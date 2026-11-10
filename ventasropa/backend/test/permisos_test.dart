import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/presentation/http/permisos.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  Request conSesion({Set<String> permisos = const {}}) {
    final usuario = usuarioDePrueba(permisos: permisos);
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    return Request(
      'GET',
      Uri.parse('http://localhost/api/v1/products'),
    ).change(context: {'sesion': sesion});
  }

  group('asegurarPermiso', () {
    test('deja pasar cuando el rol tiene el permiso', () {
      final request = conSesion(permisos: {'productos.ver', 'productos.crear'});
      expect(
        () => asegurarPermiso(request, 'productos', 'ver'),
        returnsNormally,
      );
      expect(
        () => asegurarPermiso(request, 'productos', 'crear'),
        returnsNormally,
      );
    });

    test('responde 403 permiso_denegado cuando falta el permiso', () {
      final request = conSesion(permisos: {'ventas.ver'});
      expect(
        () => asegurarPermiso(request, 'productos', 'editar'),
        throwsA(
          isA<ForbiddenException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', 'permiso_denegado'),
        ),
      );
    });

    test('la acción "editar" no la da el permiso "ver"', () {
      final request = conSesion(permisos: {'productos.ver'});
      expect(
        () => asegurarPermiso(request, 'productos', 'editar'),
        throwsA(isA<ForbiddenException>()),
      );
    });

    test('sin sesión responde 401', () {
      final request = Request('GET', Uri.parse('http://localhost/api/v1/x'));
      expect(
        () => asegurarPermiso(request, 'productos', 'ver'),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
