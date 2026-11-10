import '../../database/database.dart';
import '../../models/row_utils.dart';
import 'catalogo.dart';

/// Consultas de inventario y stock. Todo el SQL vive aquí, cerrado y con
/// `estado <> 'ELIMINADO'`; la IA solo elige la función y los parámetros.

/// Existencias (`NUMERIC(12, 3)`): recorta los ceros de relleno para que la
/// narración diga «12.75» y no «12.750».
String _stock(Object? valor) {
  final texto = RowUtils.doubleValue(valor).toStringAsFixed(3);
  if (texto.endsWith('.000')) return texto.substring(0, texto.length - 4);
  return texto.replaceFirst(RegExp(r'0+$'), '');
}

/// `stock de <producto>`: estado, stock, precio y proveedor de uno concreto.
Future<String> productoStock(DatabaseConnection db, Map<String, String> p) async {
  final nombre = p['nombre'] ?? '';
  final filas = await db.query(
    'SELECT p.nombre_producto, p.stock, p.precio_venta, p.precio_rebaja, '
    'p.estado::text AS estado, pv.nombre_proveedor '
    'FROM productos p '
    'LEFT JOIN proveedores pv ON pv.proveedor_id = p.proveedor_id '
    "WHERE p.estado <> 'ELIMINADO' "
    'AND ${ilike('p.nombre_producto', 1)} '
    'ORDER BY p.nombre_producto ASC LIMIT 5',
    ['%$nombre%'],
  );
  if (filas.isEmpty) return 'Sin resultados: ningún producto coincide con «$nombre».';
  final lineas = [
    for (final fila in filas)
      '- ${fila['nombre_producto']}: stock ${_stock(fila['stock'])} u., '
      'precio Bs ${RowUtils.doubleValue(fila['precio_venta']).toStringAsFixed(2)}'
      '${fila['precio_rebaja'] != null ? ' (rebaja Bs ${RowUtils.doubleValue(fila['precio_rebaja']).toStringAsFixed(2)})' : ''}'
      ', estado ${fila['estado'] ?? '?'}'
      '${fila['nombre_proveedor'] != null ? ', proveedor ${fila['nombre_proveedor']}' : ''}',
  ];
  return lineas.join('\n');
}

/// Ordena el inventario por stock o precio y devuelve los primeros.
Future<String> productosExtremo(DatabaseConnection db, Map<String, String> p) async {
  final criterio = p['criterio'] ?? 'mas_stock';
  final limite = int.tryParse(p['limite'] ?? '') ?? 5;
  final categoria = p['categoria'];

  final orden = switch (criterio) {
    'menos_stock' => 'p.stock ASC',
    'mas_caro' => 'p.precio_venta DESC',
    'mas_barato' => 'p.precio_venta ASC',
    _ => 'p.stock DESC',
  };
  final condiciones = <String>["p.estado <> 'ELIMINADO'"];
  final parametros = <Object?>[];
  if (categoria != null && categoria.isNotEmpty) {
    parametros.add('%$categoria%');
    condiciones.add(ilike('c.nombre_categoria', parametros.length));
  }

  final filas = await db.query(
    'SELECT p.nombre_producto, p.stock, p.precio_venta, '
    'p.estado::text AS estado, c.nombre_categoria '
    'FROM productos p '
    'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
    'WHERE ${condiciones.join(' AND ')} '
    'ORDER BY $orden, p.nombre_producto ASC '
    'LIMIT $limite',
    parametros,
  );
  if (filas.isEmpty) return 'Sin resultados para ese criterio.';
  final etiqueta = switch (criterio) {
    'menos_stock' => 'Menor stock',
    'mas_caro' => 'Más caro',
    'mas_barato' => 'Más barato',
    _ => 'Más stock',
  };
  // La primera línea ES la respuesta al «cuál»; el resto da contexto.
  String fila(Map<String, Object?> f) =>
      '${f['nombre_producto']} (stock ${_stock(f['stock'])} u., '
      'Bs ${RowUtils.doubleValue(f['precio_venta']).toStringAsFixed(2)}, '
      '${f['estado'] ?? '?'}'
      '${f['nombre_categoria'] != null ? ', ${f['nombre_categoria']}' : ''})';
  return '$etiqueta: ${fila(filas.first)}\n'
      '${[for (final f in filas.skip(1)) '- ${fila(f)}'].join('\n')}';
}

