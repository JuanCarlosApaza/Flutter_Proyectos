import 'package:farmacia_backend/src/core/errors/app_exception.dart';
import 'package:farmacia_backend/src/domain/usecases/rol_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late FakeRolRepository repo;
  late Roles roles;

  const permisosAdmin = {'productos.ver', 'productos.editar', 'ventas.ver'};

  setUp(() {
    repo = FakeRolRepository(
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
          nombre: 'ALMACENERO',
          esSistema: false,
          permisos: const {'productos.ver'},
        ),
      ],
      usuariosActivos: {1: 2, 2: 5, 3: 0},
    );
    roles = Roles(repository: repo);
  });

  group('Roles.crear', () {
    test('crea un rol con sus permisos', () async {
      final rol = await roles.crear(
        nombre: 'Vendedor',
        descripcion: 'Gestiona ventas',
        permisos: {'ventas.ver', 'ventas.crear'},
      );
      expect(rol.id, greaterThan(0));
      expect(rol.nombre, 'Vendedor');
      expect(rol.permisos, {'ventas.ver', 'ventas.crear'});
      expect(rol.esSistema, isFalse);
    });

    test('rechaza un nombre demasiado corto (400)', () {
      expect(
        () => roles.crear(nombre: 'AB'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'nombre_invalido',
          ),
        ),
      );
    });

    test('rechaza un permiso con formato inválido (400)', () {
      expect(
        () => roles.crear(nombre: 'OTRO', permisos: {'productos.borrar'}),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'permiso_invalido',
          ),
        ),
      );
    });
  });

  group('Roles.actualizar', () {
    test('actualiza nombre y permisos de un rol normal', () async {
      final rol = await roles.actualizar(
        3,
        nombre: 'Almacenero',
        permisos: {'productos.ver', 'productos.crear'},
      );
      expect(rol.nombre, 'Almacenero');
      expect(rol.permisos, {'productos.ver', 'productos.crear'});
    });

    test('el rol ADMIN no se puede modificar (409 rol_protegido)', () {
      expect(
        () => roles.actualizar(1, descripcion: 'nada'),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.code,
            'code',
            'rol_protegido',
          ),
        ),
      );
      expect(
        () => roles.actualizar(1, permisos: const <String>{}),
        throwsA(isA<ConflictException>()),
      );
    });

    test('sin campos que actualizar responde 400', () {
      expect(
        () => roles.actualizar(3),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'fields_required',
          ),
        ),
      );
    });

    test('un rol inexistente responde 404', () {
      expect(
        () => roles.actualizar(999, nombre: 'Nada'),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.code,
            'code',
            'rol_no_encontrado',
          ),
        ),
      );
    });
  });

  group('Roles.eliminar', () {
    test(
      'elimina un rol personalizado sin usuarios (borrado lógico)',
      () async {
        await roles.eliminar(3);
        expect(repo.roles.where((r) => r.id == 3), isEmpty);
      },
    );

    test('los roles de sistema no se eliminan (409 rol_sistema)', () {
      expect(
        () => roles.eliminar(2),
        throwsA(
          isA<ConflictException>().having((e) => e.code, 'code', 'rol_sistema'),
        ),
      );
    });

    test('un rol con usuarios activos no se elimina (409 rol_en_uso)', () {
      // CAJERO tiene 5 usuarios... pero además es de sistema: se comprueba
      // un rol personalizado en uso creando otro.
      repo.roles.add(
        rolDePrueba(
          id: 7,
          nombre: 'EN USO',
          esSistema: false,
          permisos: const {},
        ),
      );
      repo.usuariosActivos[7] = 1;
      expect(
        () => roles.eliminar(7),
        throwsA(
          isA<ConflictException>().having((e) => e.code, 'code', 'rol_en_uso'),
        ),
      );
    });

    test('un rol inexistente responde 404', () {
      expect(() => roles.eliminar(999), throwsA(isA<NotFoundException>()));
    });
  });
}
