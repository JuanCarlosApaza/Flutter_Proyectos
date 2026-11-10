import 'dart:convert';

import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/repositories/sesion_repository.dart';
import 'package:ventas_backend/src/domain/rules/contrasenas.dart';
import 'package:ventas_backend/src/domain/usecases/auth_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/http/rate_limit.dart';
import 'package:ventas_backend/src/presentation/routes/auth_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Sesiones en memoria (patrón del doble de `auth_usecases_test.dart`).
final class _SesionesFake implements SesionRepository {
  @override
  Future<Sesion> insert({
    required int usuarioId,
    required DateTime expiraEn,
  }) async => Sesion(
    token: 'token-de-prueba',
    usuarioId: usuarioId,
    expiraEn: expiraEn,
  );

  @override
  Future<Sesion?> findByToken(String token) async => null;

  @override
  Future<bool> delete(String token) async => true;

  @override
  Future<int> deleteExpired() async => 0;
}

void main() {
  late FakeUsuarioRepository usuarios;

  /// Monta las rutas de login reales con `errorHandler` (mismo envoltorio
  /// que producción) y el rate-limit indicado.
  Handler montar(RateLimiter limiter) {
    final autenticar = Autenticar(usuarios: usuarios, sesiones: _SesionesFake());
    final router = Router();
    addAuthRoutes(router, autenticar: autenticar, rateLimiter: limiter);
    return errorHandler()(router.call);
  }

  Future<Response> login(
    Handler handler,
    String nombre,
    String contrasena,
  ) async => await handler(
    Request(
      'POST',
      Uri.parse('http://localhost/api/v1/auth/login'),
      body: jsonEncode({'nombreUsuario': nombre, 'contrasena': contrasena}),
    ),
  );

  /// `error.code` de la respuesta de error estándar de la API.
  Future<String?> codigoDe(Response respuesta) async {
    final cuerpo = jsonDecode(await respuesta.readAsString());
    if (cuerpo is! Map) return null;
    final error = cuerpo['error'];
    return error is Map ? error['code']?.toString() : null;
  }

  setUp(() {
    usuarios = FakeUsuarioRepository();
    usuarios.usuarios.add(
      usuarioDePrueba(
        id: 7,
        nombreUsuario: 'ana',
        contrasena: hashContrasena('secreto123'),
      ),
    );
  });

  test('tras agotar los intentos fallidos → 429 demasiados_intentos', () async {
    final handler = montar(
      RateLimiter(maxIntentos: 3, ventana: const Duration(minutes: 5)),
    );

    for (var i = 0; i < 3; i++) {
      final fallo = await login(handler, 'ana', 'mala-$i');
      expect(fallo.statusCode, 401);
    }

    final bloqueado = await login(handler, 'ana', 'secreto123');
    expect(bloqueado.statusCode, 429);
    expect(await codigoDe(bloqueado), 'demasiados_intentos');
  });

  test('un login correcto reinicia el contador de la clave', () async {
    final handler = montar(
      RateLimiter(maxIntentos: 3, ventana: const Duration(minutes: 5)),
    );

    await login(handler, 'ana', 'mala-1');
    await login(handler, 'ana', 'mala-2');
    final ok = await login(handler, 'ana', 'secreto123');
    expect(ok.statusCode, 200);

    // El acierto borró los fallos: los dos siguientes vuelven a ser 401.
    await login(handler, 'ana', 'mala-3');
    final otroFallo = await login(handler, 'ana', 'mala-4');
    expect(otroFallo.statusCode, 401);
  });

  test('la ventana caducada vuelve a permitir el login', () async {
    final handler = montar(
      RateLimiter(maxIntentos: 1, ventana: const Duration(milliseconds: 100)),
    );

    await login(handler, 'ana', 'mala');
    final bloqueado = await login(handler, 'ana', 'mala');
    expect(bloqueado.statusCode, 429);

    await Future<void>.delayed(const Duration(milliseconds: 150));

    final otraVez = await login(handler, 'ana', 'secreto123');
    expect(otraVez.statusCode, 200);
  });

  test('la clave es IP + usuario: otro usuario no hereda el bloqueo', () async {
    usuarios.usuarios.add(
      usuarioDePrueba(
        id: 8,
        nombreUsuario: 'luis',
        contrasena: hashContrasena('secreto456'),
      ),
    );
    final handler = montar(
      RateLimiter(maxIntentos: 1, ventana: const Duration(minutes: 5)),
    );

    await login(handler, 'ana', 'mala');
    final anaBloqueada = await login(handler, 'ana', 'secreto123');
    expect(anaBloqueada.statusCode, 429);

    // Mismo cliente (sin IP en el test), distinto usuario: sigue probando.
    final luisSigue = await login(handler, 'luis', 'secreto456');
    expect(luisSigue.statusCode, 200);
  });

  test('las rutas que no son login no ven el límite', () async {
    final handler = montar(
      RateLimiter(maxIntentos: 1, ventana: const Duration(minutes: 5)),
    );
    for (var i = 0; i < 3; i++) {
      await login(handler, 'ana', 'mala');
    }

    final me = await handler(
      Request('GET', Uri.parse('http://localhost/api/v1/auth/me')),
    );
    expect(me.statusCode, 401);
    expect(await codigoDe(me), 'sesion_requerida');
  });
}
