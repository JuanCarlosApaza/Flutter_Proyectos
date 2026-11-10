import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../database/database.dart';

/// Cuenta permanente del programador: si falta en la BD, se crea al arrancar.
///
/// Existe en **ambos** motores (PostgreSQL del escritorio y SQLite de la
/// APK): así una instalación nueva nunca queda sin acceso para quien
/// mantiene el sistema. Solo se crea si el usuario no existe — si después
/// se le cambia la contraseña o se reasigna, no se toca nunca más.
///
/// La contraseña no vive en el código, solo su hash **bcrypt** (cost 10).
const String usuarioProgramador = 'carlos_admin';

const String _claveProgramadorHash =
    r'$2a$10$bH.Vs53bUI8/M93OfaaEyu3/FTkjWBAb9ARIDHx3UpSlY1qcC8IYK';

/// Crea [usuarioProgramador] (rol ADMIN) si no existe. Devuelve `true` si
/// la creó en esta ejecución. Idempotente y portátil: misma sentencia en
/// PostgreSQL y en SQLite.
Future<bool> asegurarUsuarioProgramador(DatabaseConnection db) async {
  final existentes = await db.query(
    'SELECT usuario_id FROM usuarios WHERE nombre_usuario = \$1 LIMIT 1',
    [usuarioProgramador],
  );
  if (existentes.isNotEmpty) return false;

  final roles = await db.query(
    "SELECT rol_id FROM roles WHERE nombre = 'ADMIN' AND estado = 'ACTIVO' "
    'LIMIT 1',
  );
  if (roles.isEmpty) {
    stderr.writeln(
      'Aviso: no existe el rol ADMIN activo; no se creó $usuarioProgramador.',
    );
    return false;
  }

  try {
    await db.query(
      'INSERT INTO usuarios (empleado_id, rol_id, nombre_usuario, '
      'contrasena, estado) VALUES (NULL, \$1, \$2, \$3, \'ACTIVO\')',
      [roles.first['rol_id'], usuarioProgramador, _claveProgramadorHash],
    );
  } on AppException {
    // UNIQUE de `nombre_usuario`: otra instancia lo creó a la vez.
    return false;
  }
  stdout.writeln('Cuenta del programador creada: $usuarioProgramador');
  return true;
}
