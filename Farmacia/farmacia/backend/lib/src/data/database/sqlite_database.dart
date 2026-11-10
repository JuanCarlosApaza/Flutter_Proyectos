import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../core/errors/app_exception.dart';
import 'database.dart';
import 'dialecto.dart';

/// Traduce una sentencia escrita para PostgreSQL al dialecto de SQLite.
///
/// Solo se toca el **código** SQL: los literales entre comillas simples se
/// copian tal cual (un `NOT LIKE '$2%'` no debe convertirse en un
/// parámetro). La traducción es mecánica y cubre lo que usa este backend:
///
/// * `$1` → `?1` (marcadores posicionales);
/// * `col = ANY($1)` → `col IN (SELECT value FROM json_each(?1))`;
/// * se eliminan los casts `::int`, `::text`, `::jsonb`, `::estado_*`...;
/// * `ILIKE` → `LIKE` (SQLite ya ignora mayúsculas ASCII por defecto);
/// * `IS DISTINCT FROM` → `IS NOT` (ambos son nulo-seguros en SQLite);
/// * `SELECT ... FOR UPDATE` → se elimina (SQLite es de un solo escritor y
///   la transacción se toma con `BEGIN IMMEDIATE`);
/// * `now()` → `CURRENT_TIMESTAMP` (mismo formato `yyyy-MM-dd HH:mm:ss`).
String traducirSqlite(String sql) {
  final salida = StringBuffer();
  final codigo = StringBuffer();
  var i = 0;

  while (i < sql.length) {
    final caracter = sql[i];
    if (caracter != "'") {
      codigo.write(caracter);
      i++;
      continue;
    }
    // Fin de segmento de código: se traduce y empieza un literal.
    salida.write(_traducirCodigo(codigo.toString()));
    codigo.clear();
    salida.write("'");
    i++;
    while (i < sql.length) {
      final c = sql[i];
      salida.write(c);
      i++;
      if (c != "'") continue;
      // `''` dentro del literal: se consume y se sigue dentro.
      if (i < sql.length && sql[i] == "'") {
        salida.write("'");
        i++;
        continue;
      }
      break;
    }
  }
  salida.write(_traducirCodigo(codigo.toString()));
  return salida.toString();
}

/// Casts de PostgreSQL que se descartan (SQLite convierte por contexto).
final RegExp _casteosPostgres = RegExp(
  r'::\s*(?:double\s+precision|timestamp(?:\s+with\s+time\s+zone)?|'
  r'timestamptz|numeric(?:\(\d+(?:,\s*\d+)?\))?|decimal(?:\(\d+(?:,\s*\d+)?\))?|'
  r'varchar\(\d+\)|char(?:acter)?(?:\(\d+\))?|text|jsonb?|boole?an|'
  r'integer|int[248]?|bigint|smallint|real|float[48]?|date|estado_\w+)',
  caseSensitive: false,
);

String _traducirCodigo(String sql) {
  if (sql.isEmpty) return sql;
  var s = sql;
  s = s.replaceAllMapped(
    RegExp(r'=\s*ANY\(\s*\$(\d+)\s*\)', caseSensitive: false),
    (m) => 'IN (SELECT value FROM json_each(\$${m[1]}))',
  );
  s = s.replaceAllMapped(RegExp(r'\$(\d+)'), (m) => '?${m[1]}');
  s = s.replaceAll(_casteosPostgres, '');
  s = s.replaceAll(RegExp(r'\bILIKE\b', caseSensitive: false), 'LIKE');
  s = s.replaceAll(
    RegExp(r'\bIS\s+DISTINCT\s+FROM\b', caseSensitive: false),
    'IS NOT',
  );
  s = s.replaceAll(RegExp(r'\s+FOR\s+UPDATE\b'), '');
  s = s.replaceAllMapped(
    RegExp(r'\bnow\s*\(\s*\)', caseSensitive: false),
    (_) => 'CURRENT_TIMESTAMP',
  );
  return s;
}

/// Semántica de `translate()` de PostgreSQL para la función personalizada.
Object? _translate(List<Object?> args) {
  final texto = args[0];
  final desde = args[1];
  final hasta = args[2];
  if (texto is! String || desde is! String || hasta is! String) return null;
  final buffer = StringBuffer();
  for (final codigo in texto.runes) {
    final caracter = String.fromCharCode(codigo);
    final posicion = desde.indexOf(caracter);
    if (posicion < 0) {
      buffer.write(caracter);
    } else if (posicion < hasta.length) {
      buffer.write(hasta[posicion]);
    }
    // posición fuera de `hasta`: el carácter se elimina (como en PG).
  }
  return buffer.toString();
}

