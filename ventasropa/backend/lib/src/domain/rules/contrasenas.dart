/// Hash y verificación de contraseñas con **bcrypt** (cost 10).
///
/// La BD solo guarda el hash (`$2a$10$...`, 60 caracteres): la contraseña en
/// claro viaja únicamente en la petición de login/cambio y nunca se persiste
/// ni se devuelve en una respuesta.
///
/// bcrypt solo admite **72 bytes** de entrada (a partir de ahí lanza error);
/// usa [cabeEnBcrypt] para validar antes de [hashContrasena].
library;

import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';

/// Coste de bcrypt: 10 ≈ 50–100 ms por hash (equilibrio estándar entre
/// seguridad y latencia del login).
const int _costeBcrypt = 10;

/// ¿Este valor es un hash bcrypt (y no una contraseña legada en texto plano)?
bool esHashBcrypt(String valor) =>
    RegExp(r'^\$2[aby]\$\d{2}\$').hasMatch(valor);

/// ¿Cabe en bcrypt? (máximo 72 **bytes** UTF-8).
bool cabeEnBcrypt(String valor) => utf8.encode(valor).length <= 72;

/// Hash bcrypt de [plano] con sal aleatoria.
///
/// Lanza [ArgumentError] si [plano] supera los 72 bytes: valida antes con
/// [cabeEnBcrypt].
String hashContrasena(String plano) =>
    BCrypt.hashpw(plano, BCrypt.gensalt(logRounds: _costeBcrypt));

/// ¿[recibida] es la contraseña que corresponde a [guardada]?
///
/// * [guardada] es un hash bcrypt → verificación real de bcrypt.
/// * [guardada] aún está en texto plano (cuenta legada que no pasó por el
///   backfill) → comparación directa; el login la re-hashea al vuelo.
bool verificarContrasena({required String guardada, required String recibida}) {
  if (guardada.isEmpty || recibida.isEmpty) return false;
  if (esHashBcrypt(guardada)) {
    // checkpw lanza error si `recibida` pasa de 72 bytes: se descarta antes.
    if (!cabeEnBcrypt(recibida)) return false;
    return BCrypt.checkpw(recibida, guardada);
  }
  return guardada == recibida;
}
