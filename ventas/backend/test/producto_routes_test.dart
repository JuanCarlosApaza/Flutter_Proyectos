import 'dart:convert';

import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/rules/validaciones.dart';
import 'package:ventas_backend/src/domain/usecases/marca_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/producto_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/unidad_medida_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/producto_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// HTTP de `/api/v1/products` sobre el repositorio falso: mismos middlewares
/// que en producción (`errorHandler` traduce las excepciones de dominio a JSON
/// con su código) y sesión de prueba en el contexto del request.
///
/// Las reglas puras viven en `validaciones_test.dart`; aquí se comprueba que
/// las rutas no las tuercen: el foco va en `descripcion` (migración
/// 018_producto_descripcion) —que viaje en el alta, que la edición parcial no
/// la pise y que un `null` la borre— y en los catálogos obligatorios del
/// producto (categoría, presentación y marca).
void main() {
  late FakeProductoRepository repo;
  late Handler handler;

  Handler montar() {
    final router = Router();
    addProductoRoutes(
      router,
      productos: Productos(
        repository: repo,
        unidades: Unidades(repository: FakeUnidadMedidaRepository.semilla()),
        marcas: Marcas(repository: FakeMarcaRepository.semilla()),
      ),
    );
    return errorHandler()(router.call);
  }

  Request conSesion({
    Set<String> permisos = const {},
    String metodo = 'GET',
    String ruta = '/api/v1/products',
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

  const ver = {'productos.ver'};
  const crear = {'productos.ver', 'productos.crear'};
  const editar = {'productos.ver', 'productos.editar'};

  /// Alta mínima válida (unidad del catálogo de la semilla y los tres
  /// catálogos obligatorios —la marca 1 existe en la semilla—). La clave
  /// `descripcion` solo aparece si se pasa: el alta sin la clave es
  /// distinta de `descripcion: null`.
  Map<String, Object?> alta({String? descripcion}) {
    final cuerpo = <String, Object?>{
      'nombre': 'Ibuprofeno 600 mg',
      'precioVenta': 2.5,
      'unidad': 'KG',
      'categoriaId': 1,
      'presentacionId': 1,
      'marcaId': 1,
    };
    if (descripcion != null) cuerpo['descripcion'] = descripcion;
    return cuerpo;
  }

  setUp(() {
    repo = FakeProductoRepository();
    handler = montar();
  });

  group('POST /api/v1/products (descripcion)', () {
    test('la guarda recortada en la ficha', () async {
      final respuesta = await handler(
        conSesion(
          permisos: crear,
          metodo: 'POST',
          cuerpo: alta(descripcion: '  Jarabe para la tos  '),
        ),
      );

      expect(respuesta.statusCode, 201);
      expect(
        await cuerpo(respuesta),
        containsPair('descripcion', 'Jarabe para la tos'),
      );
    });

    test('sin descripción la deja en null', () async {
      final respuesta = await handler(
        conSesion(permisos: crear, metodo: 'POST', cuerpo: alta()),
      );

      expect(respuesta.statusCode, 201);
      expect(await cuerpo(respuesta), containsPair('descripcion', null));
    });

    test('256 caracteres → 400 field_too_long', () async {
      final respuesta = await handler(
        conSesion(
          permisos: crear,
          metodo: 'POST',
          cuerpo: alta(descripcion: 'x' * (descripcionMaxima + 1)),
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('field_too_long'));
    });

    test('sin `productos.crear` → 403 permiso_denegado', () async {
      final respuesta = await handler(
        conSesion(permisos: ver, metodo: 'POST', cuerpo: alta()),
      );

      expect(respuesta.statusCode, 403);
      expect(await respuesta.readAsString(), contains('permiso_denegado'));
    });
  });

  group('POST /api/v1/products (catálogos obligatorios)', () {
    const casos = {
      'categoriaId': 'categoria_requerida',
      'presentacionId': 'presentacion_requerida',
      'marcaId': 'marca_requerida',
    };

    test('sin uno de los tres → 400 con su código', () async {
      for (final caso in casos.entries) {
        final cuerpo = alta()..remove(caso.key);
        final respuesta = await handler(
          conSesion(permisos: crear, metodo: 'POST', cuerpo: cuerpo),
        );

        expect(respuesta.statusCode, 400, reason: 'falta ${caso.key}');
        expect(await respuesta.readAsString(), contains(caso.value));
      }
    });

    test('con la clave en null también → 400', () async {
      for (final caso in casos.entries) {
        final cuerpo = alta()..[caso.key] = null;
        final respuesta = await handler(
          conSesion(permisos: crear, metodo: 'POST', cuerpo: cuerpo),
        );

        expect(respuesta.statusCode, 400, reason: '${caso.key} en null');
        expect(await respuesta.readAsString(), contains(caso.value));
      }
    });

    test('un id que no es entero → 400 field_invalid', () async {
      final respuesta = await handler(
        conSesion(
          permisos: crear,
          metodo: 'POST',
          cuerpo: alta()..['marcaId'] = 'x',
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('field_invalid'));
    });
  });

  group('PUT /api/v1/products/{id} (descripcion)', () {
    late int id;

    setUp(() async {
      final creada = await handler(
        conSesion(
          permisos: crear,
          metodo: 'POST',
          cuerpo: alta(descripcion: 'Jarabe'),
        ),
      );
      id = (await cuerpo(creada))['id']! as int;
    });

    test('la edición parcial no pisa lo que no se envía', () async {
      final respuesta = await handler(
        conSesion(
          permisos: editar,
          metodo: 'PUT',
          ruta: '/api/v1/products/$id',
          cuerpo: {'precioVenta': 3.0},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(await cuerpo(respuesta), containsPair('descripcion', 'Jarabe'));
    });

    test('un valor nuevo la reemplaza', () async {
      final respuesta = await handler(
        conSesion(
          permisos: editar,
          metodo: 'PUT',
          ruta: '/api/v1/products/$id',
          cuerpo: {'descripcion': 'De venta suelta'},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(
        await cuerpo(respuesta),
        containsPair('descripcion', 'De venta suelta'),
      );
    });

    test('null la borra (queda sin descripción)', () async {
      final respuesta = await handler(
        conSesion(
          permisos: editar,
          metodo: 'PUT',
          ruta: '/api/v1/products/$id',
          cuerpo: {'descripcion': null},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(await cuerpo(respuesta), containsPair('descripcion', null));
    });

    test('vacío también la borra', () async {
      final respuesta = await handler(
        conSesion(
          permisos: editar,
          metodo: 'PUT',
          ruta: '/api/v1/products/$id',
          cuerpo: {'descripcion': '   '},
        ),
      );

      expect(respuesta.statusCode, 200);
      expect(await cuerpo(respuesta), containsPair('descripcion', null));
    });

    test('256 caracteres → 400 field_too_long', () async {
      final respuesta = await handler(
        conSesion(
          permisos: editar,
          metodo: 'PUT',
          ruta: '/api/v1/products/$id',
          cuerpo: {'descripcion': 'x' * (descripcionMaxima + 1)},
        ),
      );

      expect(respuesta.statusCode, 400);
      expect(await respuesta.readAsString(), contains('field_too_long'));
    });

    test('un catálogo obligatorio no se borra con null', () async {
      const casos = {
        'categoriaId': 'categoria_requerida',
        'presentacionId': 'presentacion_requerida',
        'marcaId': 'marca_requerida',
      };
      for (final caso in casos.entries) {
        final respuesta = await handler(
          conSesion(
            permisos: editar,
            metodo: 'PUT',
            ruta: '/api/v1/products/$id',
            cuerpo: {caso.key: null},
          ),
        );

        expect(respuesta.statusCode, 400, reason: '${caso.key} en null');
        expect(await respuesta.readAsString(), contains(caso.value));
      }
    });

    test('sí acepta ids de catálogo en la edición', () async {
      final respuesta = await handler(
        conSesion(
          permisos: editar,
          metodo: 'PUT',
          ruta: '/api/v1/products/$id',
          cuerpo: {'categoriaId': 7, 'presentacionId': 4, 'marcaId': 1},
        ),
      );

      expect(respuesta.statusCode, 200);
      final json = await cuerpo(respuesta);
      expect(json, containsPair('categoriaId', 7));
      expect(json, containsPair('presentacionId', 4));
      expect(json, containsPair('marcaId', 1));
    });
  });
}