/// Parámetro de Dart al tipo que `package:sqlite3` sabe enlazar.
///
/// * `DateTime` → texto con el **reloj de pared** (`yyyy-MM-dd HH:mm:ss.SSS`,
///   o solo `yyyy-MM-dd` si es medianoche): así las fechas comparan
///   lexicográficamente igual que las que escribe `CURRENT_TIMESTAMP` y las
///   columnas `DATE` no sufren corrimiento de zona horaria.
/// * `bool` → `0/1`; `List` → array JSON (para `json_each`).
Object? _adaptarParametro(Object? valor) {
  if (valor is DateTime) return _textoFecha(valor);
  if (valor is bool) return valor ? 1 : 0;
  if (valor is List) return jsonEncode(valor);
  return valor;
}

String _textoFecha(DateTime f) {
  String p(int v, [int ancho = 2]) => v.toString().padLeft(ancho, '0');
  final fecha = '${p(f.year, 4)}-${p(f.month)}-${p(f.day)}';
  final esMedianoche =
      f.hour == 0 && f.minute == 0 && f.second == 0 && f.millisecond == 0;
  if (esMedianoche) return fecha;
  return '$fecha ${p(f.hour)}:${p(f.minute)}:${p(f.second)}.${p(f.millisecond, 3)}';
}

/// Traduce errores del driver a los mismos [AppException] que usa el
/// adaptador de PostgreSQL (la capa de HTTP no nota el cambio de motor).
Object _mapearError(Object e) {
  if (e is! SqliteException) return e;
  switch (e.resultCode) {
    case SqlError.SQLITE_CONSTRAINT:
      switch (e.extendedResultCode) {
        case SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY:
          return ConflictException('Referencia inválida: ${e.message}');
        case SqlExtendedError.SQLITE_CONSTRAINT_NOTNULL:
          return BadRequestException(
            'Falta un campo obligatorio: ${e.message}',
            code: 'not_null',
          );
        case SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE:
        case SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY:
        case SqlExtendedError.SQLITE_CONSTRAINT_ROWID:
          return ConflictException('Registro duplicado: ${e.message}');
        default:
          return BadRequestException(
            'Restricción violada: ${e.message}',
            code: 'check_violation',
          );
      }
    case SqlError.SQLITE_BUSY:
    case SqlError.SQLITE_LOCKED:
      return ConflictException(
        'Otra operación está usando los mismos datos al mismo tiempo: '
        'inténtalo de nuevo.',
        code: 'conflicto_concurrente',
      );
    case SqlError.SQLITE_MISMATCH:
      return BadRequestException(
        'Valor con formato inválido: ${e.message}',
        code: 'valor_invalido',
      );
    case SqlError.SQLITE_FULL:
    case SqlError.SQLITE_CANTOPEN:
    case SqlError.SQLITE_IOERR:
    case SqlError.SQLITE_READONLY:
      return InfrastructureException(
        'No se puede leer o escribir la base de datos: ${e.message}',
        code: 'db_unavailable',
      );
    default:
      return InfrastructureException(
        'Error de SQLite (${e.extendedResultCode}): ${e.message}',
        code: 'db_query_failed',
      );
  }
}

/// Implementación de [DatabaseConnection] sobre SQLite (`package:sqlite3`).
///
/// Diseño:
///
/// * **Una sola conexión** y **una cola de operaciones**: SQLite es de un
///   solo escritor y, sobre todo, una transacción abierta no debe mezclarse
///   con las consultas de otras peticiones HTTP que lleguen mientras tanto
///   (con el pool de PostgreSQL eso lo garantizaba `runTx`).
/// * [runInTransaction] usa `BEGIN IMMEDIATE` — el equivalente práctico del
///   `SELECT ... FOR UPDATE` de PostgreSQL aquí — y corre en una **zona**
///   propia: solo el código invocado desde esa transacción ve el flag y entra
///   en línea; las peticiones concurrentes siguen esperando en la cola.
/// * El SQL pasa por [traducirSqlite] antes de ejecutarse.
final class SqliteDatabase implements DatabaseConnection {
  SqliteDatabase(this.ruta) {
    Dialecto.sqlite = true;
    _db = sqlite3.open(ruta);
    // FKs desactivadas por defecto en SQLite: sin esto no existirían ni
    // RESTRICT ni CASCADE y el comportamiento divergiría de PostgreSQL.
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('PRAGMA busy_timeout = 5000;');
    // `translate(texto, desde, hasta)` no existe en SQLite y es la base de
    // la búsqueda insensible a acentos (`ilike()` del catálogo y
    // `andBusqueda`): se registra aquí con la semántica de PostgreSQL
    // (carácter de `desde` → el de la misma posición en `hasta`; los que
    // sobran en `desde` se eliminan).
    _db.createFunction(
      functionName: 'translate',
      argumentCount: const AllowedArgumentCount(3),
      deterministic: true,
      directOnly: false,
      function: _translate,
    );
  }

