import 'package:farmacia_backend/src/core/errors/app_exception.dart';
import 'package:farmacia_backend/src/domain/rules/contrasenas.dart';
import 'package:farmacia_backend/src/domain/usecases/usuario_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late FakeUsuarioRepository usuariosRepo;
  late FakeRolRepository rolesRepo;
  late Usuarios usuarios;

  const permisosAdmin = {
    'productos.ver',
    'productos.editar',
    'ventas.ver',
    'ventas.editar',
  };
  final admin = usuarioDePrueba(
    id: 1,
    rolId: 1,
    nivel: 'ADMIN',
    permisos: permisosAdmin,
  );
  final cajero = usuarioDePrueba(
    id: 2,
    rolId: 2,
    nivel: 'CAJERO',
    permisos: const {'ventas.ver'},
  );

  setUp(() {
    usuariosRepo = FakeUsuarioRepository(usuarios: [admin, cajero]);
    rolesRepo = FakeRolRepository(
      roles: [
        rolDePrueba(id: 1, nombre: 'ADMIN', permisos: permisosAdmin),
        rolDePrueba(
          id: 2,
          nombre: 'CAJERO',
          esSistema: true,
          permisos: const {'ventas.ver'},
        ),
        rolDePrueba(
          id: 3,
          nombre: 'INACTIVO',
          esSistema: false,
          estado: 'INACTIVO',
          permisos: const {},
        ),
        rolDePrueba(
          id: 4,
          nombre: 'GERENTE',
          esSistema: false,
          permisos: {'ventas.ver', 'ventas.editar'},
        ),
      ],
      usuariosActivos: {1: 1, 2: 3},
    );
    usuarios = Usuarios(repository: usuariosRepo, roles: rolesRepo);
  });

  group('Usuarios.crear', () {
    test(
      'crea el usuario con su rol cuando el actor lo puede asignar',
      () async {
        final creado = await usuarios.crear(
          nombreUsuario: 'nuevo.user',
          contrasena: 'secreto123',
          rolId: 2,
          actor: admin,
        );
        expect(creado.rolId, 2);
        expect(creado.nivelUsuario, 'CAJERO');
        expect(creado.id, greaterThan(0));
      },
    );

    test('sin rolId responde 400 rol_requerido', () {
      expect(
        () => usuarios.crear(
          nombreUsuario: 'nuevo.user',
          contrasena: 'secreto123',
          rolId: 0,
          actor: admin,
        ),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'rol_requerido',
          ),
        ),
      );
    });

    test('con un rol inexistente responde 404 rol_no_encontrado', () {
      expect(
        () => usuarios.crear(
          nombreUsuario: 'nuevo.user',
          contrasena: 'secreto123',
          rolId: 999,
          actor: admin,
        ),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.code,
            'code',
            'rol_no_encontrado',
          ),
        ),
      );
    });

    test('con un rol inactivo responde 409 rol_inactivo', () {
      expect(
        () => usuarios.crear(
          nombreUsuario: 'nuevo.user',
          contrasena: 'secreto123',
          rolId: 3,
          actor: admin,
        ),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.code,
            'code',
            'rol_inactivo',
          ),
        ),
      );
    });

    test('nadie puede crear usuarios con un rol por encima del suyo (403)', () {
      expect(
        () => usuarios.crear(
          nombreUsuario: 'nuevo.user',
          contrasena: 'secreto123',
          rolId: 1, // ADMIN: el cajero no tiene todos sus permisos
          actor: cajero,
        ),
        throwsA(
          isA<ForbiddenException>().having(
            (e) => e.code,
            'code',
            'rol_superior',
          ),
        ),
      );
    });

    test(
      'el arranque inicial (sin actor) puede crear el primer ADMIN',
      () async {
        final creado = await usuarios.crear(
          nombreUsuario: 'primer.admin',
          contrasena: 'secreto123',
          rolId: 1,
        );
        expect(creado.nivelUsuario, 'ADMIN');
      },
    );

    test('valida el nombre de usuario y la contraseña', () {
      expect(
        () => usuarios.crear(
          nombreUsuario: 'ab',
          contrasena: 'secreto123',
          rolId: 2,
          actor: admin,
        ),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'usuario_invalido',
          ),
        ),
      );
      expect(
        () => usuarios.crear(
          nombreUsuario: 'usuario.valido',
          contrasena: 'corta',
          rolId: 2,
          actor: admin,
        ),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'contrasena_invalida',
          ),
        ),
      );
    });
  });

  group('Usuarios.actualizar', () {
    test('permite reasignar rol cuando el actor puede otorgarlo', () async {
      final actualizado = await usuarios.actualizar(
        2,
        usuarioDePrueba(rolId: 4, nivel: 'GERENTE'),
        {'rolId'},
        actor: admin,
      );
      expect(actualizado.rolId, 4);
    });

    test('nadie asciende a un rol por encima del suyo (403 rol_superior)', () {
      expect(
        () => usuarios.actualizar(
          2,
          usuarioDePrueba(rolId: 1, nivel: 'ADMIN'),
          {'rolId'},
          actor: cajero,
        ),
        throwsA(
          isA<ForbiddenException>().having(
            (e) => e.code,
            'code',
            'rol_superior',
          ),
        ),
      );
    });

    test('no se puede reasignar el rol del único ADMIN activo (409)', () {
      expect(
        () => usuarios.actualizar(
          1,
          usuarioDePrueba(rolId: 4, nivel: 'GERENTE'),
          {'rolId'},
          actor: admin,
        ),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.code,
            'code',
            'ultimo_admin',
          ),
        ),
      );
    });

    test('sí se reasigna si queda otro ADMIN activo', () async {
      rolesRepo.usuariosActivos[1] = 2;
      final actualizado = await usuarios.actualizar(
        1,
        usuarioDePrueba(rolId: 4, nivel: 'GERENTE'),
        {'rolId'},
        actor: admin,
      );
      expect(actualizado.rolId, 4);
    });

    test('sin campos responde 400', () {
      expect(
        () => usuarios.actualizar(1, usuarioDePrueba(), const {}, actor: admin),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'fields_required',
          ),
        ),
      );
    });
  });

  group('Usuarios.eliminar', () {
    test('no se elimina el único ADMIN activo (409 ultimo_admin)', () {
      expect(
        () => usuarios.eliminar(1),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.code,
            'code',
            'ultimo_admin',
          ),
        ),
      );
    });

    test('elimina un usuario normal', () async {
      await usuarios.eliminar(2);
      expect(usuariosRepo.usuarios.where((u) => u.id == 2), isEmpty);
    });

    test('un usuario inexistente responde 404', () {
      expect(
        () => usuarios.eliminar(999),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.code,
            'code',
            'usuario_no_encontrado',
          ),
        ),
      );
    });
  });

  group('Usuarios: contraseñas', () {
    test('crear guarda el hash, nunca el texto plano', () async {
      final creado = await usuarios.crear(
        nombreUsuario: 'nuevo.user',
        contrasena: 'secreto123',
        rolId: 2,
        actor: admin,
      );
      final guardada = creado.contrasena!;
      expect(esHashBcrypt(guardada), isTrue);
      expect(guardada, isNot('secreto123'));
      expect(
        verificarContrasena(guardada: guardada, recibida: 'secreto123'),
        isTrue,
      );
    });

    test('cambiar sin claveAdmin → 400 clave_admin_requerida', () {
      expect(
        () => usuarios.actualizar(
          2,
          usuarioDePrueba(contrasena: 'nuevapass123'),
          {'contrasena'},
          actor: admin,
        ),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'clave_admin_requerida',
          ),
        ),
      );
      expect(usuariosRepo.usuarios[1].contrasena, 'secreto123');
    });

    test('claveAdmin incorrecta → 403 clave_admin_incorrecta', () {
      expect(
        () => usuarios.actualizar(
          2,
          usuarioDePrueba(contrasena: 'nuevapass123'),
          {'contrasena'},
          actor: admin,
          claveAdmin: 'clave-mala',
        ),
        throwsA(
          isA<ForbiddenException>().having(
            (e) => e.code,
            'code',
            'clave_admin_incorrecta',
          ),
        ),
      );
      // No se escribió nada.
      expect(usuariosRepo.usuarios[1].contrasena, 'secreto123');
    });

    test('claveAdmin correcta → guarda el hash de la clave nueva', () async {
      await usuarios.actualizar(
        2,
        usuarioDePrueba(contrasena: 'nuevapass123'),
        {'contrasena'},
        actor: admin,
        claveAdmin: 'secreto123',
      );
      final guardada = usuariosRepo.usuarios[1].contrasena!;
      expect(esHashBcrypt(guardada), isTrue);
      expect(
        verificarContrasena(guardada: guardada, recibida: 'nuevapass123'),
        isTrue,
      );
      expect(
        verificarContrasena(guardada: guardada, recibida: 'secreto123'),
        isFalse,
      );
    });

    test('contraseña de más de 72 bytes → 400', () {
      expect(
        () => usuarios.actualizar(
          2,
          usuarioDePrueba(contrasena: 'a' * 73),
          {'contrasena'},
          actor: admin,
          claveAdmin: 'secreto123',
        ),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'contrasena_demasiada_larga',
          ),
        ),
      );
    });
  });
}
