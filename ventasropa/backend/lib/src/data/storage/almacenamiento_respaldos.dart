import 'dart:io';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/respaldo.dart';
import '../../domain/repositories/respaldo_repository.dart';

/// Ejecuta `pg_dump` y devuelve su código de salida y su stderr.
///
/// Va separado de la lógica para poder inyectarlo en los tests: así se
/// comprueba el comportamiento sin necesidad de PostgreSQL.
typedef PgDump = Future<({int codigo, String error})> Function(
  String ejecutable,
  List<String> argumentos,
  Map<String, String> entorno,
);

/// Lanza `pg_dump` de verdad.
Future<({int codigo, String error})> ejecutarPgDump(
  String ejecutable,
  List<String> argumentos,
  Map<String, String> entorno,
) async {
  try {
    final proceso = await Process.run(
      ejecutable,
      argumentos,
      environment: entorno,
      runInShell: false,
    );
    return (codigo: proceso.exitCode, error: '${proceso.stderr}'.trim());
  } on ProcessException catch (error) {
    return (
      codigo: -1,
      error: 'No se pudo ejecutar "$ejecutable": ${error.message}',
    );
  }
}

/// Almacenamiento local de los respaldos de la BD (`BACKUPS_DIR`).
///
/// El respaldo lo produce `pg_dump -Fc` (formato comprimido, se restaura con
/// `pg_restore`): este tipo solo decide **dónde** se escribe, **qué nombre
/// lleva**, cuántos se conservan y cómo se leen para servirlos por HTTP.
final class AlmacenamientoRespaldos implements RespaldoRepository {
  AlmacenamientoRespaldos({
    required this.rutaDirectorio,
    required this.db,
    required this.ejecutable,
    PgDump? ejecutar,
    this.copiarBase,
  }) : _ejecutar = ejecutar ?? ejecutarPgDump;

  /// Carpeta de los respaldos (`BACKUPS_DIR`, relativa al CWD).
  final String rutaDirectorio;

  /// Conexión a PostgreSQL (host, puerto, base, usuario y contraseña).
  final DbConfig db;

  /// Ejecutable de `pg_dump` (`PG_DUMP_BIN`).
  final String ejecutable;

  final PgDump _ejecutar;

  /// Respaldo alternativo a `pg_dump` para SQLite (`VACUUM INTO destino`):
  /// copia atómica y consistente del fichero `.db`. Si es `null` se usa
  /// `pg_dump` (motor PostgreSQL, por defecto).
  final Future<void> Function(String destino)? copiarBase;

  /// Respaldos que se conservan: los más recientes se quedan y el resto se
  /// borra tras cada respaldo (una tienda no necesita años de copias).
  static const int maxRespaldos = 30;

  /// Nombre propio del fichero: `respaldo_aaaa-MM-dd_HHmmss.dump`.
  ///
  /// Sale del reloj del servidor y nunca del cliente, así que no hay riesgo
  /// de *path traversal*; aun así, al leerlo se vuelve a validar.
  static final RegExp nombreValido = RegExp(
    r'^respaldo_\d{4}-\d{2}-\d{2}_\d{6}(_\d+)?\.dump$',
  );

  /// Genera un respaldo con `pg_dump -Fc` y devuelve su ficha.
  @override
  Future<Respaldo> respaldar() async {
    final directorio = Directory(rutaDirectorio);
    if (!directorio.existsSync()) {
      directorio.createSync(recursive: true);
    }

    final nombre = _nombreLibre(directorio);
    final ruta = '${directorio.path}${Platform.pathSeparator}$nombre';

    final copia = copiarBase;
    if (copia != null) {
      // Motor SQLite: `VACUUM INTO` escribe una copia íntegra del fichero
      // en [ruta] sin bloquear la base (mismo esquema de nombres que
      // `pg_dump` para que el listado y la descarga sigan igual).
      try {
        await copia(ruta);
      } on AppException {
        rethrow;
      } catch (error) {
        throw InfrastructureException(
          'No se pudo copiar la base de datos: $error',
          code: 'respaldo_fallido',
        );
      }
      if (!File(ruta).existsSync()) {
        throw const InfrastructureException(
          'La copia no escribió el fichero.',
          code: 'respaldo_fallido',
        );
      }
      final ficha = _ficha(File(ruta));
      _podar(directorio);
      return ficha;
    }

    final resultado = await _ejecutar(
      ejecutable,
      [
        '-h',
        db.host,
        '-p',
        '${db.port}',
        '-U',
        db.user,
        '-d',
        db.name,
        '-Fc',
        '-f',
        ruta,
      ],
      // La contraseña viaja SOLO en el entorno del proceso hijo: ni aparece
      // en la lista de procesos del sistema ni se puede colar en un log.
      {'PGPASSWORD': db.password},
    );

    final fichero = File(ruta);
    if (resultado.codigo != 0) {
      // Un `pg_dump` fallido puede dejar un fichero a medias: se borra para
      // que no aparezca como un respaldo válido en el listado.
      if (fichero.existsSync()) fichero.deleteSync();
      final detalle = resultado.error.isEmpty
          ? 'código de salida ${resultado.codigo}'
          : resultado.error;
      if (resultado.error.contains('No se pudo ejecutar')) {
        throw InfrastructureException(
          '$detalle. Comprueba que pg_dump esté en el PATH o define '
          'PG_DUMP_BIN con su ruta completa.',
          code: 'respaldo_fallido',
        );
      }
      throw InfrastructureException(
        'pg_dump terminó con un error: $detalle',
        code: 'respaldo_fallido',
      );
    }
    if (!fichero.existsSync()) {
      throw const InfrastructureException(
        'pg_dump terminó sin escribir el fichero.',
        code: 'respaldo_fallido',
      );
    }

    final info = _ficha(fichero);
    _podar(directorio);
    return info;
  }