/// Avisos: agotados o con stock bajo.
Future<String> alertasStock(DatabaseConnection db, Map<String, String> p) async {
  final tipo = p['tipo'] ?? 'stock_bajo';
  final umbral = int.tryParse(p['umbral'] ?? '') ?? 5;
  final categoria = p['categoria'];

  final (condicion, etiqueta) = switch (tipo) {
    'agotados' => ("p.stock = 0 OR p.estado = 'AGOTADO'", 'Agotados'),
    _ => ('p.stock BETWEEN 1 AND $umbral', 'Stock bajo (1 a $umbral u.)'),
  };

  final parametros = <Object?>[];
  var filtroCategoria = '';
  if (categoria != null && categoria.isNotEmpty) {
    parametros.add('%$categoria%');
    filtroCategoria = ' AND ${ilike('c.nombre_categoria', 1)}';
  }
  final filas = await db.query(
    'SELECT p.nombre_producto, p.stock, p.estado::text AS estado '
    'FROM productos p '
    'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
    "WHERE p.estado <> 'ELIMINADO' AND ($condicion)$filtroCategoria "
    'ORDER BY p.stock ASC, p.nombre_producto ASC LIMIT 20',
    parametros,
  );
  if (filas.isEmpty) return 'No hay productos: $etiqueta.';
  final lineas = [
    for (final fila in filas)
      '- ${fila['nombre_producto']}: stock ${_stock(fila['stock'])} u.'
      ' (${fila['estado'] ?? '?'})',
  ];
  return '$etiqueta (${filas.length}):\n${lineas.join('\n')}';
}

/// Resumen del inventario: totales por estado.
Future<String> inventarioResumen(DatabaseConnection db, Map<String, String> p) async {
  final filas = await db.query(
    'SELECT estado::text AS estado, COUNT(*)::int AS total, '
    "COALESCE(SUM(stock), 0) AS unidades "
    "FROM productos WHERE estado <> 'ELIMINADO' GROUP BY estado",
  );
  if (filas.isEmpty) return 'No hay productos en el inventario.';
  var total = 0;
  var unidades = 0.0;
  final partes = <String>[];
  for (final fila in filas) {
    total += RowUtils.intValue(fila['total']);
    unidades += RowUtils.doubleValue(fila['unidades']);
    partes.add('${fila['estado']}: ${fila['total']}');
  }
  return 'Productos activos: $total (unidades en stock: ${_stock(unidades)})\n'
      'Por estado: ${partes.join(', ')}';
}

/// Búsqueda libre por nombre.
Future<String> productosBuscar(DatabaseConnection db, Map<String, String> p) async {
  final termino = p['termino'] ?? '';
  final filas = await db.query(
    'SELECT nombre_producto, stock, precio_venta, estado::text AS estado '
    "FROM productos WHERE estado <> 'ELIMINADO' "
    'AND ${ilike('nombre_producto', 1)} '
    'ORDER BY nombre_producto ASC LIMIT 10',
    ['%$termino%'],
  );
  if (filas.isEmpty) return 'No hay productos que coincidan con «$termino».';
  return [
    for (final fila in filas)
      '- ${fila['nombre_producto']}: stock ${_stock(fila['stock'])} u., '
      'Bs ${RowUtils.doubleValue(fila['precio_venta']).toStringAsFixed(2)} (${fila['estado'] ?? '?'})',
  ].join('\n');
}

/// Productos de una categoría.
Future<String> productosCategoria(DatabaseConnection db, Map<String, String> p) async {
  final categoria = p['categoria'] ?? '';
  // El total va explícito: si no, el modelo suma los stocks de las filas y
  // se lo inventa como «165 productos».
  final conteo = await db.query(
    'SELECT COUNT(*)::int AS total FROM productos p '
    'JOIN categorias c ON c.categoria_id = p.categoria_id '
    "WHERE p.estado <> 'ELIMINADO' AND ${ilike('c.nombre_categoria', 1)}",
    ['%$categoria%'],
  );
  final total = RowUtils.intValue(
    conteo.isEmpty ? null : conteo.first['total'],
  );
  final filas = await db.query(
    'SELECT p.nombre_producto, p.stock, p.precio_venta '
    'FROM productos p '
    'JOIN categorias c ON c.categoria_id = p.categoria_id '
    "WHERE p.estado <> 'ELIMINADO' AND ${ilike('c.nombre_categoria', 1)} "
    'ORDER BY p.nombre_producto ASC LIMIT 20',
    ['%$categoria%'],
  );
  if (filas.isEmpty) return 'No hay productos en la categoría «$categoria».';
  final lineas = [
    for (final fila in filas)
      '- ${fila['nombre_producto']}: stock ${_stock(fila['stock'])} u., '
      'Bs ${RowUtils.doubleValue(fila['precio_venta']).toStringAsFixed(2)}',
  ];
  return 'Productos en «$categoria»: $total '
      '(mostrando los primeros ${filas.length}):\n${lineas.join('\n')}';
}

