import 'package:postgres/postgres.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';

/// Acceso centralizado a PostgreSQL.
///
/// - Mantiene un **pool de conexiones** (no se abre una conexión por request).
/// - Es el único punto del backend que conoce `package:postgres`: las
///   violaciones de integridad se traducen aquí a [AppException] para que la
///   capa de dominio no dependa del driver.
/// - El resto de capas trabaja contra esta interfaz, de modo que los
///   repositorios pueden probarse con un doble en memoria.
abstract interface class DatabaseConnection {
  /// Ejecuta una sentencia SELECT y devuelve las filas como mapas
  /// `nombre_columna -> valor`.
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  /// Ejecuta un script SQL que puede contener **varias sentencias**
  /// (se usa solo para migraciones; no admite parámetros).
  Future<void> executeScript(String sql);

  /// Ejecuta [action] dentro de una transacción; si lanza, se hace rollback.
  Future<void> runInTransaction(
    Future<void> Function(DatabaseSession session) action,
  );

  /// Comprueba que la BD responde. Lanza [InfrastructureException] si no.
  Future<void> ping();

  Future<void> close();
}

/// Sesión disponible dentro de una transacción.
abstract interface class DatabaseSession {
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]);

  /// Varias sentencias en la misma transacción (solo migraciones).
  Future<void> executeScript(String sql);
}

/// Implementación real sobre PostgreSQL con pool de conexiones.
final class PostgresDatabase implements DatabaseConnection {
  PostgresDatabase(this._config);

  final DbConfig _config;
  Pool<dynamic>? _pool;

  Pool<dynamic> get _poolOrCreate => _pool ??= Pool.withEndpoints(
    [
      Endpoint(
        host: _config.host,
        port: _config.port,
        database: _config.name,
        username: _config.user,
        password: _config.password,
      ),
    ],
    settings: PoolSettings(
      maxConnectionCount: _config.poolMax,
      applicationName: 'farmacia_backend',
      connectTimeout: const Duration(seconds: 5),
      sslMode: _config.sslMode == 'require' ? SslMode.require : SslMode.disable,
    ),
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    try {
      final result = await _poolOrCreate.execute(
        sql,
        parameters: parameters.isEmpty ? null : parameters,
      );
      return _toMaps(result);
    } on PgException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> executeScript(String sql) async {
    try {
      await _poolOrCreate.execute(sql, queryMode: QueryMode.simple);
    } on PgException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> runInTransaction(
    Future<void> Function(DatabaseSession session) action,
  ) async {
    try {
      await _poolOrCreate.runTx((session) => action(_PgSession(session)));
    } on PgException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> ping() async {
    try {
      await _poolOrCreate.execute('SELECT 1');
    } on PgException catch (e) {
      throw _translate(e);
    } catch (e) {
      throw InfrastructureException(
        'La base de datos no responde: $e',
        code: 'db_unavailable',
      );
    }
  }

  @override
  Future<void> close() async {
    final pool = _pool;
    _pool = null;
    if (pool != null) await pool.close();
  }

  /// Traduce errores del driver a errores de la aplicación.
  AppException _translate(PgException e) {
    if (e is UniqueViolationException) {
      return ConflictException('Registro duplicado: ${e.message}');
    }
    if (e is ForeignKeyViolationException) {
      return ConflictException('Referencia inválida: ${e.message}');
    }
    if (e is ServerException) {
      // SQLSTATE: https://www.postgresql.org/docs/current/errcodes-appendix.html
      // Las violaciones de restricción son datos inválidos del cliente (400),
      // no fallos de infraestructura (503).
      switch (e.code) {
        case '23514': // check_violation (p. ej. edad < 18, stock < 0)
          return BadRequestException(
            'Restricción violada: ${e.message}',
            code: 'check_violation',
          );
        case '23502': // not_null_violation
          return BadRequestException(
            'Falta un campo obligatorio: ${e.message}',
            code: 'not_null',
          );
        case '22001': // string_data_right_truncation
          return BadRequestException(
            'Un texto supera la longitud permitida: ${e.message}',
            code: 'valor_demasiado_largo',
          );
        case '22003': // numeric_value_out_of_range
          return BadRequestException(
            'Número fuera de rango: ${e.message}',
            code: 'valor_fuera_de_rango',
          );
        case '22P02': // invalid_text_representation (casts, enums)
          return BadRequestException(
            'Valor con formato inválido: ${e.message}',
            code: 'valor_invalido',
          );
        case '40P01': // deadlock_detected
        case '55P03': // lock_not_available
          // Con la jerarquía de bloqueos orden → detalles → productos este
          // caso es rarísimo; se traduce a un 409 reintenable y no a un 503.
          return ConflictException(
            'Otra operación está usando los mismos datos al mismo tiempo: '
            'inténtalo de nuevo.',
            code: 'conflicto_concurrente',
          );
      }
      return InfrastructureException(
        'Error de PostgreSQL (${e.code ?? 'sin código'}): ${e.message}',
        code: 'db_query_failed',
      );
    }
    return InfrastructureException(
      'Fallo de conexión con PostgreSQL: ${e.message}',
      code: 'db_unavailable',
    );
  }

  static List<Map<String, Object?>> _toMaps(Result result) => result
      .map((row) => Map<String, Object?>.from(row.toColumnMap()))
      .toList(growable: false);
}

final class _PgSession implements DatabaseSession {
  _PgSession(this._session);

  final TxSession _session;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    final result = await _session.execute(
      sql,
      parameters: parameters.isEmpty ? null : parameters,
    );
    return PostgresDatabase._toMaps(result);
  }

  @override
  Future<void> executeScript(String sql) =>
      _session.execute(sql, queryMode: QueryMode.simple);
}
