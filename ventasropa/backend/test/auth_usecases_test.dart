import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/repositories/sesion_repository.dart';
import 'package:ventas_backend/src/domain/rules/contrasenas.dart';
import 'package:ventas_backend/src/domain/usecases/auth_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Doble en memoria de [SesionRepository].
final class FakeSesiones implements SesionRepository {
  int? ultimoUsuarioId;

  @override
  Future<Sesion> insert({
    required int usuarioId,
    required DateTime expiraEn,
  }) async {
    ultimoUsuarioId = usuarioId;
    return Sesion(
      token: 'token-de-prueba',
      usuarioId: usuarioId,
      expiraEn: expiraEn,
    );
  }

  @override
  Future<Sesion?> findByToken(String token) async => null;

  @override
  Future<bool> delete(String token) async => true;

  @override
  Future<int> deleteExpired() async => 0;
}

void main() {
  late FakeUsuarioRepository usuarios;
  late FakeSesiones sesiones;
  late Autenticar autenticar;

  setUp(() {
    usuarios = FakeUsuarioRepository();
    sesiones = FakeSesiones();
    autenticar = Autenticar(usuarios: usuarios, sesiones: sesiones);
  });

  group('Autenticar.iniciarSesion', () {
    test('login correcto contra el hash bcrypt', () async {
      final hashOriginal = hashContrasena('secreto123');
      usuarios.usuarios.add(
        usuarioDePrueba(id: 7, nombreUsuario: 'ana', contrasena: hashOriginal),
      );

      final sesion = await autenticar.iniciarSesion(
        nombreUsuario: 'ana',
        contrasena: 'secreto123',
      );

      expect(sesion.usuarioId, 7);
      expect(sesiones.ultimoUsuarioId, 7);
      expect(sesion.usuario?.id, 7);
      // Ya era hash: el login no lo reescribe.
      expect(usuarios.usuarios.single.contrasena, hashOriginal);
    });

    test('contraseña incorrecta → 401 credenciales_invalidas', () async {
      usuarios.usuarios.add(
        usuarioDePrueba(
          id: 7,
          nombreUsuario: 'ana',
          contrasena: hashContrasena('secreto123'),
        ),
      );

      expect(
        () => autenticar.iniciarSesion(
          nombreUsuario: 'ana',
          contrasena: 'contrasena-mala',
        ),
        throwsA(
          isA<UnauthorizedException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', 'credenciales_invalidas'),
        ),
      );
    });

    test('usuario inexistente → 401 (mismo mensaje)', () {
      expect(
        () => autenticar.iniciarSesion(
          nombreUsuario: 'noexiste',
          contrasena: 'secreto123',
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.code,
            'code',
            'credenciales_invalidas',
          ),
        ),
      );
    });

    test('cuenta inactiva → 403 cuenta_inactiva', () {
      usuarios.usuarios.add(
        usuarioDePrueba(
          id: 7,
          nombreUsuario: 'ana',
          contrasena: hashContrasena('secreto123'),
          estado: 'INACTIVO',
        ),
      );

      expect(
        () => autenticar.iniciarSesion(
          nombreUsuario: 'ana',
          contrasena: 'secreto123',
        ),
        throwsA(
          isA<ForbiddenException>().having(
            (e) => e.code,
            'code',
            'cuenta_inactiva',
          ),
        ),
      );
    });

    test(
      'cuenta legada en texto plano: entra y se re-hashea al vuelo',
      () async {
        usuarios.usuarios.add(
          usuarioDePrueba(
            id: 7,
            nombreUsuario: 'ana',
            contrasena: 'secreto123',
          ),
        );
        expect(esHashBcrypt(usuarios.usuarios.single.contrasena!), isFalse);

        final sesion = await autenticar.iniciarSesion(
          nombreUsuario: 'ana',
          contrasena: 'secreto123',
        );

        expect(sesion.usuarioId, 7);
        // La fila ya no guarda texto plano: ahora es hash verificable.
        final guardada = usuarios.usuarios.single.contrasena!;
        expect(esHashBcrypt(guardada), isTrue);
        expect(
          verificarContrasena(guardada: guardada, recibida: 'secreto123'),
          isTrue,
        );
      },
    );
  });
}
