import 'dart:math';

import '../../domain/entities/sesion.dart';
import '../../domain/repositories/sesion_repository.dart';
import '../database/database.dart';
import '../models/sesion_model.dart';

/// Implementación SQL del contrato [SesionRepository].
///
/// El token se genera aquí con [Random.secure]: 32 bytes aleatorios en
/// hexadecimal (64 caracteres) que solo existen en la tabla `sesiones`.
final class SesionRepositoryImpl implements SesionRepository {
  SesionRepositoryImpl(this._db);

  final DatabaseConnection _db;

  static const String _columns = 'token, usuario_id, creada_en, expira_en';

  /// Generador criptográfico (no se reutiliza entre peticiones).
  static final Random _random = Random.secure();

  @override
  Future<Sesion> insert({
    required int usuarioId,
    required DateTime expiraEn,
  }) async {
    final rows = await _db.query(
      'INSERT INTO sesiones (token, usuario_id, expira_en) '
      'VALUES (\$1, \$2, \$3) RETURNING $_columns',
      [_nuevoToken(), usuarioId, expiraEn.toUtc()],
    );
    return SesionModel.sesion(rows.first);
  }

  @override
  Future<Sesion?> findByToken(String token) async {
    final rows = await _db.query(
      'SELECT $_columns FROM sesiones WHERE token = \$1',
      [token],
    );
    return rows.isEmpty ? null : SesionModel.sesion(rows.first);
  }

  @override
  Future<bool> delete(String token) async {
    final rows = await _db.query(
      'DELETE FROM sesiones WHERE token = \$1 RETURNING token',
      [token],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> deleteExpired() async {
    final rows = await _db.query(
      'DELETE FROM sesiones WHERE expira_en < now() RETURNING token',
    );
    return rows.length;
  }

  /// 64 caracteres hexadecimales aleatorios (`2^256` de espacio de claves).
  static String _nuevoToken() => [
    for (var i = 0; i < 32; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
