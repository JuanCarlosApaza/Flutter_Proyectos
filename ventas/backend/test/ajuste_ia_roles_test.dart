import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/ajuste.dart';
import 'package:ventas_backend/src/domain/repositories/ajuste_repository.dart';
import 'package:ventas_backend/src/domain/usecases/ajuste_usecases.dart';
import 'package:test/test.dart';

/// Repositorio en memoria con unos ajustes prefijados.
final class _Repositorio implements AjusteRepository {
  _Repositorio([Map<String, String>? valores]) : _valores = {...?valores};

  final Map<String, String> _valores;

  @override
  Future<List<Ajuste>> findAjustes({int limit = 200, int offset = 0}) async {
    final ahora = DateTime.now();
    return [
      for (final entrada in _valores.entries)
        Ajuste(
          id: 0,
          clave: entrada.key,
          valor: entrada.value,
          fechaCreacion: ahora,
          fechaActualizacion: ahora,
        ),
    ];
  }

  @override
  Future<void> upsertAjustes(Map<String, String> valores) async {
    _valores.addAll(valores);
  }
}

void main() {
  group('Ajustes.puedeUsarIa (ajuste iaRoles)', () {
    test('sin ajuste guardado, cualquier rol puede usar la IA', () async {
      final ajustes = Ajustes(repository: _Repositorio());
      expect(await ajustes.puedeUsarIa('ADMIN'), isTrue);
      expect(await ajustes.puedeUsarIa('VENDEDOR'), isTrue);
      expect(await ajustes.puedeUsarIa(null), isTrue);
    });

    test('con la lista vacía, cualquier rol puede usar la IA', () async {
      final ajustes = Ajustes(
        repository: _Repositorio({Ajustes.claveIaRoles: ''}),
      );
      expect(await ajustes.puedeUsarIa('CAJERO'), isTrue);
    });

    test(
      'rol en la lista → sí; rol fuera → no (sin distinguir mayúsculas)',
      () async {
        final ajustes = Ajustes(
          repository: _Repositorio({Ajustes.claveIaRoles: 'ADMIN,cajero'}),
        );
        expect(await ajustes.puedeUsarIa('ADMIN'), isTrue);
        expect(await ajustes.puedeUsarIa('CAJERO'), isTrue);
        expect(await ajustes.puedeUsarIa('VENDEDOR'), isFalse);
        expect(await ajustes.puedeUsarIa(null), isFalse);
      },
    );
  });

  group('validación de iaRoles al guardar', () {
    test('admite la lista bien formada y el vacío', () async {
      final ajustes = Ajustes(repository: _Repositorio());
      await ajustes.guardar({Ajustes.claveIaRoles: 'ADMIN,CAJERO'});
      await ajustes.guardar({Ajustes.claveIaRoles: ''});
    });

    test('admite «ADMIN, CAJERO» (cada trozo se recorta)', () async {
      final ajustes = Ajustes(repository: _Repositorio());
      await ajustes.guardar({Ajustes.claveIaRoles: 'ADMIN, CAJERO'});
      expect(await ajustes.puedeUsarIa('CAJERO'), isTrue);
    });

    test('rechaza tokens con símbolos o trozos vacíos', () async {
      final ajustes = Ajustes(repository: _Repositorio());
      for (final malo in const ['ADMIN;;X', ',ADMIN', 'A,B,']) {
        expect(
          () => ajustes.guardar({Ajustes.claveIaRoles: malo}),
          throwsA(
            isA<BadRequestException>().having(
              (e) => e.code,
              'code',
              'valor_invalido',
            ),
          ),
          reason: malo,
        );
      }
    });
  });
}
