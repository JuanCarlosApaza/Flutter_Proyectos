import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/usecases/producto_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/producto_routes.dart';

import 'fakes.dart';

/// Carga masiva de productos (`POST /api/v1/productos/importar`).
///
/// El frontend envía las filas del Excel ya parseadas, con la misma forma
/// que un alta normal; aquí se comprueba el trato **por fila**: las buenas
/// se crean, las fallidas se anotan con su fila y su motivo, y los nombres
/// repetidos (en la BD o dentro del propio envío) se omiten con aviso.
void main() {
  const permisos = {'productos.ver', 'productos.crear'};

  late FakeProductoRepository repositorio;
  late Handler handler;

  /// Fila de importación con los valores por defecto de las pruebas.
  Map<String, Object?> producto({
    required int fila,
    required String nombre,
    double precioCompra = 59.9,
    double precioVenta = 89.9,
    List<Map<String, Object?>>? variantes,
    double? stock,
    String? estado,
  }) => {
    'fila': fila,
    'nombre': nombre,
    'precioCompra': precioCompra,
    'precioVenta': precioVenta,
    'variantes': ?variantes,
    'stock': ?stock,
    'estado': ?estado,
  };

  /// POST a `/api/v1/productos/importar` con sesión de prueba.
  Future<Response> importar(
    Object cuerpo, {
    Set<String>? permisosSesion,
  }) async {
    final usuario = usuarioDePrueba(permisos: permisosSesion ?? permisos);
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    final peticion = Request(
      'POST',
      Uri.parse('http://localhost/api/v1/productos/importar'),
      body: jsonEncode(cuerpo),
    ).change(context: {'sesion': sesion});
    return handler(peticion);
  }

  setUp(() {
    repositorio = FakeProductoRepository();
    final router = Router();
    addProductoRoutes(router, productos: Productos(repository: repositorio));
    handler = errorHandler()(router.call);
  });

  group('POST /api/v1/productos/importar', () {
    test('crea las válidas y devuelve errores con su fila real', () async {
      final respuesta = await importar({
        'productos': [
          producto(
            fila: 2,
            nombre: 'Pantalón mezclillo',
            variantes: [
              {'talla': 'S', 'color': 'Negro', 'stock': 5},
              {'talla': '39-41', 'color': 'Blanco', 'stock': 4},
            ],
          ),
          producto(
            fila: 3,
            nombre: 'Medias clásicas',
            variantes: [],
            stock: 24,
          ),
          // Venta por debajo de compra: única fila mala, y su fila es la 12.
          producto(
            fila: 12,
            nombre: 'Barato raro',
            precioCompra: 50,
            precioVenta: 30,
          ),
        ],
      });

      expect(respuesta.statusCode, 200);
      final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;
      expect(cuerpo['creados'], 2);
      expect(cuerpo['errores'], hasLength(1));
      expect(cuerpo['errores'][0]['fila'], 12);
      expect(cuerpo['errores'][0]['mensaje'], contains('no puede ser menor'));
      expect(cuerpo['omitidos'], isEmpty);

      // Las dos buenas entraron; la mala, no.
      expect(
        repositorio.productos.map((p) => p.nombre),
        containsAll(['Pantalón mezclillo', 'Medias clásicas']),
      );
      expect(
        repositorio.productos.map((p) => p.nombre),
        isNot(contains('Barato raro')),
      );
    });

    test(
      'las variantes con rango se crean y la sin tallas queda «Única»',
      () async {
        final respuesta = await importar({
          'productos': [
            producto(
              fila: 2,
              nombre: 'Pantalón mezclillo',
              variantes: [
                {'talla': 'S', 'color': 'Negro', 'stock': 5},
                {'talla': '40/41', 'color': 'Blanco', 'stock': 4},
              ],
            ),
            producto(
              fila: 3,
              nombre: 'Medias clásicas',
              variantes: [],
              stock: 24,
            ),
          ],
        });

        expect(respuesta.statusCode, 200);
        final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;
        expect(cuerpo['creados'], 2);

        final pantalon = repositorio.productos.firstWhere(
          (p) => p.nombre == 'Pantalón mezclillo',
        );
        expect(pantalon.variantes, hasLength(2));
        expect(
          pantalon.variantes.map((v) => v.nombreTalla),
          containsAll(['S', '40/41']),
        );
        expect(pantalon.stock, 9);

        final medias = repositorio.productos.firstWhere(
          (p) => p.nombre == 'Medias clásicas',
        );
        expect(medias.variantes.single.nombreTalla, 'Única');
        expect(medias.variantes.single.stock, 24);
      },
    );

    test(
      'omite nombres repetidos: en la BD (con acentos) y en el envío',
      () async {
        final primera = await importar({
          'productos': [producto(fila: 2, nombre: 'Pantalón mezclillo')],
        });
        expect((jsonDecode(await primera.readAsString()) as Map)['creados'], 1);

        // Misma prenda con distinto acento/mayúsculas + duplicado interno.
        final segunda = await importar({
          'productos': [
            producto(fila: 2, nombre: 'Pantalón mezclillo'),
            producto(fila: 3, nombre: 'pantalon mezclillo'),
            producto(fila: 4, nombre: 'Gorra Lana'),
            producto(fila: 5, nombre: 'gorra lana'),
          ],
        });

        expect(segunda.statusCode, 200);
        final cuerpo = jsonDecode(await segunda.readAsString()) as Map;
        expect(cuerpo['creados'], 1); // solo la gorra buena
        expect(cuerpo['omitidos'], hasLength(3));
        expect(
          (cuerpo['omitidos'] as List)
              .map((o) => (o as Map)['motivo'])
              .every((m) => '$m'.contains('Ya existe')),
          isTrue,
        );
        // Re-subir no duplica inventario.
        expect(repositorio.productos, hasLength(2));
      },
    );

    test(
      'sin campo «fila», el error informa la posición de la lista',
      () async {
        final respuesta = await importar({
          'productos': [
            {'nombre': 'Buena', 'precioCompra': 10.0, 'precioVenta': 20.0},
            {'nombre': 'Mala', 'precioCompra': 10.0, 'precioVenta': 5.0},
          ],
        });

        expect(respuesta.statusCode, 200);
        final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;
        expect(cuerpo['creados'], 1);
        expect(cuerpo['errores'], hasLength(1));
        expect(cuerpo['errores'][0]['fila'], 2); // posición, no número de Excel
      },
    );

    test('lista vacía y más de 1000 productos → 400', () async {
      final vacia = await importar({'productos': <Object?>[]});
      expect(vacia.statusCode, 400);
      expect(
        (jsonDecode(await vacia.readAsString()) as Map)['error']['code'],
        'productos_invalidos',
      );

      final muchisimos = await importar({
        'productos': [
          for (var i = 0; i < 1001; i++)
            producto(fila: i + 2, nombre: 'Producto $i'),
        ],
      });
      expect(muchisimos.statusCode, 400);
      expect(
        (jsonDecode(await muchisimos.readAsString()) as Map)['error']['code'],
        'productos_limite',
      );
      expect(repositorio.productos, isEmpty);
    });

    test('sin productos.crear → 403 permiso_denegado', () async {
      final respuesta = await importar(
        {
          'productos': [producto(fila: 2, nombre: 'Pantalón mezclillo')],
        },
        permisosSesion: const {'productos.ver'},
      );

      expect(respuesta.statusCode, 403);
      final cuerpo = jsonDecode(await respuesta.readAsString()) as Map;
      expect(cuerpo['error']['code'], 'permiso_denegado');
      expect(repositorio.productos, isEmpty);
    });
  });
}
