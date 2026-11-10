import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/entities/product.dart';
import '../../domain/usecases/producto_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de productos:
///
/// * `GET/POST    /api/v1/products` (alias en español: `/api/v1/productos`)
/// * `GET/PUT/DEL /api/v1/products/{id}`
///
/// `PUT` es una actualización parcial: solo se modifican los campos enviados
/// y, dentro de ellos, `null` borra el valor.
///
/// Cada operación exige el permiso de su módulo (`productos.ver`, `.crear`,
/// `.editar`, `.eliminar`) en el rol de la sesión.
void addProductoRoutes(Router router, {required Productos productos}) {
  Future<Response> list(Request request) async {
    asegurarPermiso(request, 'productos', 'ver');
    final page = paginationOf(request);
    final q = queryOrNull(request, 'q', maxLength: 100);
    final estado = queryOrNull(request, 'estado');
    final total = await productos.contar(estado: estado, q: q);
    final items = await productos.listar(
      limit: page.limit,
      offset: page.offset,
      estado: estado,
      q: q,
    );
    return listJsonResponse(
      items.map((e) => e.toJson()).toList(),
      total: total,
      limit: page.limit,
      offset: page.offset,
    );
  }

  Future<Response> get(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'ver');
    final item = await productos.obtener(pathId(id));
    return jsonResponse(200, item.toJson());
  }

  Future<Response> create(Request request) async {
    asegurarPermiso(request, 'productos', 'crear');
    final body = await readJsonObject(request);
    detalleRegistro(request, nombre: body['nombre']?.toString());
    final item = await productos.crear(
      nombre: requireText(body, 'nombre', maxLength: 150),
      precioVenta: requireDouble(body, 'precioVenta'),
      imagen: textOrNull(body, 'imagen', maxLength: 500),
      precioCompra: doubleOrNull(body, 'precioCompra'),
      precioRebaja: doubleOrNull(body, 'precioRebaja'),
      fechaVencimiento: dateOrNull(body, 'fechaVencimiento'),
      stock: intOrNull(body, 'stock') ?? 0,
      categoriaId: intOrNull(body, 'categoriaId'),
      proveedorId: intOrNull(body, 'proveedorId'),
      presentacionId: intOrNull(body, 'presentacionId'),
      estado: textOrNull(body, 'estado') ?? 'DISPONIBLE',
    );
    return jsonResponse(201, item.toJson());
  }

  Future<Response> update(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'editar');
    final body = await readJsonObject(request);
    final campos = camposEnviados(body, const [
      'nombre',
      'imagen',
      'precioVenta',
      'precioCompra',
      'precioRebaja',
      'fechaVencimiento',
      'stock',
      'categoriaId',
      'proveedorId',
      'presentacionId',
      'estado',
    ]);
    ensureHayCampos(campos);
    // Estado ANTES: el evento de auditoría lleva el nombre del producto y
    // el diff de los campos que cambian (precio, stock, estado...).
    final antes = await productos.obtener(pathId(id));
    detalleRegistro(
      request,
      nombre: antes.nombre,
      antes: antes.toJson(),
      despues: body,
      campos: campos,
    );
    final item = await productos.actualizar(
      pathId(id),
      _productoDesdeBody(body),
      campos,
      // Guarda optimista: el cliente devuelve la `version` que leyó; si
      // alguien más editó el producto, el repo responde 409 y no se pisa.
      versionEsperado: intOrNull(body, 'versionLeida'),
    );
    return jsonResponse(200, item.toJson());
  }

  Future<Response> remove(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'eliminar');
    // El evento deja el nombre: "quién ocultó el producto X y cuándo".
    final antes = await productos.obtener(pathId(id));
    detalleRegistro(request, nombre: antes.nombre);
    await productos.eliminar(pathId(id));
    return noContent();
  }

  router
    // Inglés (contract original usado por el frontend)
    ..get('/api/v1/products', list)
    ..get('/api/v1/products/<id>', get)
    ..post('/api/v1/products', create)
    ..put('/api/v1/products/<id>', update)
    ..delete('/api/v1/products/<id>', remove)
    // Alias en español, igual que el resto de recursos
    ..get('/api/v1/productos', list)
    ..get('/api/v1/productos/<id>', get)
    ..post('/api/v1/productos', create)
    ..put('/api/v1/productos/<id>', update)
    ..delete('/api/v1/productos/<id>', remove);
}

Product _productoDesdeBody(Map<String, Object?> body) => Product(
  id: 0,
  nombre: body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: 150)
      : '',
  imagen: textOrNull(body, 'imagen', maxLength: 500),
  precioVenta: body.containsKey('precioVenta')
      ? doubleOrNull(body, 'precioVenta') ?? 0
      : 0,
  precioCompra: doubleOrNull(body, 'precioCompra'),
  precioRebaja: doubleOrNull(body, 'precioRebaja'),
  fechaVencimiento: dateOrNull(body, 'fechaVencimiento'),
  stock: intOrNull(body, 'stock') ?? 0,
  categoriaId: intOrNull(body, 'categoriaId'),
  proveedorId: intOrNull(body, 'proveedorId'),
  presentacionId: intOrNull(body, 'presentacionId'),
  estado: textOrNull(body, 'estado') ?? '',
);
