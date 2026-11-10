import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/variante.dart';
import '../../domain/usecases/producto_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de productos y sus variantes (talla + color):
///
/// * `GET/POST    /api/v1/products` (alias en español: `/api/v1/productos`)
/// * `GET/PUT/DEL /api/v1/products/{id}`
/// * `GET/POST   /api/v1/productos/{id}/variantes`
/// * `PUT/DEL    /api/v1/variantes/{id}`
///
/// `PUT` es una actualización parcial: solo se modifican los campos enviados
/// y, dentro de ellos, `null` borra el valor. El `stock` del producto no se
/// edita: es el agregado de sus variantes.
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
    final item = await _crearDesdeBody(productos, body);
    return jsonResponse(201, item.toJson());
  }

  /// Carga masiva desde Excel (`POST /api/v1/productos/importar`).
  ///
  /// El frontend parsea el `.xlsx` y envía las filas ya validadas, con la
  /// misma forma que un alta normal (`create`); aquí se recorren **con
  /// mejor esfuerzo**: las buenas se crean, las fallidas se devuelven con
  /// su fila y su motivo, y los nombres repetidos (en la BD o dentro del
  /// propio envío) se omiten con aviso — así re-subir el mismo archivo no
  /// duplica inventario.
  Future<Response> importar(Request request) async {
    asegurarPermiso(request, 'productos', 'crear');
    final body = await readJsonObject(request);
    final crudo = body['productos'];
    if (crudo is! List || crudo.isEmpty) {
      throw const BadRequestException(
        'El campo "productos" debe ser una lista no vacía de productos.',
        code: 'productos_invalidos',
      );
    }
    if (crudo.length > 1000) {
      throw BadRequestException(
        'Máximo 1000 productos por importación (recibidos: ${crudo.length}).',
        code: 'productos_limite',
      );
    }

    // Nombres existentes, leídos por páginas: con ellos basta marcar los
    // repetidos sin volver a consultar la BD por cada fila.
    final existentes = await _nombresExistentes(productos);

    var creados = 0;
    final errores = <Map<String, Object?>>[];
    final omitidos = <Map<String, Object?>>[];

    var posicion = 0;
    for (final elemento in crudo) {
      posicion++;
      if (elemento is! Map) {
        errores.add({
          'fila': posicion,
          'mensaje': 'Cada producto debe ser un objeto.',
        });
        continue;
      }
      final fila = elemento.cast<String, Object?>();
      // La fila real de Excel (si el cliente la envía): los mensajes
      // apuntan a la fila que el usuario ve en su archivo.
      final numeroFila = intOrNull(fila, 'fila') ?? posicion;
      final nombre = fila['nombre']?.toString().trim() ?? '';
      if (nombre.isEmpty) {
        errores.add({
          'fila': numeroFila,
          'mensaje': 'El campo "nombre" es obligatorio.',
        });
        continue;
      }
      final clave = _claveNombre(nombre);
      if (existentes.contains(clave)) {
        omitidos.add({
          'fila': numeroFila,
          'nombre': nombre,
          'motivo': 'Ya existe un producto con ese nombre',
        });
        continue;
      }
      try {
        await _crearDesdeBody(productos, fila);
        existentes.add(clave);
        creados++;
      } on AppException catch (error) {
        // 5xx (BD caída...): no seguimos fallando fila a fila.
        if (error.statusCode >= 500) rethrow;
        errores.add({'fila': numeroFila, 'mensaje': error.message});
      } catch (error) {
        errores.add({
          'fila': numeroFila,
          'mensaje': 'No se pudo crear: $error',
        });
      }
    }

    detalleAuditoria(request, {
      'creados': creados,
      'omitidos': omitidos.length,
      'errores': errores.length,
    }, accion: 'importar');

    return jsonResponse(200, {
      'creados': creados,
      'errores': errores,
      'omitidos': omitidos,
    });
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
      'stock',
      'stockMinimo',
      'categoriaId',
      'marcaId',
      'proveedorId',
      'estado',
    ]);
    ensureHayCampos(campos);
    // Estado ANTES: el evento de auditoría lleva el nombre del producto y
    // el diff de los campos que cambian (precio, estado...).
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

  // --- Variantes (talla + color: el stock real) -----------------------------

  Future<Response> listarVariantes(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'ver');
    final items = await productos.listarVariantes(pathId(id));
    return listJsonResponse(
      items.map((e) => e.toJson()).toList(),
      total: items.length,
      limit: items.length,
      offset: 0,
    );
  }

  Future<Response> crearVariante(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'editar');
    final body = await readJsonObject(request);
    // La combinación puede venir por id o por nombre escrito a mano: en
    // ese caso el backend la busca (o la crea) en el catálogo.
    final tallaId = intOrNull(body, 'tallaId');
    final colorId = intOrNull(body, 'colorId');
    final talla = textOrNull(body, 'talla', maxLength: 30);
    final color = textOrNull(body, 'color', maxLength: 50);
    // Falta un lado de la combinación si no viene ni id ni nombre.
    bool falta(int? id, String? nombre) =>
        (id == null || id <= 0) && (nombre == null || nombre.trim().isEmpty);
    if (falta(tallaId, talla) || falta(colorId, color)) {
      throw const BadRequestException(
        'Cada variante necesita su talla y su color: envía "tallaId" y '
        '"colorId", o "talla" y "color" escritos (por ejemplo «S» y '
        '«Negro»).',
        code: 'fields_required',
      );
    }
    detalleRegistro(
      request,
      nombre: 'variante ${talla ?? tallaId}/${color ?? colorId}',
    );
    final item = await productos.crearVariante(
      pathId(id),
      tallaId: tallaId ?? 0,
      colorId: colorId ?? 0,
      talla: talla,
      color: color,
      stock: doubleOrNull(body, 'stock') ?? 0,
      codigo: textOrNull(body, 'codigo', maxLength: 60),
    );
    return jsonResponse(201, item.toJson());
  }

  Future<Response> actualizarVariante(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'editar');
    final body = await readJsonObject(request);
    final campos = camposEnviados(body, const [
      'tallaId',
      'colorId',
      'stock',
      'codigo',
    ]);
    ensureHayCampos(campos);
    detalleRegistro(
      request,
      nombre: 'variante $id',
      despues: body,
      campos: campos,
    );
    final item = await productos.actualizarVariante(
      pathId(id),
      DatoVariante(
        tallaId: intOrNull(body, 'tallaId') ?? 0,
        colorId: intOrNull(body, 'colorId') ?? 0,
        stock: doubleOrNull(body, 'stock') ?? 0,
        codigo: textOrNull(body, 'codigo', maxLength: 60),
      ),
      campos,
    );
    return jsonResponse(200, item.toJson());
  }

  Future<Response> eliminarVariante(Request request, String id) async {
    asegurarPermiso(request, 'productos', 'editar');
    detalleRegistro(request, nombre: 'variante $id');
    await productos.eliminarVariante(pathId(id));
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
    ..post('/api/v1/productos/importar', importar)
    ..put('/api/v1/productos/<id>', update)
    ..delete('/api/v1/productos/<id>', remove)
    // Variantes de una prenda (talla + color)
    ..get('/api/v1/productos/<id>/variantes', listarVariantes)
    ..post('/api/v1/productos/<id>/variantes', crearVariante)
    ..put('/api/v1/variantes/<id>', actualizarVariante)
    ..delete('/api/v1/variantes/<id>', eliminarVariante);
}

