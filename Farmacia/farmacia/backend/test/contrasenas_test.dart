import 'package:farmacia_backend/src/domain/rules/contrasenas.dart';
import 'package:test/test.dart';

void main() {
  group('hashContrasena / verificarContrasena', () {
    test('hash redondo: guarda el hash y verifica la clave original', () {
      final hash = hashContrasena('secreto123');
      expect(esHashBcrypt(hash), isTrue);
      expect(hash, startsWith('\$2a\$10\$'));
      expect(hash.length, 60);
      expect(
        verificarContrasena(guardada: hash, recibida: 'secreto123'),
        isTrue,
      );
    });

    test('una clave distinta no verifica', () {
      final hash = hashContrasena('secreto123');
      expect(
        verificarContrasena(guardada: hash, recibida: 'otraclave'),
        isFalse,
      );
      expect(verificarContrasena(guardada: hash, recibida: ''), isFalse);
      expect(
        verificarContrasena(guardada: '', recibida: 'secreto123'),
        isFalse,
      );
    });

    test('cada hash usa una sal distinta', () {
      expect(hashContrasena('secreto123'), isNot(hashContrasena('secreto123')));
    });

    test('la contraseña no aparece en el hash', () {
      expect(hashContrasena('secreto123').contains('secreto123'), isFalse);
    });

    test('cuenta legada en texto plano: comparación directa', () {
      expect(
        verificarContrasena(guardada: 'secreto123', recibida: 'secreto123'),
        isTrue,
      );
      expect(
        verificarContrasena(guardada: 'secreto123', recibida: 'otraclave'),
        isFalse,
      );
      expect(esHashBcrypt('secreto123'), isFalse);
    });

    test('más de 72 bytes: no cabe en bcrypt', () {
      final larga = 'a' * 73;
      expect(cabeEnBcrypt('a' * 72), isTrue);
      expect(cabeEnBcrypt(larga), isFalse);
      // Ni siquiera intenta verificar contra un hash (evita el error de bcrypt).
      expect(
        verificarContrasena(
          guardada: hashContrasena('secreto123'),
          recibida: larga,
        ),
        isFalse,
      );
    });
  });
}
