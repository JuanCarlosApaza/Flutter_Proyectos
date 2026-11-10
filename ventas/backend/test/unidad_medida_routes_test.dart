import 'dart:convert';

import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/usecases/unidad_medida_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/unidad_medida_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// HTTP de `/api/v1/unidades` sobre el repositorio falso: mismos middlewares
/// que en producción (`errorHandler` traduce las excepciones de dominio a JSON
/// con su código) y sesión de prueba en el contexto del request.
///
/// Las reglas del negocio ya tienen su sitio en `unidad_medida_test.dart`;
/// aquí se comprueba que las rutas no las tuerzan: permisos, códigos HTTP,
/// lectura de cuerpos y metadatos de paginación.
void main() {
  late FakeUnidadMedidaRepository repo;
  late Handler handler;

  Handler montar() {
    final router = Router();
    addUnidadMedidaRoutes(router, unidades: Unidades(repository: repo));
    return errorHandler()(router.call);
  }

  Request conSesion({
    Set<String> permisos = const {},
    String metodo = 'GET',
    String ruta = '/api/v1/unidades',
    Object? cuerpo,
  }) {
    final usuario = usuarioDePrueba(permisos: permisos);
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    return Request(
      metodo,
      Uri.parse('http://localhost$ruta'),
      body: cuerpo == null ? null : jsonEncode(cuerpo),
      headers: cuerpo == null ? null : {'content-type': 'application/json'},
    ).change(context: {'sesion': sesion});
  }

  Future<Map<String, Object?>> cuerpo(Response respuesta) async =>
      jsonDecode(await respuesta.readAsString()) as Map<String, Object?>;

  /// Los cuatro permisos que reparte la migración 017 al rol ADMIN.
  const admin = {
    'unidades.ver',
    'unidades.crear',
    'unidades.editar',
    'unidades.eliminar',
  };

  setUp(() {
    repo = FakeUnidadMedidaRepository.semilla();
    handler = montar();
  });

  group('GET /api/v1/unidades', () {
    test('lista la semilla con su total y paginación', () async {
      final respuesta = await handler(conSesion(permisos: {'unidades.ver'}));

      expect(respuesta.statusCode, 200);
      final json = await cuerpo(respuesta);
      expect(json['total'], 4);
      expect(json['limit'], 50);
      expect(json['offset'], 0);
      final items = json['items']! as List;
      expect(items.first, containsPair('codigo', 'KG'));
      expect(items.first, containsPair('decimales', 3));
    });

    test('q= filtra por código y estado= acota por estado', () async {
      final filtrada = await handler(
        conSesion(permisos: {'unidades.ver'}, ruta: '/api/v1/unidades?q=caja'),
      );
      final jsonFiltro = await cuerpo(filtrada);
      expect(jsonFiltro['total'], 1);
      expect(
        (jsonFiltro['items']! as List).first,
        containsPair('codigo', 'CAJA'),
      );

      final porEstado = await handler(
        conSesion(
          permisos: {'unidades.ver'},
          ruta: '/api/v1/unidades?estado=INVENTADO',
        ),
      );
      expect(porEstado.statusCode, 400);
      expect(await porEstado.readAsString(), contains('estado_invalido'));
    });

    test('sin `unidades.ver` → 403 permiso_denegado', () async {
      final respuesta = await handler(conSesion(permisos: {}));

      expect(respuesta.statusCode, 403);
      expect(await respuesta.readAsString(), contains('permiso_denegado'));
    });
  });

  group('GET /api/v1/unidades/{id}', () {
    test('la ficha llega con su código y sus decimales', () async {
      final respuesta = await handler(
        conSesion(permisos: {'unidades.ver'}, ruta: '/api/v1/unidades/1'),
      );

      expect(respuesta.statusCode, 200);
      expect(await cuerpo(respuesta), containsPair('codigo', 'KG'));
    });

    test('id que no existe → 404 unidad_no_encontrada', () async {
      final respuesta = await handler(
        conSesion(permisos: {'unidades.ver'}, ruta: '/api/v1/unidades/999'),
      );

      expect(respuesta.statusCode, 404);
      expect(await respuesta.readAsString(), contains('unidad_no_encontrada'));
    });

    test('id que no es un número → 400', () async {
      final respuesta = await handler(
        conSesion(permisos: {'unidades.ver'}, ruta: '/api/v1/unidades/abc'),
      );

      expect(respuesta.statusCode, 400);
    });
  });

  group('POST /api/v1/unidades', () {
    test('crea y devuelve 201 con el código normalizado', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'POST',
          cuerpo: {'codigo': ' barril ', 'nombre': 'Barril'},
        ),
      );

      expect(respuesta.statusCode, 201);
      final json = await cuerpo(respuesta);
      // La forma del símbolo la decide el dominio: limpio y en mayúsculas.
      expect(json, containsPair('codigo', 'BARRIL'));
      expect(json, containsPair('nombre', 'Barril'));
      // Lo que no viene en el cuerpo nace con su valor por defecto.
      expect(json, containsPair('tipo', 'UNIDAD'));
      expect(json, containsPair('decimales', 0));
      expect(json, containsPair('estado', 'ACTIVO'));
      expect(repo.unidades.length, 5);
    });

    test('tipo no admitido → 400 tipo_unidad_invalido', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'POST',
          cuerpo: {'codigo': 'OTRA', 'nombre': 'Otra', 'tipo': 'VOLUMENES'},
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('tipo_unidad_invalido'));
    });

    test('decimales fuera de 0..3 → 400 decimales_invalidos', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'POST',
          cuerpo: {'codigo': 'OTRA', 'nombre': 'Otra', 'decimales': 9},
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('decimales_invalidos'));
      expect(repo.unidades.length, 4);
    });

    test('código repetido → 409 (no se cola un duplicado)', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'POST',
          cuerpo: {'codigo': 'KG', 'nombre': 'Otro kilo'},
        ),
      );

      expect(respuesta.statusCode, 409);
      expect(repo.unidades.length, 4);
    });

    test('sin `unidades.crear` → 403 y no escribe nada', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'unidades.ver'},
          metodo: 'POST',
          cuerpo: {'codigo': 'BARRIL', 'nombre': 'Barril'},
        ),
      );

      expect(respuesta.statusCode, 403);
      expect(repo.unidades.length, 4);
    });

    test('sin `codigo` → 400 field_required', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'POST',
          cuerpo: {'nombre': 'Sin código'},
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('field_required'));
    });
  });

  group('PUT /api/v1/unidades/{id}', () {
    test('actualización parcial: solo cambia lo enviado', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'PUT',
          ruta: '/api/v1/unidades/1',
          cuerpo: {'nombre': 'Kilo', 'decimales': 2},
        ),
      );

      expect(respuesta.statusCode, 200);
      final json = await cuerpo(respuesta);
      expect(json, containsPair('nombre', 'Kilo'));
      expect(json, containsPair('decimales', 2));
      // Lo que no vino conserva su valor.
      expect(json, containsPair('codigo', 'KG'));
      expect(json, containsPair('tipo', 'PESO'));
    });

    test('cambiar el código → 400 codigo_inmutable', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'PUT',
          ruta: '/api/v1/unidades/1',
          cuerpo: {'codigo': 'OTRO'},
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('codigo_inmutable'));
      expect(repo.porId(1)!.codigo, 'KG');
    });

    test('cuerpo sin campos → 400 fields_required', () async {
      final respuesta = await handler(
        conSesion(
          permisos: admin,
          metodo: 'PUT',
          ruta: '/api/v1/unidades/1',
          cuerpo: <String, Object?>{},
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('fields_required'));
    });

    test('sin `unidades.editar` → 403', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'unidades.ver'},
          metodo: 'PUT',
          ruta: '/api/v1/unidades/1',
          cuerpo: {'nombre': 'Kilo'},
        ),
      );

      expect(respuesta.statusCode, 403);
      expect(repo.porId(1)!.nombre, 'Kilogramo');
    });
  });

  group('DELETE /api/v1/unidades/{id}', () {
    test('oculta la fila (204) y deja de salir en los listados', () async {
      final borrada = await handler(
        conSesion(
          permisos: admin,
          metodo: 'DELETE',
          ruta: '/api/v1/unidades/1',
        ),
      );
      expect(borrada.statusCode, 204);

      // La fila sigue ahí: los productos que ya usan KG la conservan…
      final ficha = await handler(
        conSesion(permisos: {'unidades.ver'}, ruta: '/api/v1/unidades/1'),
      );
      expect(ficha.statusCode, 200);
      expect(await cuerpo(ficha), containsPair('estado', 'ELIMINADO'));

      // …pero ya no se puede elegir: desaparece del catálogo.
      final lista = await handler(conSesion(permisos: {'unidades.ver'}));
      final json = await cuerpo(lista);
      expect(json['total'], 3);
      expect(
        (json['items']! as List).map((i) => (i as Map)['codigo']),
        isNot(contains('KG')),
      );
    });

    test('sin `unidades.eliminar` → 403', () async {
      final respuesta = await handler(
        conSesion(
          permisos: {'unidades.ver'},
          metodo: 'DELETE',
          ruta: '/api/v1/unidades/1',
        ),
      );

      expect(respuesta.statusCode, 403);
      expect(repo.porId(1)!.estado, 'ACTIVO');
    });

    test('eliminar dos veces → 404', () async {
      await handler(
        conSesion(
          permisos: admin,
          metodo: 'DELETE',
          ruta: '/api/v1/unidades/1',
        ),
      );
      final segunda = await handler(
        conSesion(
          permisos: admin,
          metodo: 'DELETE',
          ruta: '/api/v1/unidades/1',
        ),
      );

      expect(segunda.statusCode, 404);
      expect(await segunda.readAsString(), contains('unidad_no_encontrada'));
    });
  });
}
