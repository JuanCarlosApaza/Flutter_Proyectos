import 'dart:convert';

import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/usecases/marca_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/producto_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/unidad_medida_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/producto_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// `POST /api/v1/products/importar` sobre el repositorio falso: mismos
/// middlewares que en producción y sesión de prueba en el contexto.
///
/// Lo que comprueba aquí es el **contrato de la importación**: permiso igual
/// que el alta, mejor esfuerzo por fila (una fila mala no detiene las demás),
/// que el `fila` de la respuesta es el número real del Excel, que los
/// duplicados se saltan con aviso (idempotencia) y el límite de filas. La
/// validación campo a campo no se repite: la hace `Productos.crear`, la
/// misma del alta normal.
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
      'POST',
      Uri.parse('http://localhost/api/v1/products/importar'),
      body: jsonEncode(cuerpo),
      headers: const {'content-type': 'application/json'},
    ).change(context: {'sesion': sesion});
  }

  Future<Map<String, Object?>> cuerpo(Response respuesta) async =>
      jsonDecode(await respuesta.readAsString()) as Map<String, Object?>;

  const crear = {'productos.ver', 'productos.crear'};

  /// Fila válida tal y como la manda el frontend (relaciones ya resueltas a
  /// IDs, con el `fila` real de la hoja `datos`).
  Map<String, Object?> fila({
    required int numero,
    String nombre = 'Gaseosa Cola 2 L',
    String? codigo,
    double precioVenta = 12.0,
    double precioCompra = 8.0,
    int categoriaId = 1,
    int presentacionId = 1,
    int? marcaId = 1,
  }) => {
    'fila': numero,
    'nombre': nombre,
    'codigo': codigo,
    'precioVenta': precioVenta,
    'precioCompra': precioCompra,
    'stock': 5,
    'unidad': 'KG',
    'estado': 'DISPONIBLE',
    'categoriaId': categoriaId,
    'presentacionId': presentacionId,
    'marcaId': marcaId,
  };

  Future<Map<String, Object?>> importar(List<Map<String, Object?>> filas) async {
    final respuesta = await handler(
      conSesion(permisos: crear, cuerpo: {'archivo': 'productos.xlsx', 'filas': filas}),
    );
    expect(respuesta.statusCode, 200);
    return cuerpo(respuesta);
  }

  setUp(() {
    repo = FakeProductoRepository();
    handler = montar();
  });

  test('sin `productos.crear` → 403 permiso_denegado', () async {
    final respuesta = await handler(
      conSesion(
        permisos: const {'productos.ver'},
        cuerpo: {'filas': [fila(numero: 2)]},
      ),
    );

    expect(respuesta.statusCode, 403);
    expect(await respuesta.readAsString(), contains('permiso_denegado'));
  });

  test('crea todas las filas válidas y responde 200 con el recuento', () async {
    final json = await importar([
      fila(numero: 2, nombre: 'Gaseosa Cola 2 L', codigo: 'BEB-002'),
      fila(numero: 3, nombre: 'Papas Fritas 150 g', codigo: 'SNK-001'),
    ]);

    expect(json['creados'], 2);
    expect(json['omitidos'], isEmpty);
    expect(json['errores'], isEmpty);
    expect(repo.productos, hasLength(2));
    expect(repo.productos.map((p) => p.nombre), contains('Gaseosa Cola 2 L'));
  });

  test('una fila inválida no detiene las demás (mejor esfuerzo)', () async {
    final json = await importar([
      fila(numero: 2, nombre: 'Pan Integral'),
      // Precio de venta por debajo del coste → la rechaza `crear`.
      fila(
        numero: 4,
        nombre: 'Lejía 1 L',
        precioVenta: 1,
        precioCompra: 5,
      ),
      fila(numero: 5, nombre: 'Tomate'),
    ]);

    expect(json['creados'], 2);
    final errores = json['errores']! as List;
    expect(errores, hasLength(1));
    // El `fila` es el número REAL de la hoja, para encontrarlo en el Excel.
    expect((errores.first as Map)['fila'], 4);
    expect(
      (errores.first as Map)['mensaje'].toString(),
      contains('precio de venta'),
    );
    expect((errores.first as Map)['codigo'], 'precio_venta_bajo_costo');
    expect(repo.productos, hasLength(2));
  });

  test('duplicado por código ya en la BD → se omite con aviso', () async {
    repo = FakeProductoRepository(
      productos: [
        Product(
          id: 1,
          nombre: 'Gaseosa Cola 2 L',
          codigo: 'BEB-002',
          unidad: 'LT',
          precioVenta: 12,
          stock: 3,
          categoriaId: 1,
          presentacionId: 1,
          estado: 'DISPONIBLE',
          version: 1,
        ),
      ],
    );
    handler = montar();

    final json = await importar([
      fila(numero: 2, nombre: 'Gaseosa Cola 2 L', codigo: 'BEB-002'),
      fila(numero: 3, nombre: 'Manzana Roja', codigo: 'FRU-001'),
    ]);

    expect(json['creados'], 1);
    final omitidos = json['omitidos']! as List;
    expect(omitidos, hasLength(1));
    expect((omitidos.first as Map)['fila'], 2);
    // Solo se creó la nueva: re-subir el archivo no duplica nada.
    expect(repo.productos, hasLength(2));
  });

  test('repetida dentro del propio archivo → la segunda se omite', () async {
    final json = await importar([
      fila(numero: 2, nombre: 'Croissant'),
      fila(numero: 3, nombre: 'croissant'),
    ]);

    expect(json['creados'], 1);
    final omitidos = json['omitidos']! as List;
    expect(omitidos, hasLength(1));
    expect((omitidos.first as Map)['fila'], 3);
    expect(repo.productos, hasLength(1));
  });

  test('sin catálogo obligatorio → 400 en esa fila, no en toda la tanda',
      () async {
    final json = await importar([
      fila(numero: 2, nombre: 'Pan Integral', marcaId: 1),
      fila(numero: 3, nombre: 'Croissant', marcaId: null),
    ]);

    expect(json['creados'], 1);
    final errores = json['errores']! as List;
    expect(errores, hasLength(1));
    expect((errores.first as Map)['fila'], 3);
    expect((errores.first as Map)['codigo'], 'marca_requerida');
  });

  test('más de 1000 filas → 400 importar_demasiadas_filas', () async {
    final filas = <Map<String, Object?>>[
      for (var i = 0; i <= maximoFilasImportar; i++) fila(numero: i + 2),
    ];
    final respuesta = await handler(
      conSesion(permisos: crear, cuerpo: {'filas': filas}),
    );

    expect(respuesta.statusCode, 400);
    expect(await respuesta.readAsString(), contains('importar_demasiadas_filas'));
    expect(repo.productos, isEmpty);
  });

  test('cuerpo sin `filas` → 400 filas_invalidas', () async {
    final respuesta = await handler(
      conSesion(permisos: crear, cuerpo: {'filas': <Map<String, Object?>>[]}),
    );

    expect(respuesta.statusCode, 400);
    expect(await respuesta.readAsString(), contains('filas_invalidas'));
  });
}
