import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/rules/validaciones.dart';
import '../../domain/usecases/producto_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Máximo de filas que acepta un solo archivo de importación masiva.
const int maximoFilasImportar = 1000;

/// Rutas de productos:
///
/// * `GET/POST    /api/v1/products` (alias en español: `/api/v1/productos`)
/// * `GET/PUT/DEL /api/v1/products/{id}`
/// * `POST        /api/v1/products/importar` (importación masiva de Excel)
///
/// `PUT` es una actualización parcial: solo se modifican los campos enviados
/// y, dentro de ellos, `null` borra el valor — excepto los catálogos
/// obligatorios (categoría, presentación y marca), que no se aceptan en
/// `null`. El alta exige además `nombre`, `precioVenta` y esos tres
/// catálogos.
///
/// Cada operación exige el permiso de su módulo (`productos.ver`, `.crear`,
/// `.editar`, `.eliminar`) en el rol de la sesión.
void addProductoRoutes(Router router, {required Productos productos}) {
  Future<Response> list(Request request) async {
    asegurarPermiso(request, 'productos', 'ver');
    final page = paginationOf(request);
    final q = queryOrNull(request, 'q', maxLength: 100);
    final estado = queryOrNull(request, 'estado');
    // Filtro del desplegable «Marca» de la tabla: no numérico → sin filtro.
    final marcaId = int.tryParse(queryOrNull(request, 'marcaId') ?? '');
    final total = await productos.contar(
      estado: estado,
      q: q,
      marcaId: marcaId,
    );
    final items = await productos.listar(
      limit: page.limit,
      offset: page.offset,
      estado: estado,
      q: q,
      marcaId: marcaId,
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
      codigo: textOrNull(body, 'codigo', maxLength: 60),
      imagen: textOrNull(body, 'imagen', maxLength: 500),
      descripcion: textOrNull(
        body,
        'descripcion',
        maxLength: descripcionMaxima,
      ),
      unidad: textOrNull(body, 'unidad', maxLength: 10),
      precioCompra: doubleOrNull(body, 'precioCompra'),
      precioRebaja: doubleOrNull(body, 'precioRebaja'),
      fechaVencimiento: dateOrNull(body, 'fechaVencimiento'),
      stock: doubleOrNull(body, 'stock') ?? 0,
      stockMinimo: doubleOrNull(body, 'stockMinimo'),
      categoriaId: _idCatalogoRequerido(body, 'categoriaId'),
      proveedorId: intOrNull(body, 'proveedorId'),
      presentacionId: _idCatalogoRequerido(body, 'presentacionId'),
      marcaId: _idCatalogoRequerido(body, 'marcaId'),
      garantiaMeses: intOrNull(body, 'garantiaMeses'),
      estado: textOrNull(body, 'estado') ?? 'DISPONIBLE',
      variantes: variantesDesdeBody(body) ?? const [],
    );
    return jsonResponse(201, item.toJson());
  }

  Future<Response> update(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'editar');
    final body = await readJsonObject(request);
    final campos = camposEnviados(body, const [
      'nombre',
      'codigo',
      'imagen',
      'descripcion',
      'unidad',
      'precioVenta',
      'precioCompra',
      'precioRebaja',
      'fechaVencimiento',
      'stock',
      'stockMinimo',
      'categoriaId',
      'proveedorId',
      'presentacionId',
      'marcaId',
      'garantiaMeses',
      'estado',
      'variantes',
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
      // `null` = el cuerpo no trae "variantes" (no se tocan); lista =
      // se reescriben (vacía → vuelve a ser «Único»).
      variantes: variantesDesdeBody(body),
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

  /// Importación masiva desde Excel: el frontend lee el .xlsx en el
  /// navegador, valida cada fila **con las mismas reglas del formulario** y
  /// manda aquí las filas válidas con las relaciones ya resueltas a IDs.
  ///
  /// * **Mejor esfuerzo por fila**: una fila que falle no detiene las demás.
  /// * Se reutiliza `Productos.crear` tal cual → misma validación que el
  ///   alta normal (nada de lógica paralela).
  /// * `fila` es el **número real de fila del Excel** (la 1 es la de
  ///   encabezados) para que el usuario lo encuentre en su archivo.
  /// * **Duplicados → se saltan con aviso** (mismo código, o mismo nombre +
  ///   categoría + presentación): re-subir el archivo completo no duplica.
  Future<Response> importar(Request request) async {
    asegurarPermiso(request, 'productos', 'crear');
    final body = await readJsonObject(request);
    detalleRegistro(
      request,
      nombre: body['archivo']?.toString() ?? 'Importación Excel',
    );
    final filas = body['filas'];
    if (filas is! List || filas.isEmpty) {
      throw const BadRequestException(
        'El cuerpo debe traer "filas" con al menos una fila.',
        code: 'filas_invalidas',
      );
    }
    if (filas.length > maximoFilasImportar) {
      throw BadRequestException(
        'Un archivo puede traer como máximo $maximoFilasImportar filas '
        '(recibidas: ${filas.length}).',
        code: 'importar_demasiadas_filas',
      );
    }

    var creados = 0;
    final omitidos = <Map<String, Object?>>[];
    final errores = <Map<String, Object?>>[];

    for (final cruda in filas) {
      if (cruda is! Map) {
        errores.add({'fila': 0, 'mensaje': 'Fila ilegible.'});
        continue;
      }
      final fila = Map<String, Object?>.from(cruda);
      final numero = fila['fila'] is num ? (fila['fila'] as num).toInt() : 0;
      try {
        // Duplicado en la BD (o repetido dentro del propio archivo: la
        // primera fila ya lo habrá creado y esta la encontrará).
        final yaExiste = await productos.existe(
          codigo: textOrNull(fila, 'codigo', maxLength: 60),
          nombre: textOrNull(fila, 'nombre', maxLength: 150),
          categoriaId: intOrNull(fila, 'categoriaId'),
          presentacionId: intOrNull(fila, 'presentacionId'),
        );
        if (yaExiste) {
          omitidos.add({
            'fila': numero,
            'mensaje': 'Ya existe un producto igual (se omite).',
          });
          continue;
        }
        // Mismos parseos y la misma lógica que `create`.
        await productos.crear(
          nombre: requireText(fila, 'nombre', maxLength: 150),
          precioVenta: requireDouble(fila, 'precioVenta'),
          codigo: textOrNull(fila, 'codigo', maxLength: 60),
          imagen: textOrNull(fila, 'imagen', maxLength: 500),
          descripcion: textOrNull(
            fila,
            'descripcion',
            maxLength: descripcionMaxima,
          ),
          unidad: textOrNull(fila, 'unidad', maxLength: 10),
          precioCompra: doubleOrNull(fila, 'precioCompra'),
          precioRebaja: doubleOrNull(fila, 'precioRebaja'),
          fechaVencimiento: dateOrNull(fila, 'fechaVencimiento'),
          stock: doubleOrNull(fila, 'stock') ?? 0,
          stockMinimo: doubleOrNull(fila, 'stockMinimo'),
          categoriaId: _idCatalogoRequerido(fila, 'categoriaId'),
          proveedorId: intOrNull(fila, 'proveedorId'),
          presentacionId: _idCatalogoRequerido(fila, 'presentacionId'),
          marcaId: _idCatalogoRequerido(fila, 'marcaId'),
          garantiaMeses: intOrNull(fila, 'garantiaMeses'),
          estado: textOrNull(fila, 'estado') ?? 'DISPONIBLE',
          variantes: variantesDesdeBody(fila) ?? const [],
        );
        creados++;
      } on AppException catch (e) {
        errores.add({
          'fila': numero,
          'mensaje': e.message,
          if (e.code != null) 'codigo': e.code,
        });
      } on Exception {
        errores.add({'fila': numero, 'mensaje': 'No se pudo guardar la fila.'});
      }
    }

    return jsonResponse(200, {
      'creados': creados,
      'omitidos': omitidos,
      'errores': errores,
    });
  }

  router
    // Inglés (contract original usado por el frontend)
    ..get('/api/v1/products', list)
    ..get('/api/v1/products/<id>', get)
    ..post('/api/v1/products', create)
    ..put('/api/v1/products/<id>', update)
    ..delete('/api/v1/products/<id>', remove)
    ..post('/api/v1/products/importar', importar)
    // Alias en español, igual que el resto de recursos
    ..get('/api/v1/productos', list)
    ..get('/api/v1/productos/<id>', get)
    ..post('/api/v1/productos', create)
    ..put('/api/v1/productos/<id>', update)
    ..delete('/api/v1/productos/<id>', remove)
    ..post('/api/v1/productos/importar', importar);
}

Product _productoDesdeBody(Map<String, Object?> body) => Product(
  id: 0,
  nombre: body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: 150)
      : '',
  codigo: textOrNull(body, 'codigo', maxLength: 60),
  imagen: textOrNull(body, 'imagen', maxLength: 500),
  descripcion: textOrNull(body, 'descripcion', maxLength: descripcionMaxima),
  unidad: textOrNull(body, 'unidad', maxLength: 10) ?? 'UN',
  precioVenta: body.containsKey('precioVenta')
      ? doubleOrNull(body, 'precioVenta') ?? 0
      : 0,
  precioCompra: doubleOrNull(body, 'precioCompra'),
  precioRebaja: doubleOrNull(body, 'precioRebaja'),
  fechaVencimiento: dateOrNull(body, 'fechaVencimiento'),
  stock: doubleOrNull(body, 'stock') ?? 0,
  stockMinimo: doubleOrNull(body, 'stockMinimo'),
  // Categoría, presentación y marca: obligatorias. Si la clave viene
  // (aunque sea en `null`) no puede faltar; si no viene, la edición
  // parcial no la toca.
  categoriaId: body.containsKey('categoriaId')
      ? _idCatalogoRequerido(body, 'categoriaId')
      : null,
  proveedorId: intOrNull(body, 'proveedorId'),
  presentacionId: body.containsKey('presentacionId')
      ? _idCatalogoRequerido(body, 'presentacionId')
      : null,
  marcaId: body.containsKey('marcaId')
      ? _idCatalogoRequerido(body, 'marcaId')
      : null,
  garantiaMeses: intOrNull(body, 'garantiaMeses'),
  estado: textOrNull(body, 'estado') ?? '',
);

/// Los tres catálogos obligatorios del producto: qué código de error
/// lleva cada id y de qué catálogo hablamos.
const _catalogosProducto = <String, ({String codigo, String catalogo})>{
  'categoriaId': (codigo: 'categoria_requerida', catalogo: 'una categoría'),
  'presentacionId': (
    codigo: 'presentacion_requerida',
    catalogo: 'una presentación',
  ),
  'marcaId': (codigo: 'marca_requerida', catalogo: 'una marca'),
};

/// `400` si el cuerpo no trae el id de catálogo obligatorio [campo]
/// (faltante o en `null`). El producto siempre lleva categoría,
/// presentación y marca: la regla la impone el formulario y aquí se
/// sostiene el contrato de la API.
int _idCatalogoRequerido(Map<String, Object?> body, String campo) {
  final id = intOrNull(body, campo);
  if (id == null) {
    final meta = _catalogosProducto[campo]!;
    throw BadRequestException(
      'El campo "$campo" es obligatorio (id de ${meta.catalogo} existente).',
      code: meta.codigo,
    );
  }
  return id;
}