/// Altas: el camino compartido por `create` (una) e `importar` (masiva),
/// para que una fila del Excel pase exactamente por las mismas reglas que
/// el formulario (precios, estados, tallas y variante «Única» cuando no
/// hay variantes).
Future<Product> _crearDesdeBody(
  Productos productos,
  Map<String, Object?> body,
) => productos.crear(
  nombre: requireText(body, 'nombre', maxLength: 150),
  precioVenta: requireDouble(body, 'precioVenta'),
  codigo: textOrNull(body, 'codigo', maxLength: 60),
  imagen: textOrNull(body, 'imagen', maxLength: 500),
  descripcion: textOrNull(body, 'descripcion', maxLength: 2000),
  unidad: textOrNull(body, 'unidad', maxLength: 10),
  precioCompra: doubleOrNull(body, 'precioCompra'),
  precioRebaja: doubleOrNull(body, 'precioRebaja'),
  stock: doubleOrNull(body, 'stock') ?? 0,
  stockMinimo: doubleOrNull(body, 'stockMinimo'),
  categoriaId: intOrNull(body, 'categoriaId'),
  marcaId: intOrNull(body, 'marcaId'),
  proveedorId: intOrNull(body, 'proveedorId'),
  estado: textOrNull(body, 'estado') ?? 'DISPONIBLE',
  variantes: _variantesDesdeBody(body),
);