/// Stock agrupado por talla (suma las variantes visibles prenda+talla+
/// color). Con `talla` solo muestra esa talla.
Future<String> stockPorTalla(DatabaseConnection db, Map<String, String> p) async {
  final talla = (p['talla'] ?? '').trim();
  final condiciones = ["v.estado <> 'ELIMINADO'"];
  final parametros = <Object?>[];
  if (talla.isNotEmpty) {
    parametros.add(talla);
    condiciones.add('t.nombre = \$1');
  }
  final filas = await db.query(
    'SELECT t.nombre AS talla, SUM(v.stock) AS unidades '
    'FROM producto_variantes v '
    'JOIN tallas t ON t.talla_id = v.talla_id '
    'WHERE ${condiciones.join(' AND ')} '
    'GROUP BY t.nombre ORDER BY t.nombre',
    parametros,
  );
  if (filas.isEmpty) {
    return talla.isEmpty
        ? 'No hay variantes de stock por talla.'
        : 'No hay stock en la talla «$talla».';
  }
  return [
    for (final fila in filas)
      'Talla ${fila['talla']}: ${_stock(fila['unidades'])} unidades',
  ].join('\n');
}

/// Entradas del catálogo relacionadas con stock e inventario.
List<FuncionConsulta> funcionesStock() => [
  FuncionConsulta(
    nombre: 'producto_stock',
    descripcion: 'Stock, precio y estado de un producto concreto por nombre.',
    claves: const [
      'cuanto tengo de',
      'cuanto queda de',
      'me queda',
      'stock de',
      'stock del',
      'stock',
      'precio',
      'precio de',
      'precio del',
      'precio tiene',
      'cuanto cuesta',
      'cuanto vale',
      'que vale',
      'en stock',
      'tengo de',
      'me provee',
      'quien me provee',
      'proveedor de',
    ],
    parametros: const [
      ParametroFuncion(
        'nombre',
        obligatorio: true,
        pregunta: '¿De qué producto quieres saberlo?',
      ),
    ],
    ejecutar: productoStock,
  ),
  FuncionConsulta(
    nombre: 'productos_extremo',
    descripcion:
        'Productos con más/menos stock o precio más alto/más bajo, ordenados.',
    claves: const [
      'mas stock',
      'menos stock',
      'mayor stock',
      'menor stock',
      'mas caro',
      'mas cara',
      'precio mas alto',
      'precio mas bajo',
      'mas barato',
      'mas barata',
      'mas unidades',
      'mas cantidad',
      'tengo mas',
      'tengo ma ',
      'mas tengo',
    ],
    parametros: const [
      ParametroFuncion(
        'criterio',
        valores: ['mas_stock', 'menos_stock', 'mas_caro', 'mas_barato'],
        defecto: 'mas_stock',
      ),
      ParametroFuncion('limite', esNumero: true, defecto: '5'),
      ParametroFuncion('categoria'),
    ],
    ejecutar: productosExtremo,
  ),
  FuncionConsulta(
    nombre: 'alertas_stock',
    descripcion: 'Productos agotados o con stock bajo.',
    claves: const [
      'agotado',
      'agotados',
      'agoto',
      'sin stock',
      'sin existencias',
      'stock bajo',
      'poco stock',
      'menos de',
      'casi agotado',
      'para reponer',
      'al limite',
      'reponer',
    ],
    parametros: const [
      ParametroFuncion(
        'tipo',
        valores: ['agotados', 'stock_bajo'],
        defecto: 'stock_bajo',
      ),
      ParametroFuncion('umbral', esNumero: true, defecto: '5'),
      ParametroFuncion('categoria'),
    ],
    ejecutar: alertasStock,
  ),
  FuncionConsulta(
    nombre: 'inventario_resumen',
    descripcion: 'Totales del inventario: cuántos productos y unidades hay.',
    claves: const [
      'inventario',
      'cuantos productos',
      'cuantas prendas',
      'cuanto stock tengo',
      'resumen de stock',
      'resumen',
      'el stock',
      'cuantos articulos',
    ],
    ejecutar: inventarioResumen,
  ),
  FuncionConsulta(
    nombre: 'productos_buscar',
    descripcion: 'Buscar productos por nombre libre.',
    claves: const [
      'buscar',
      'buscar producto',
      'buscar prenda',
      'existe el',
      'se llama',
      'que productos hay',
      'cuales productos',
      'lista de productos',
      'necesito ver',
    ],
    parametros: const [
      ParametroFuncion(
        'termino',
        obligatorio: true,
        pregunta: '¿Qué producto quieres buscar?',
      ),
    ],
    ejecutar: productosBuscar,
  ),
  FuncionConsulta(
    nombre: 'productos_categoria',
    descripcion: 'Listar los productos de una categoría.',
    claves: const [
      'hay en la categoria',
      'de la categoria',
      'productos de categoria',
      'que categoria',
      'categorias con',
    ],
    parametros: const [
      ParametroFuncion(
        'categoria',
        obligatorio: true,
        pregunta: '¿De qué categoría quieres ver los productos?',
      ),
    ],
    ejecutar: productosCategoria,
  ),
  FuncionConsulta(
    nombre: 'stock_por_talla',
    descripcion: 'Unidades en stock agrupadas por talla; con talla, solo esa.',
    claves: const [
      'stock por talla',
      'por talla',
      'de talla',
      'en la talla',
      'tallas',
      'talla',
    ],
    parametros: const [
      ParametroFuncion('talla'),
    ],
    ejecutar: stockPorTalla,
  ),
];
