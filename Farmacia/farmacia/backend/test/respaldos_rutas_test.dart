import 'dart:io';

import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/data/storage/almacenamiento_respaldos.dart';
import 'package:farmacia_backend/src/domain/entities/sesion.dart';
import 'package:farmacia_backend/src/domain/usecases/respaldo_usecases.dart';
import 'package:farmacia_backend/src/presentation/http/middlewares.dart';
import 'package:farmacia_backend/src/presentation/routes/respaldo_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// `pg_dump` de mentira: escribe el fichero que le mandan y devuelve 0.
Future<({int codigo, String error})> _falsoPgDump(
  String ejecutable,
  List<String> argumentos,
  Map<String, String> entorno,
) async {
  File(argumentos[argumentos.indexOf('-f') + 1]).writeAsStringSync('PGDMP fake');
  return (codigo: 0, error: '');
}

void main() {
  late Directory carpeta;
  late Handler handler;

  /// Monta las rutas reales sobre un almacenamiento real (carpeta temporal
  /// y `pg_dump` falso): solo la sesión del request es un doble.
  Handler montar() {
    final almacen = AlmacenamientoRespaldos(
      rutaDirectorio: carpeta.path,
      db: const DbConfig(
        host: 'localhost',
        port: 5432,
        name: 'farmacia',
        user: 'postgres',
        password: 'x',
        sslMode: 'disable',
        poolMax: 1,
      ),
      ejecutable: 'pg_dump',
      ejecutar: _falsoPgDump,
    );
    final router = Router();
    addRespaldoRoutes(router, respaldos: Respaldos(repository: almacen));
    // El mismo envoltorio que en producción: traduce las excepciones de
    // dominio a JSON con su código HTTP.
    return errorHandler()(router.call);
  }

  /// Request con sesión de prueba (patrón de `permisos_test`).
  Request conSesion({
    Set<String> permisos = const {},
    String metodo = 'GET',
    String ruta = '/api/v1/respaldos',
  }) {
    final usuario = usuarioDePrueba(permisos: permisos);
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    return Request(metodo, Uri.parse('http://localhost$ruta')).change(
      context: {'sesion': sesion},
    );
  }

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('respaldos_rutas_test');
    handler = montar();
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  test('POST /respaldos con ajustes.editar crea el .dump (201)', () async {
    final respuesta = await handler(
      conSesion(
        metodo: 'POST',
        permisos: {'ajustes.editar', 'ajustes.ver'},
      ),
    );

    expect(respuesta.statusCode, 201);
    final cuerpo = await respuesta.readAsString();
    expect(cuerpo, contains('"id":0'));
    expect(cuerpo, contains('"nombre":"respaldo_'));
    expect(cuerpo, contains('"bytes":'));

    // El listado ya lo incluye (permiso ajustes.ver).
    final listado = await handler(conSesion(permisos: {'ajustes.ver'}));
    expect(listado.statusCode, 200);
    expect(await listado.readAsString(), contains('respaldo_'));
  });

  test('POST /respaldos sin permiso responde 403 permiso_denegado', () async {
    final respuesta = await handler(conSesion(metodo: 'POST'));

    expect(respuesta.statusCode, 403);
    expect(await respuesta.readAsString(), contains('permiso_denegado'));
  });

  test('sin sesión responde 401', () async {
    final respuesta = await handler(
      Request('GET', Uri.parse('http://localhost/api/v1/respaldos')),
    );

    expect(respuesta.statusCode, 401);
  });

  test('GET /respaldos/{nombre}/descarga entrega los bytes como adjunto', () async {
    await handler(
      conSesion(metodo: 'POST', permisos: {'ajustes.editar'}),
    );
    final listado = await handler(conSesion(permisos: {'ajustes.ver'}));
    final cuerpo = await listado.readAsString();
    final nombre = RegExp('"nombre":"([^"]+)"').firstMatch(cuerpo)!.group(1)!;

    final descarga = await handler(
      conSesion(
        permisos: {'ajustes.editar'},
        ruta: '/api/v1/respaldos/$nombre/descarga',
      ),
    );

    expect(descarga.statusCode, 200);
    expect(descarga.headers['content-type'], 'application/octet-stream');
    expect(
      descarga.headers['content-disposition'],
      'attachment; filename="$nombre"',
    );
    expect(await descarga.read().fold<List<int>>([], (a, b) => a..addAll(b)),
        isNotEmpty);
  });

  test('descarga sin ajustes.editar o con nombre raro no deja pasar nada', () async {
    await handler(
      conSesion(metodo: 'POST', permisos: {'ajustes.editar'}),
    );
    final listado = await handler(conSesion(permisos: {'ajustes.ver'}));
    final nombre = RegExp('"nombre":"([^"]+)"')
        .firstMatch(await listado.readAsString())!
        .group(1)!;

    // Quien solo puede leer no se lleva el fichero.
    final sinPermiso = await handler(
      conSesion(permisos: {'ajustes.ver'}, ruta: '/api/v1/respaldos/$nombre/descarga'),
    );
    expect(sinPermiso.statusCode, 403);

    // Un nombre fuera del patrón no toca la carpeta.
    final raro = await handler(
      conSesion(
        permisos: {'ajustes.editar'},
        ruta: '/api/v1/respaldos/../../secretos/descarga',
      ),
    );
    expect(raro.statusCode, 404);

    // Patrón correcto pero sin fichero.
    final ausente = await handler(
      conSesion(
        permisos: {'ajustes.editar'},
        ruta: '/api/v1/respaldos/respaldo_1999-01-01_000000.dump/descarga',
      ),
    );
    expect(ausente.statusCode, 404);
  });
}
