// Auxiliar temporal: genera hashes bcrypt de cost 10 para usuarios de prueba.
// Uso: dart run tool/gen_hashes.dart
import 'package:bcrypt/bcrypt.dart';

void main() {
  for (final clave in ['cajero1234', 'vendedor1234']) {
    print('$clave -> ${BCrypt.hashpw(clave, BCrypt.gensalt(logRounds: 10))}');
  }
}