/// Nombres de todos los productos (normalizados) para detectar los
/// repetidos de una importación con una sola serie de lecturas.
Future<Set<String>> _nombresExistentes(Productos productos) async {
  final nombres = <String>{};
  final total = await productos.contar();
  var offset = 0;
  while (offset < total) {
    final lote = await productos.listar(limit: 200, offset: offset);
    if (lote.isEmpty) break;
    for (final producto in lote) {
      nombres.add(_claveNombre(producto.nombre));
    }
    offset += lote.length;
  }
  return nombres;
}

/// Clave de comparación de nombres: minúsculas, sin acentos ni espacios
/// sobrantes (espejo del `normalizarTexto` del frontend: «Pantalón» y
/// «pantalon» son el mismo producto a efectos de duplicado).
String _claveNombre(String nombre) {
  const acentos = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final base = nombre.toLowerCase().trim();
  final salida = StringBuffer();
  for (final codigo in base.runes) {
    final caracter = String.fromCharCode(codigo);
    salida.write(acentos[caracter] ?? caracter);
  }
  return salida.toString();
}

Product _productoDesdeBody(Map<String, Object?> body) => Product(
  id: 0,
  nombre: body.containsKey('nombre')
      ? requireText(body, 'nombre', maxLength: 150)
      : '',
  codigo: textOrNull(body, 'codigo', maxLength: 60),
  imagen: textOrNull(body, 'imagen', maxLength: 500),
  descripcion: textOrNull(body, 'descripcion', maxLength: 2000),
  unidad: textOrNull(body, 'unidad', maxLength: 10) ?? 'UN',
  precioVenta: body.containsKey('precioVenta')
      ? doubleOrNull(body, 'precioVenta') ?? 0
      : 0,
  precioCompra: doubleOrNull(body, 'precioCompra'),
  precioRebaja: doubleOrNull(body, 'precioRebaja'),
  stock: doubleOrNull(body, 'stock') ?? 0,
  stockMinimo: doubleOrNull(body, 'stockMinimo'),
  categoriaId: intOrNull(body, 'categoriaId'),
  marcaId: intOrNull(body, 'marcaId'),
  proveedorId: intOrNull(body, 'proveedorId'),
  estado: textOrNull(body, 'estado') ?? '',
);

/// Lista opcional `variantes` del cuerpo de alta de producto:
/// `[{tallaId, colorId, stock?, codigo?}, ...]` o, escrito a mano,
/// `[{talla: "S", color: "Negro", stock: 5}, ...]`.
///
/// En el segundo caso el backend resuelve cada nombre en los catálogos
/// `tallas`/`colores` y lo crea si todavía no existe: no hace falta que
/// vengan sembrados.
List<DatoVariante> _variantesDesdeBody(Map<String, Object?> body) {
  final crudo = body['variantes'];
  if (crudo is! List) return const [];
  final variantes = <DatoVariante>[];
  for (final item in crudo) {
    if (item is! Map) {
      throw const BadRequestException(
        'Cada elemento de "variantes" debe ser un objeto.',
        code: 'field_invalid',
      );
    }
    final mapa = item.cast<String, Object?>();
    final tallaId = intOrNull(mapa, 'tallaId') ?? 0;
    final colorId = intOrNull(mapa, 'colorId') ?? 0;
    final talla = textOrNull(mapa, 'talla', maxLength: 30);
    final color = textOrNull(mapa, 'color', maxLength: 50);
    bool falta(int id, String? nombre) =>
        id <= 0 && (nombre == null || nombre.trim().isEmpty);
    if (falta(tallaId, talla) || falta(colorId, color)) {
      throw const BadRequestException(
        'Cada variante necesita su talla y su color: envía "tallaId" y '
        '"colorId", o "talla" y "color" escritos (por ejemplo «S» y '
        '«Negro»).',
        code: 'fields_required',
      );
    }
    variantes.add(
      DatoVariante(
        tallaId: tallaId,
        colorId: colorId,
        talla: talla,
        color: color,
        stock: doubleOrNull(mapa, 'stock') ?? 0,
        codigo: textOrNull(mapa, 'codigo', maxLength: 60),
      ),
    );
  }
  return variantes;
}
