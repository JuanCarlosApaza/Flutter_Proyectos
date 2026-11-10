import 'dart:io';

import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/core/errors/app_exception.dart';
import 'package:farmacia_backend/src/data/storage/almacenamiento_respaldos.dart';
import 'package:farmacia_backend/src/data/storage/programador_respaldos.dart';
import 'package:farmacia_backend/src/domain/entities/ajuste.dart';
import 'package:farmacia_backend/src/domain/repositories/ajuste_repository.dart';
import 'package:farmacia_backend/src/domain/usecases/ajuste_usecases.dart';
import 'package:farmacia_backend/src/domain/usecases/respaldo_usecases.dart';
import 'package:test/test.dart';

/// Base de datos de mentira: solo importa que no se toque la real.
const _db = DbConfig(
  host: 'localhost',
  port: 5432,
  name: 'farmacia',
  user: 'postgres',
  password: 'secreta',
  sslMode: 'disable',
  poolMax: 1,
);

/// `pg_dump` de mentira: escribe el fichero que le mandan (como hace el
/// real con `-f`) y devuelve el código indicado.
List<String>? ultimosArgumentos;
Map<String, String>? ultimoEntorno;

Future<({int codigo, String error})> _falsoPgDump(
  String ejecutable,
  List<String> argumentos,
  Map<String, String> entorno,
) async {
  ultimosArgumentos = argumentos;
  ultimoEntorno = entorno;
  final ruta = argumentos[argumentos.indexOf('-f') + 1];
  File(ruta).writeAsStringSync('PGDMP fake');
  return (codigo: 0, error: '');
}

Future<({int codigo, String error})> _pgDumpRoto(
  String ejecutable,
  List<String> argumentos,
  Map<String, String> entorno,
) async {
  final ruta = argumentos[argumentos.indexOf('-f') + 1];
  File(ruta).writeAsStringSync('a medias');
  return (codigo: 1, error: 'pg_dump: error: la BD no responde');
}

void main() {
  late Directory carpeta;

  AlmacenamientoRespaldos almacen({PgDump? ejecutar}) =>
      AlmacenamientoRespaldos(
        rutaDirectorio: carpeta.path,
        db: _db,
        ejecutable: 'pg_dump',
        ejecutar: ejecutar ?? _falsoPgDump,
      );

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('respaldos_test');
    ultimosArgumentos = null;
    ultimoEntorno = null;
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  group('AlmacenamientoRespaldos', () {
    test('respaldar escribe un .dump con nombre propio y lo lista', () async {
      final creado = await almacen().respaldar();

      expect(AlmacenamientoRespaldos.nombreValido.hasMatch(creado.nombre), isTrue);
      expect(creado.nombre, endsWith('.dump'));
      expect(creado.bytes, greaterThan(0));
      expect(
        File('${carpeta.path}${Platform.pathSeparator}${creado.nombre}')
            .existsSync(),
        isTrue,
      );

      final listado = almacen().listar();
      expect(listado.map((r) => r.nombre), contains(creado.nombre));
      expect(almacen().ultimo()?.nombre, creado.nombre);
    });

    test('la contraseña viaja en el entorno, nunca en la línea de comandos', () async {
      await almacen().respaldar();

      expect(ultimosArgumentos, containsAll(['-Fc', '-h', '-U', '-d']));
      expect(ultimosArgumentos!.join(' '), isNot(contains('secreta')));
      expect(ultimoEntorno!['PGPASSWORD'], 'secreta');
    });

    test('pg_dump fallido: 503 respaldo_fallido y no deja ficheros', () async {
      await expectLater(
        almacen(ejecutar: _pgDumpRoto).respaldar(),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', 'respaldo_fallido')
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
      expect(almacen().listar(), isEmpty);
    });

    test('el nombre de un respaldo no sirve para salir de la carpeta', () async {
      final fuera = File('${carpeta.path}${Platform.pathSeparator}secreto.txt');
      fuera.writeAsStringSync('no me lleves');

      await expectLater(
        almacen().leer('../secreto.txt'),
        throwsA(isA<NotFoundException>()),
      );
      await expectLater(
        almacen().leer('respaldo_2026-01-01_000000.dump'),
        throwsA(isA<NotFoundException>()),
      );
      expect(fuera.existsSync(), isTrue);
    });

    test('se conservan los 30 respaldos más recientes', () async {
      for (var i = 0; i < AlmacenamientoRespaldos.maxRespaldos + 5; i++) {
        await almacen().respaldar();
      }

      final listado = almacen().listar();
      expect(
        listado.length,
        AlmacenamientoRespaldos.maxRespaldos,
        reason: 'la poda debe dejar exactamente el tope',
      );
      // Los que quedan son los más nuevos: el orden es descendente.
      expect(
        listado.first.creado.isAfter(listado.last.creado) ||
            listado.first.creado.isAtSameMomentAs(listado.last.creado),
        isTrue,
      );
    });
  });

  group('Respaldos (caso de uso)', () {
    test('delega en el repositorio', () async {
      final repositorio = almacen();
      final casoUso = Respaldos(repository: repositorio);

      expect(casoUso.listar(), isEmpty);
      expect(casoUso.ultimo(), isNull);

      await casoUso.respaldar();

      expect(casoUso.listar(), hasLength(1));
      expect(casoUso.ultimo(), isNotNull);
      expect(await casoUso.leer(casoUso.ultimo()!.nombre), isNotEmpty);
    });
  });

  group('ProgramadorRespaldos', () {
    test('sin el ajuste del intervalo no programa nada', () async {
      final programador = ProgramadorRespaldos(
        ajustes: Ajustes(repository: _AjusteRepositoryFalso()),
        respaldos: Respaldos(repository: almacen()),
      );
      addTearDown(programador.detener);

      expect(await programador.iniciar(), isNull);
    });

    test('con intervalo devuelve los minutos pendientes y se puede parar', () async {
      final programador = ProgramadorRespaldos(
        ajustes: Ajustes(
          repository: _AjusteRepositoryFalso({
            ProgramadorRespaldos.claveIntervalo: '1440',
          }),
        ),
        respaldos: Respaldos(repository: almacen()),
      );
      addTearDown(programador.detener);

      expect(await programador.iniciar(), 1440);

      // Con un respaldo recién hecho, la cuenta baja pero nunca a cero.
      await almacen().respaldar();
      final pendientes = await programador.reprogramar();
      expect(pendientes, lessThanOrEqualTo(1440));
      expect(pendientes, greaterThan(0));

      // Detener no lanza y deja el temporizador cancelado.
      programador.detener();
      programador.detener();
    });
  });
}

// --- Dobles ----------------------------------------------------------------

/// Repositorio de ajustes en memoria: solo hace falta leerlos.
class _AjusteRepositoryFalso implements AjusteRepository {
  _AjusteRepositoryFalso([Map<String, String>? valores])
    : _valores = {...?valores};

  final Map<String, String> _valores;

  @override
  Future<List<Ajuste>> findAjustes({int limit = 200, int offset = 0}) async {
    final ahora = DateTime.now();
    return [
      for (final ajuste in _valores.entries)
        Ajuste(
          id: 0,
          clave: ajuste.key,
          valor: ajuste.value,
          fechaCreacion: ahora,
          fechaActualizacion: ahora,
        ),
    ];
  }

  @override
  Future<void> upsertAjustes(Map<String, String> valores) async {
    _valores.addAll(valores);
  }
}
