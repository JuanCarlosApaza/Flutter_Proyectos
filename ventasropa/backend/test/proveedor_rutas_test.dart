import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/repositories/persona_repository_impl.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/usecases/persona_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/persona_routes.dart';

import 'fakes.dart';

/// Rutas HTTP de proveedores sobre una base SQLite recién migrada.
///
/// Cubre los campos nuevos `email` y `nit` de extremo a extremo: pasan por
/// la petición JSON, la validación del dominio, el repositorio SQL y la
/// columna que la `022_proveedores_email_nit` crea.
void main() {
  const permisos = {
    'proveedores.ver',
    'proveedores.crear',
    'proveedores.editar',
  };

  late Directory dir;
  late SqliteDatabase db;
  late Handler handler;

  /// Petición con sesión de prueba; [cuerpo] va en JSON cuando viene.
  Future<Response> enviar(
    String metodo,
    String ruta, {
    Object? cuerpo,
  }) async {
    final usuario = usuarioDePrueba(permisos: permisos);
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    final peticion = Request(
      metodo,
      Uri.parse('http://localhost$ruta'),
      body: cuerpo == null ? null : jsonEncode(cuerpo),
      headers: cuerpo == null
          ? null
          : {'content-type': 'application/json'},
    ).change(context: {'sesion': sesion});
    return handler(peticion);
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('proveedor_rutas');
    db = SqliteDatabase('${dir.path}${Platform.pathSeparator}ventas.db');
    await Migrator(db, engine: 'sqlite').migrate();

    final router = Router();
    final personas = PersonaRepositoryImpl(db);
    addPersonaRoutes(
      router,
      clientes: Clientes(repository: personas),
      proveedores: Proveedores(repository: personas),
      empleados: Empleados(repository: personas),
    );
    handler = errorHandler()(router.call);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('POST guarda email y NIT y el GET los devuelve', () async {
    final creada = await enviar(
      'POST',
      '/api/v1/proveedores',
      cuerpo: {
        'nombre': 'Distribuidora Norte',
        'email': ' contactos@norte.com.bo ',
        'nit': '1023456027',
      },
    );
    expect(creada.statusCode, 201);

    final json = jsonDecode(await creada.readAsString())
        as Map<String, Object?>;
    expect(json['email'], 'contactos@norte.com.bo');
    expect(json['nit'], '1023456027');

    final lista = await enviar('GET', '/api/v1/proveedores');
    final items =
        (jsonDecode(await lista.readAsString())['items'] as List)
            .cast<Map<String, Object?>>();
    expect(items.single['email'], 'contactos@norte.com.bo');
    expect(items.single['nit'], '1023456027');
  });

  test('sin email ni NIT se dan de alta (campos opcionales)', () async {
    final creada = await enviar(
      'POST',
      '/api/v1/proveedores',
      cuerpo: {'nombre': 'Sin Datos SAC'},
    );
    expect(creada.statusCode, 201);

    final json = jsonDecode(await creada.readAsString())
        as Map<String, Object?>;
    expect(json['email'], isNull);
    expect(json['nit'], isNull);
  });

  test('la búsqueda libre encuentra un proveedor por su NIT', () async {
    await enviar(
      'POST',
      '/api/v1/proveedores',
      cuerpo: {'nombre': 'Textiles Andinos', 'nit': '3012345018'},
    );

    final buscada = await enviar(
      'GET',
      '/api/v1/proveedores?q=3012345018',
    );
    final items =
        (jsonDecode(await buscada.readAsString())['items'] as List)
            .cast<Map<String, Object?>>();
    expect(items.single['nombre'], 'Textiles Andinos');
  });

  test('un email inválido en el alta responde 400 email_invalido', () async {
    final creada = await enviar(
      'POST',
      '/api/v1/proveedores',
      cuerpo: {'nombre': 'Mala Forma', 'email': 'sin-arroba'},
    );
    expect(creada.statusCode, 400);
    expect(await creada.readAsString(), contains('email_invalido'));
  });

  test('PUT edita el email y limpia el NIT con null', () async {
    final creada = await enviar(
      'POST',
      '/api/v1/proveedores',
      cuerpo: {
        'nombre': 'Alpaca Sur',
        'email': 'hola@alpaca.bo',
        'nit': '1234567018',
      },
    );
    final id = (jsonDecode(await creada.readAsString())
        as Map<String, Object?>)['id'];

    final editada = await enviar(
      'PUT',
      '/api/v1/proveedores/$id',
      cuerpo: {'email': 'ventas@alpaca.bo', 'nit': null},
    );
    expect(editada.statusCode, 200);

    final json = jsonDecode(await editada.readAsString())
        as Map<String, Object?>;
    expect(json['email'], 'ventas@alpaca.bo');
    expect(json['nit'], isNull);

    // `nit` ausente en el PUT no toca el valor guardado.
    final soloTelefono = await enviar(
      'PUT',
      '/api/v1/proveedores/$id',
      cuerpo: {'telefono': '274-0000'},
    );
    expect(soloTelefono.statusCode, 200);
    final trasEdicion = jsonDecode(await soloTelefono.readAsString())
        as Map<String, Object?>;
    expect(trasEdicion['email'], 'ventas@alpaca.bo');
    expect(trasEdicion['nit'], isNull);
    expect(trasEdicion['telefono'], '274-0000');
  });

  test('PUT con un NIT mal formado responde 400 nit_invalido', () async {
    final creada = await enviar(
      'POST',
      '/api/v1/proveedores',
      cuerpo: {'nombre': 'Fiscalia Menor'},
    );
    final id = (jsonDecode(await creada.readAsString())
        as Map<String, Object?>)['id'];

    final editada = await enviar(
      'PUT',
      '/api/v1/proveedores/$id',
      cuerpo: {'nit': '12 34'},
    );
    expect(editada.statusCode, 400);
    expect(await editada.readAsString(), contains('nit_invalido'));
  });
}