  /// Respaldos existentes, del más reciente al más antiguo.
  @override
  List<Respaldo> listar() {
    final directorio = Directory(rutaDirectorio);
    if (!directorio.existsSync()) return const [];

    final ficheros = directorio
        .listSync(followLinks: false)
        .whereType<File>()
        .where((fichero) => nombreValido.hasMatch(_nombreDe(fichero)))
        .toList();

    final respaldos = [for (final fichero in ficheros) _ficha(fichero)];
    respaldos.sort((a, b) => b.creado.compareTo(a.creado));
    return respaldos;
  }

  /// El respaldo más reciente, o `null` si la carpeta está vacía.
  @override
  Respaldo? ultimo() {
    final respaldos = listar();
    return respaldos.isEmpty ? null : respaldos.first;
  }

  /// Bytes de un respaldo para servirlo por HTTP (`404` si no existe).
  @override
  Future<List<int>> leer(String nombre) async {
    final fichero = _ficheroDe(nombre);
    if (!fichero.existsSync()) {
      throw const NotFoundException(
        'Respaldo no encontrado.',
        code: 'respaldo_no_encontrado',
      );
    }
    return fichero.readAsBytes();
  }

  /// Fichero de un respaldo (`404` si el nombre no está bien formado).
  File _ficheroDe(String nombre) {
    final limpio = nombre.trim();
    if (!nombreValido.hasMatch(limpio)) {
      throw const NotFoundException(
        'Respaldo no encontrado.',
        code: 'respaldo_no_encontrado',
      );
    }
    return File(
      '${Directory(rutaDirectorio).path}${Platform.pathSeparator}$limpio',
    );
  }

  /// Nombre de fichero que todavía no existe en la carpeta.
  String _nombreLibre(Directory directorio) {
    final base = 'respaldo_${_sello(DateTime.now())}';
    var nombre = '$base.dump';
    var intento = 1;
    while (
        File('${directorio.path}${Platform.pathSeparator}$nombre')
            .existsSync()) {
      intento++;
      nombre = '${base}_$intento.dump';
    }
    return nombre;
  }

  /// Conserva solo los [maxRespaldos] más recientes.
  void _podar(Directory directorio) {
    final sobrantes = listar().skip(maxRespaldos);
    for (final respaldo in sobrantes) {
      final fichero = File(
        '${directorio.path}${Platform.pathSeparator}${respaldo.nombre}',
      );
      try {
        if (fichero.existsSync()) fichero.deleteSync();
      } on FileSystemException {
        // Un fichero bloqueado no puede tumbar el respaldo recién hecho.
      }
    }
  }

  Respaldo _ficha(File fichero) {
    final stat = fichero.statSync();
    return Respaldo(
      nombre: _nombreDe(fichero),
      bytes: stat.size,
      creado: stat.modified,
    );
  }

  static String _nombreDe(File fichero) =>
      fichero.uri.pathSegments.last;

  static String _sello(DateTime momento) =>
      '${momento.year.toString().padLeft(4, '0')}-'
      '${(momento.month).toString().padLeft(2, '0')}-'
      '${momento.day.toString().padLeft(2, '0')}_'
      '${momento.hour.toString().padLeft(2, '0')}'
      '${momento.minute.toString().padLeft(2, '0')}'
      '${momento.second.toString().padLeft(2, '0')}';
}
