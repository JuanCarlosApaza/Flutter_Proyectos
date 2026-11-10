/// Migraciones con **fuente única**: se definen una sola vez y corren en
/// ambos motores (PostgreSQL para escritorio/web, SQLite para la APK).
///
/// Cómo se usa (regla para futuros cambios de esquema):
///
/// 1. Añade una entrada a [migracionesCompartidas] con el siguiente nombre
///    incremental (`016_...`, `017_...`...).
/// 2. Expresa cada paso con una operación estructurada ([AgregarColumna],
///    [AgregarIndice] o [SqlCompartido]): el `Migrator` la renderiza al
///    dialecto que corresponda según `DB_ENGINE`.
/// 3. Solo si algo no se puede expresar de forma estructurada, usa
///    [SqlPorMotor] — es el **único** sitio donde se escribe SQL por motor.
///
/// El registro `schema_migrations` garantiza que cada migración corre una
/// sola vez en cada base de datos, igual que las 15 clásicas de
/// `migrations.dart` (que no se tocan: ya están aplicadas en producción).
library;

/// Una migración: pasos estructurados con nombre incremental.
final class Migracion {
  const Migracion(this.nombre, this.operaciones);

  /// Nombre incremental único (`016_agrega_columna_x`).
  final String nombre;

  final List<OperacionDdl> operaciones;

  /// SQL de la migración para el motor indicado (`postgres` | `sqlite`).
  String renderizar(String engine) => [
    for (final operacion in operaciones)
      engine == 'sqlite' ? operacion.sqlite : operacion.postgres,
  ].join('\n');
}

/// Un paso de migración traducible a cada motor.
abstract class OperacionDdl {
  const OperacionDdl();

  String get postgres;
  String get sqlite;
}

/// SQL idéntico en ambos motores (sentencias que ya son portables).
final class SqlCompartido extends OperacionDdl {
  const SqlCompartido(this.sql);

  final String sql;

  @override
  String get postgres => sql;

  @override
  String get sqlite => sql;
}

/// Escape hatch: SQL escrito a mano por motor. Úsalo solo cuando la
/// operación no se pueda expresar con las estructuradas (p. ej. un cambio
/// que dependa de funciones exclusivas de cada motor).
final class SqlPorMotor extends OperacionDdl {
  const SqlPorMotor({required this.postgres, required this.sqlite});

  @override
  final String postgres;

  @override
  final String sqlite;
}

/// `ALTER TABLE ... ADD COLUMN`.
///
/// Los tipos van por motor porque lo que cambia es la equivalencia
/// (`TIMESTAMPTZ` ↔ `TEXT`); el resto de la definición es una sola.
final class AgregarColumna extends OperacionDdl {
  const AgregarColumna({
    required this.tabla,
    required this.columna,
    required this.tipoPostgres,
    required this.tipoSqlite,
    this.porDefecto,
    this.noNula = false,
  });

  final String tabla;
  final String columna;
  final String tipoPostgres;
  final String tipoSqlite;

  /// Literal de valor por defecto (`'ACTIVO'`, `0`...); `null` sin defecto.
  final Object? porDefecto;

  final bool noNula;

  String _sql(String tipo) => 'ALTER TABLE $tabla ADD COLUMN $columna $tipo'
      '${noNula ? ' NOT NULL' : ''}'
      '${porDefecto == null ? '' : ' DEFAULT $porDefecto'}';

  @override
  String get postgres => _sql(tipoPostgres);

  @override
  String get sqlite => _sql(tipoSqlite);
}

/// `CREATE INDEX` (la sentencia es idéntica en ambos motores).
final class AgregarIndice extends OperacionDdl {
  const AgregarIndice({
    required this.nombre,
    required this.tabla,
    required this.columnas,
    this.unico = false,
    this.donde,
  });

  final String nombre;
  final String tabla;
  final String columnas;
  final bool unico;

  /// Expresión opcional `WHERE ...` (índice parcial).
  final String? donde;

  String get _sql => 'CREATE INDEX IF NOT EXISTS $nombre ON $tabla '
      '${unico ? 'UNIQUE ' : ''}($columnas)'
      '${donde == null ? '' : ' WHERE $donde'}';

  @override
  String get postgres => _sql;

  @override
  String get sqlite => _sql;
}

/// Lista única de migraciones futuras (ambos motores).
///
/// Las 15 migraciones originales de PostgreSQL viven en `migrations.dart`
/// y el esquema base de SQLite en `migrations_sqlite.dart`; esta lista es
/// para TODO lo que se cambie a partir de ahora.
const List<Migracion> migracionesCompartidas = [
  // Ejemplo de uso (se añade cuando toque el próximo cambio de esquema):
  // Migracion('016_xxx', [
  //   AgregarColumna(tabla: 'productos', columna: 'xxx', ...),
  // ]),
];
