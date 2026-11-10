import '../../core/errors/app_exception.dart';
import 'database.dart';
import 'migraciones_compartidas.dart';
import 'migrations.dart';
import 'migrations_sqlite.dart';

/// Aplica las migraciones pendientes al arrancar.
///
/// - Crea la tabla de control `schema_migrations` si no existe.
/// - Ejecuta en orden cada migración aún no aplicada, **cada una en su
///   propia transacción**: o se aplica entera o no se aplica.
///
/// El motor (`engine`) elige la lista base: PostgreSQL corre las 15
/// migraciones clásicas (`migrations`), SQLite el esquema de partida
/// (`migrationsSqlite`). Después, **ambos** corren las migraciones con
/// fuente única de `migracionesCompartidas`, renderizadas a su dialecto —
/// así un cambio de esquema futuro se escribe una sola vez.
final class Migrator {
  Migrator(this._db, {this.engine = 'postgres'});

  final DatabaseConnection _db;

  /// `postgres` (por defecto) o `sqlite`.
  final String engine;

  bool get _esSqlite => engine == 'sqlite';

  Future<List<String>> migrate() async {
    await _db.executeScript(_esSqlite
        ? '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  name        TEXT PRIMARY KEY,
  applied_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);'''
        : '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  name        TEXT PRIMARY KEY,
  applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);''');

    final applied = (await _db.query('SELECT name FROM schema_migrations'))
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();

    final pendientes = <Migration>[
      ...(_esSqlite ? migrationsSqlite : migrations),
      for (final compartida in migracionesCompartidas)
        Migration(compartida.nombre, compartida.renderizar(engine)),
    ];

    final executed = <String>[];
    for (final migration in pendientes) {
      if (applied.contains(migration.name)) continue;

      try {
        await _db.runInTransaction((session) async {
          await session.executeScript(migration.sql);
          await session.query(
            'INSERT INTO schema_migrations (name) VALUES (\$1)',
            [migration.name],
          );
        });
        executed.add(migration.name);
      } on AppException {
        rethrow;
      } catch (e) {
        throw AppException(
          'Fallo al aplicar la migración ${migration.name}: $e',
          code: 'migration_failed',
        );
      }
    }
    return executed;
  }
}