  /// Ruta del fichero `.db` (o `:memory:` en pruebas).
  final String ruta;

  late final Database _db;

  /// Marca de "estamos dentro de la transacción activa" (por zona).
  static const Object _claveTransaccion = #transaccionSqlite;

  int _profundidadTransaccion = 0;
  Future<void> _pendiente = Future<void>.value();

  bool get _enTransaccion => Zone.current[_claveTransaccion] == true;

  /// Encola [operacion] detrás de lo que haya pendiente. Dentro de una
  /// transacción activa se ejecuta en línea (ya está serializada).
  Future<T> _cola<T>(Future<T> Function() operacion) {
    if (_enTransaccion) return operacion();
    final resultado = _pendiente.then((_) => operacion());
    _pendiente = resultado.then((_) {}, onError: (_) {});
    return resultado;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return _cola(() async {
      final parametros = [
        for (final parametro in parameters) _adaptarParametro(parametro),
      ];
      try {
        final filas = _db.select(traducirSqlite(sql), parametros);
        // PostgreSQL pliega los identificadores sin comillas a minúsculas
        // (`Categoria_ID` llega como `categoria_id`); SQLite conserva la
        // caja original. Se normaliza aquí para que los modelos lean las
        // claves igual con ambos motores.
        return [
          for (final fila in filas)
            {
              for (final entrada in fila.entries)
                entrada.key.toLowerCase(): entrada.value,
            },
        ];
      } catch (e) {
        throw _mapearError(e);
      }
    });
  }

  @override
  Future<void> executeScript(String sql) {
    return _cola(() async {
      try {
        // Sin parámetros: `execute` admite varias sentencias separadas por
        // punto y coma y se detiene en la primera que falle.
        _db.execute(traducirSqlite(sql));
      } catch (e) {
        throw _mapearError(e);
      }
    });
  }

  @override
  Future<void> runInTransaction(
    Future<void> Function(DatabaseSession session) action,
  ) {
    return _cola(() async {
      // Transacción anidada (no ocurre hoy, pero un `runInTransaction`
      // dentro de otro debe ser un savepoint, nunca un BEGIN ilegal).
      if (_enTransaccion) {
        final nombre = 'sp_${_profundidadTransaccion + 1}';
        _profundidadTransaccion++;
        _db.execute('SAVEPOINT $nombre');
        try {
          await action(_SesionSqlite(this));
          _db.execute('RELEASE $nombre');
        } catch (e) {
          _db.execute('ROLLBACK TO $nombre');
          _db.execute('RELEASE $nombre');
          throw _mapearError(e);
        } finally {
          _profundidadTransaccion--;
        }
        return;
      }

      await runZoned(
        () async {
          _db.execute('BEGIN IMMEDIATE');
          try {
            await action(_SesionSqlite(this));
            _db.execute('COMMIT');
          } catch (e) {
            try {
              _db.execute('ROLLBACK');
            } on SqliteException {
              // La transacción ya no está abierta: el error original manda.
            }
            throw _mapearError(e);
          }
        },
        zoneValues: {_claveTransaccion: true},
      );
    });
  }

  @override
  Future<void> ping() {
    return _cola(() async {
      try {
        _db.select('SELECT 1');
      } catch (e) {
        throw e is SqliteException
            ? InfrastructureException(
                'La base de datos no responde: ${e.message}',
                code: 'db_unavailable',
              )
            : _mapearError(e);
      }
    });
  }

  @override
  Future<void> close() {
    return _cola(() async {
      _db.close();
    });
  }
}

/// Sesión dentro de una transacción: delega en la conexión, que ya sabe (por
/// zona) que debe ejecutar en línea en vez de encolar.
final class _SesionSqlite implements DatabaseSession {
  _SesionSqlite(this._dueno);

  final SqliteDatabase _dueno;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) => _dueno.query(sql, parameters);

  @override
  Future<void> executeScript(String sql) => _dueno.executeScript(sql);
}
