import 'dart:io';

import '../../domain/rules/contrasenas.dart';
import '../database/database.dart';
import '../models/row_utils.dart';

/// Hashea con **bcrypt** las contraseñas que queden en texto plano.
///
/// Es el paso de datos que acompaña a la introducción del hash: las cuentas
/// creadas antes guardaban la contraseña tal cual y aquí pasan a guardarse
/// como `$2a$10$...`. Idempotente — en cada arranque solo toca las filas que
/// aún no empiezan por `$2`, así que después del primero no encuentra nada.
///
/// Devuelve el número de cuentas re-hasheadas (para el aviso de arranque).
Future<int> hashearContrasenasLegadas(DatabaseConnection db) async {
  final filas = await db.query(r'''
    SELECT usuario_id, contrasena FROM usuarios
    WHERE contrasena NOT LIKE '$2%'
    ''');

  var total = 0;
  var omitidas = 0;
  for (final fila in filas) {
    final guardada = RowUtils.textOrNull(fila['contrasena']);
    // Se omite lo que ya es hash y lo que no cabe en bcrypt (72 bytes): una
    // clave así se queda legada para no romper su login (se contabiliza).
    if (guardada == null ||
        guardada.isEmpty ||
        esHashBcrypt(guardada) ||
        !cabeEnBcrypt(guardada)) {
      if (guardada != null && guardada.isNotEmpty && !cabeEnBcrypt(guardada)) {
        omitidas++;
      }
      continue;
    }
    await db.query(
      'UPDATE usuarios SET contrasena = \$1 WHERE usuario_id = \$2',
      [hashContrasena(guardada), RowUtils.intValue(fila['usuario_id'])],
    );
    total++;
  }
  if (omitidas > 0) {
    stderr.writeln(
      'Aviso: $omitidas contraseña(s) legadas no se han hasheadado '
      '(superan los 72 bytes de bcrypt).',
    );
  }
  return total;
}
