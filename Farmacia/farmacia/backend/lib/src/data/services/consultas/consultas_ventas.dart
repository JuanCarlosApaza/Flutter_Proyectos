import '../../database/database.dart';
import '../../database/dialecto.dart';
import '../../models/row_utils.dart';
import 'catalogo.dart';

/// Consultas de ventas. El periodo llega como parámetro cerrado
/// (`hoy|ayer|semana|mes|mes_pasado|anio`) y se traduce aquí a SQL; la IA
/// nunca redacta la consulta.

/// Inicio del periodo recortado: `date_trunc` en PostgreSQL; en SQLite, el
/// modificador equivalente de `datetime` (la semana empieza el lunes, igual
/// que `date_trunc('week', ...)`).
String _truncado(String parte) {
  if (!Dialecto.sqlite) return "date_trunc('$parte', CURRENT_TIMESTAMP)";
  return switch (parte) {
    'week' =>
      "datetime('now', '-' || ((CAST(strftime('%w', 'now') AS INTEGER) + 6) "
      "% 7) || ' days', 'start of day')",
    'month' => "datetime('now', 'start of month')",
    _ => "datetime('now', 'start of year')",
  };
}

/// `expr - INTERVAL 'n ...'` (PostgreSQL) / `datetime(expr, '-n ...')`
/// (SQLite). Los intervalos que usa este archivo: `7 days`, `14 days`,
/// `1 month`, `2 months`, `1 year`.
String _menos(String expr, String intervalo) =>
    Dialecto.sqlite ? "datetime($expr, '-$intervalo')" : "$expr - INTERVAL '$intervalo'";

/// Hoy: `CURRENT_DATE` (PostgreSQL) / `date('now')` (SQLite, mismo formato
/// `yyyy-MM-dd` con el que se comparan las fechas guardadas como texto).
String get _hoy => Dialecto.sqlite ? "date('now')" : 'CURRENT_DATE';

/// Hoy hace [dias] días.
String _haceDias(int dias) =>
    Dialecto.sqlite ? "date('now', '-$dias days')" : 'CURRENT_DATE - $dias';

/// Traduce un periodo a (condición actual, condición previa, etiquetas).
///
/// La condición previa sirve para la comparativa («ayer fue +10 %») sin una
/// segunda consulta.
({String condicion, String previa, String etiqueta, String etiquetaPrevia})
periodoSql(String periodo) {
  final semana = _truncado('week');
  final mes = _truncado('month');
  final anio = _truncado('year');
  final haceSiete = _menos(semana, '7 days');
  final haceCatorce = _menos(semana, '14 days');
  final mesAnterior = _menos(mes, '1 month');
  final dosMeses = _menos(mes, '2 months');
  final anioAnterior = _menos(anio, '1 year');

  return switch (periodo) {
    'hoy' => (
      condicion: 'fecha_orden >= $_hoy',
      previa: 'fecha_orden >= ${_haceDias(1)} AND fecha_orden < $_hoy',
      etiqueta: 'Hoy',
      etiquetaPrevia: 'Ayer',
    ),
    'ayer' => (
      condicion: 'fecha_orden >= ${_haceDias(1)} AND fecha_orden < $_hoy',
      previa:
          'fecha_orden >= ${_haceDias(2)} AND fecha_orden < ${_haceDias(1)}',
      etiqueta: 'Ayer',
      etiquetaPrevia: 'Antes de ayer',
    ),
    'semana_pasada' => (
      condicion: 'fecha_orden >= $haceSiete AND fecha_orden < $semana',
      previa: 'fecha_orden >= $haceCatorce AND fecha_orden < $haceSiete',
      etiqueta: 'Semana pasada',
      etiquetaPrevia: 'Hace dos semanas',
    ),
    'semana' => (
      condicion: 'fecha_orden >= $semana',
      previa: 'fecha_orden >= $haceSiete AND fecha_orden < $semana',
      etiqueta: 'Esta semana',
      etiquetaPrevia: 'Semana pasada',
    ),
    'mes_pasado' => (
      condicion: 'fecha_orden >= $mesAnterior AND fecha_orden < $mes',
      previa: 'fecha_orden >= $dosMeses AND fecha_orden < $mesAnterior',
      etiqueta: 'Mes pasado',
      etiquetaPrevia: 'Hace dos meses',
    ),
    'anio' => (
      condicion: 'fecha_orden >= $anio',
      previa: 'fecha_orden >= $anioAnterior AND fecha_orden < $anio',
      etiqueta: 'Este año',
      etiquetaPrevia: 'Año pasado',
    ),
    _ => (
      condicion: 'fecha_orden >= $mes',
      previa: 'fecha_orden >= $mesAnterior AND fecha_orden < $mes',
      etiqueta: 'Este mes',
      etiquetaPrevia: 'Mes pasado',
    ),
  };
}

String _dinero(Object? valor) =>
    RowUtils.doubleValue(valor).toStringAsFixed(2);

/// Cifras de ventas del periodo con su comparativa contra el previo.
Future<String> ventasTotales(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'mes');
  // SQLite no admite `FILTER (WHERE ...)`: el mismo conteo/importe
  // condicionado se expresa con `SUM(CASE WHEN ...)`.
  final sql = Dialecto.sqlite
      ? 'SELECT '
            'SUM(CASE WHEN ${periodo.condicion} THEN 1 ELSE 0 END) AS n, '
            'COALESCE(SUM(CASE WHEN ${periodo.condicion} '
            'THEN total ELSE 0 END), 0) AS monto, '
            'SUM(CASE WHEN ${periodo.previa} THEN 1 ELSE 0 END) AS n_previo, '
            'COALESCE(SUM(CASE WHEN ${periodo.previa} '
            'THEN total ELSE 0 END), 0) AS monto_previo '
            "FROM ordenes_pedidos WHERE estado IN ('PENDIENTE', 'PAGADO')"
      : 'SELECT '
            'COUNT(*) FILTER (WHERE ${periodo.condicion})::int AS n, '
            'COALESCE(SUM(total) FILTER (WHERE ${periodo.condicion}), 0) AS monto, '
            'COUNT(*) FILTER (WHERE ${periodo.previa})::int AS n_previo, '
            'COALESCE(SUM(total) FILTER (WHERE ${periodo.previa}), 0) AS monto_previo '
            "FROM ordenes_pedidos WHERE estado IN ('PENDIENTE', 'PAGADO')";
  final filas = await db.query(sql);
  final fila = filas.isEmpty ? const <String, Object?>{} : filas.first;
  final n = RowUtils.intValue(fila['n']);
  final monto = RowUtils.doubleValue(fila['monto']);
  final nPrevio = RowUtils.intValue(fila['n_previo']);
  final montoPrevio = RowUtils.doubleValue(fila['monto_previo']);

  String variacion(double actual, double anterior) {
    if (anterior == 0) return actual == 0 ? '(sin cambio)' : '(sin dato previo)';
    final pct = ((actual - anterior) / anterior) * 100;
    return '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
  }

  return '${periodo.etiqueta}: $n órdenes por Bs ${_dinero(monto)} '
      '(${periodo.etiquetaPrevia}: $nPrevio órdenes por Bs ${_dinero(montoPrevio)}, '
      '${variacion(monto, montoPrevio)})';
}

/// Qué se vendió en el periodo (top por unidades).
///
/// Con `criterio = sin_vender` invierte la pregunta: lista los productos
/// activos que NO tuvieron ninguna venta en el periodo.
Future<String> ventasDetalle(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'mes');
  final criterio = p['criterio'] ?? 'mas_vendido';
  final limite = int.tryParse(p['limite'] ?? '') ?? 5;
  final categoria = p['categoria'];

  if (criterio == 'sin_vender') {
    return _productosSinVentas(
      db,
      periodo: periodo,
      categoria: categoria,
      limite: limite,
    );
  }

  final condiciones = <String>[
    "d.estado <> 'ELIMINADO'",
    "o.estado IN ('PENDIENTE', 'PAGADO')",
    periodo.condicion,
  ];
  final parametros = <Object?>[];
  if (categoria != null && categoria.isNotEmpty) {
    parametros.add('%$categoria%');
    condiciones.add(ilike('c.nombre_categoria', parametros.length));
  }

  final filas = await db.query(
    'SELECT d.nombre_producto, SUM(d.cantidad)::int AS unidades, '
    'SUM(d.monto_total) AS monto '
    'FROM detalles_ordenes_pedidos d '
    'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
    'LEFT JOIN productos p ON p.producto_id = d.producto_id '
    'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
    'WHERE ${condiciones.join(' AND ')} '
    'GROUP BY d.nombre_producto '
    'ORDER BY unidades ${criterio == 'menos_vendido' ? 'ASC' : 'DESC'}, '
        'd.nombre_producto ASC '
    'LIMIT $limite',
    parametros,
  );
  if (filas.isEmpty) return 'Sin ventas registradas en ese periodo.';
  // Igual que en extremos: la primera línea es la respuesta al «qué».
  String fila(Map<String, Object?> f) =>
      '${f['nombre_producto']}: ${f['unidades'] ?? 0} u. '
      '(Bs ${_dinero(f['monto'])})';
  final etiqueta = criterio == 'menos_vendido'
      ? 'Menos vendido'
      : 'Más vendido del periodo';
  return '$etiqueta: ${fila(filas.first)}\n'
      '${[for (final f in filas.skip(1)) '- ${fila(f)}'].join('\n')}';
}

/// Productos activos sin NINGUNA venta en el periodo («¿qué no se vende?»).
Future<String> _productosSinVentas(
  DatabaseConnection db, {
  required ({String condicion, String previa, String etiqueta, String etiquetaPrevia}) periodo,
  String? categoria,
  required int limite,
}) async {
  final parametros = <Object?>[];
  final condiciones = [
    "p.estado <> 'ELIMINADO'",
    'NOT EXISTS ('
        'SELECT 1 FROM detalles_ordenes_pedidos d '
        'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
        "WHERE d.producto_id = p.producto_id "
        "AND d.estado <> 'ELIMINADO' "
        "AND o.estado IN ('PENDIENTE', 'PAGADO') "
        'AND ${periodo.condicion})',
  ];
  if (categoria != null && categoria.isNotEmpty) {
    parametros.add('%$categoria%');
    condiciones.add(ilike('c.nombre_categoria', parametros.length));
  }

  final filas = await db.query(
    'SELECT p.nombre_producto, p.stock '
    'FROM productos p '
    'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
    'WHERE ${condiciones.join(' AND ')} '
    'ORDER BY p.nombre_producto ASC '
    'LIMIT $limite',
    parametros,
  );
  if (filas.isEmpty) {
    return 'Todos los productos se vendieron ${periodo.etiqueta.toLowerCase()}.';
  }
  return 'Sin ventas ${periodo.etiqueta.toLowerCase()}: ${filas.length} productos\n'
      '${[for (final f in filas) '- ${f['nombre_producto']} (stock ${RowUtils.intValue(f['stock'])} u.)'].join('\n')}';
}

/// Unidades y monto de un producto concreto en el periodo.
Future<String> ventasProducto(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'mes');
  final nombre = p['nombre'] ?? '';

  // El producto debe existir en el catálogo: si no, se dice tal cual en vez
  // de devolver «sin ventas» de algo que no está.
  final existe = await db.query(
    'SELECT 1 FROM productos '
    "WHERE estado <> 'ELIMINADO' AND ${ilike('nombre_producto', 1)} LIMIT 1",
    ['%$nombre%'],
  );
  if (existe.isEmpty) {
    return 'Sin resultados: ningún producto coincide con «$nombre».';
  }

  final filas = await db.query(
    'SELECT COALESCE(SUM(d.cantidad), 0)::int AS unidades, '
    'COALESCE(SUM(d.monto_total), 0) AS monto '
    'FROM detalles_ordenes_pedidos d '
    'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
    "WHERE d.estado <> 'ELIMINADO' "
    "AND o.estado IN ('PENDIENTE', 'PAGADO') "
    'AND ${periodo.condicion} '
    'AND ${ilike('d.nombre_producto', 1)}',
    ['%$nombre%'],
  );
  final fila = filas.isEmpty ? const <String, Object?>{} : filas.first;
  final unidades = RowUtils.intValue(fila['unidades']);
  if (unidades == 0) {
    return 'Sin ventas de «$nombre» en ${periodo.etiqueta.toLowerCase()}.';
  }
  return '${periodo.etiqueta} vendiste $unidades u. de «$nombre» '
      'por Bs ${_dinero(fila['monto'])}';
}

/// Ventas del periodo agrupadas por categoría.
///
/// `criterio = menos_vendido` invierte el orden; `sin_vender` lista las
/// categorías sin NINGUNA venta en el periodo.
Future<String> ventasCategoria(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'mes');
  final criterio = p['criterio'] ?? 'mas_vendido';

  if (criterio == 'sin_vender') {
    final sinVentas = await db.query(
      'SELECT c.nombre_categoria FROM categorias c '
      "WHERE c.estado <> 'ELIMINADO' "
      'AND NOT EXISTS ('
      'SELECT 1 FROM detalles_ordenes_pedidos d '
      'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
      'LEFT JOIN productos p ON p.producto_id = d.producto_id '
      'WHERE p.categoria_id = c.categoria_id '
      "AND d.estado <> 'ELIMINADO' "
      "AND o.estado IN ('PENDIENTE', 'PAGADO') "
      'AND ${periodo.condicion}) '
      'ORDER BY c.nombre_categoria ASC',
    );
    if (sinVentas.isEmpty) {
      return 'Todas las categorías se vendieron '
          '${periodo.etiqueta.toLowerCase()}.';
    }
    return 'Categorías sin ventas '
        '${periodo.etiqueta.toLowerCase()}: ${sinVentas.length}\n'
        '${[for (final f in sinVentas) '- ${f['nombre_categoria']}'].join('\n')}';
  }

  final filas = await db.query(
    'SELECT COALESCE(c.nombre_categoria, \'(sin categoría)\') AS categoria, '
    'SUM(d.cantidad)::int AS unidades, SUM(d.monto_total) AS monto '
    'FROM detalles_ordenes_pedidos d '
    'JOIN ordenes_pedidos o ON o.orden_id = d.orden_id '
    'LEFT JOIN productos p ON p.producto_id = d.producto_id '
    'LEFT JOIN categorias c ON c.categoria_id = p.categoria_id '
    "WHERE d.estado <> 'ELIMINADO' "
    "AND o.estado IN ('PENDIENTE', 'PAGADO') "
    'AND ${periodo.condicion} '
    'GROUP BY c.nombre_categoria '
    'ORDER BY monto ${criterio == 'menos_vendido' ? 'ASC' : 'DESC'}',
  );
  if (filas.isEmpty) return 'Sin ventas registradas en ese periodo.';
  // El total va calculado aquí: si se lo dejamos al modelo, se inventa la
  // suma (probado: «100 u. ($430.30)» con datos que suman 27 u.).
  var unidades = 0;
  var monto = 0.0;
  final lineas = <String>[];
  for (final fila in filas) {
    unidades += RowUtils.intValue(fila['unidades']);
    monto += RowUtils.doubleValue(fila['monto']);
    lineas.add(
      '- ${fila['categoria']}: ${fila['unidades'] ?? 0} u. '
      '(Bs ${_dinero(fila['monto'])})',
    );
  }
  if (criterio == 'menos_vendido') {
    final resto = lineas.skip(1).toList();
    return 'Categoría que menos vende: ${lineas.first.replaceFirst('- ', '')}'
        '${resto.isEmpty ? '' : '\n${resto.join('\n')}'}';
  }
  return 'Total: $unidades u. (Bs ${_dinero(monto)}) '
      'en ${filas.length} categorías:\n${lineas.join('\n')}';
}

/// Cobros del periodo por método de pago (tabla `pagos`).
Future<String> pagosResumen(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'hoy');
  final condicion = periodo.condicion.replaceAll('fecha_orden', 'fecha_creacion');
  final metodo = (p['metodo'] ?? '').trim();
  final parametros = <Object?>[];
  var filtroMetodo = '';
  if (metodo.isNotEmpty) {
    parametros.add(metodo);
    filtroMetodo = ' AND metodo_pago ILIKE \$${parametros.length}';
  }
  final filas = await db.query(
    'SELECT metodo_pago, COUNT(*)::int AS n, SUM(monto) AS monto '
    "FROM pagos WHERE estado <> 'ELIMINADO' "
    'AND $condicion$filtroMetodo '
    'GROUP BY metodo_pago ORDER BY monto DESC',
    parametros,
  );
  if (filas.isEmpty) return 'No hay pagos registrados en ese periodo.';
  var total = 0.0;
  var totalN = 0;
  for (final fila in filas) {
    total += RowUtils.doubleValue(fila['monto']);
    totalN += RowUtils.intValue(fila['n']);
  }
  final lineas = [
    for (final fila in filas)
      '- ${fila['metodo_pago']}: Bs ${_dinero(fila['monto'])} '
      '(${fila['n']} pagos)',
  ];
  return '${periodo.etiqueta} se cobraron Bs ${_dinero(total)} '
      'en $totalN pagos${metodo.isNotEmpty ? ' de $metodo' : ''}:\n'
      '${lineas.join('\n')}';
}

/// Facturas emitidas del periodo: subtotal, rebajas e IVA (tabla `facturas`).
Future<String> facturasResumen(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'mes');
  final condicion = periodo.condicion.replaceAll('fecha_orden', 'fecha_factura');
  final filas = await db.query(
    'SELECT COUNT(*)::int AS n, COALESCE(SUM(subtotal), 0) AS subtotal, '
    'COALESCE(SUM(rebaja), 0) AS rebaja, COALESCE(SUM(iva), 0) AS iva '
    "FROM facturas WHERE estado = 'EMITIDA' AND $condicion",
  );
  final fila = filas.isEmpty ? const <String, Object?>{} : filas.first;
  final n = RowUtils.intValue(fila['n']);
  if (n == 0) return 'No hay facturas emitidas en ese periodo.';
  return '${periodo.etiqueta}: $n facturas emitidas '
      '(subtotal Bs ${_dinero(fila['subtotal'])}, '
      'rebajas Bs ${_dinero(fila['rebaja'])}, '
      'IVA Bs ${_dinero(fila['iva'])})';
}

/// Vendedores que más (o menos) han vendido, por importe de sus órdenes.
Future<String> vendedorTop(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'anio');
  final criterio = p['criterio'] ?? 'mas_vendido';
  final orden = criterio == 'menos_vendido' ? 'monto ASC' : 'monto DESC';
  final filas = await db.query(
    "SELECT COALESCE(e.nombre_empleado, '(sin vendedor)') AS vendedor, "
    'COUNT(*)::int AS ordenes, COALESCE(SUM(o.total), 0) AS monto '
    'FROM ordenes_pedidos o '
    'LEFT JOIN empleados e ON e.empleado_id = o.empleado_id '
    "WHERE o.estado IN ('PENDIENTE', 'PAGADO') "
    'AND ${periodo.condicion} '
    'GROUP BY e.nombre_empleado '
    'ORDER BY $orden, vendedor ASC LIMIT 5',
  );
  if (filas.isEmpty) return 'No hay ventas de vendedores en ese periodo.';
  final primero = filas.first;
  final resto = [
    for (final fila in filas.skip(1))
      '- ${fila['vendedor']}: ${fila['ordenes']} órdenes, '
      'Bs ${_dinero(fila['monto'])}',
  ];
  final etiqueta =
      criterio == 'menos_vendido' ? 'vende menos' : 'vende más';
  return 'El vendedor que $etiqueta: ${primero['vendedor']} '
      '(${primero['ordenes']} órdenes, Bs ${_dinero(primero['monto'])})'
      '${resto.isEmpty ? '' : '\n${resto.join('\n')}'}';
}

/// Entradas del catálogo relacionadas con ventas.
List<FuncionConsulta> funcionesVentas() => [
  FuncionConsulta(
    nombre: 'ventas_totales',
    descripcion:
        'Cifra de ventas (órdenes e importe) de un periodo, con comparativa '
        'contra el periodo anterior.',
    claves: const [
      'cuanto vendi',
      'cuanto facture',
      'cuanto ingrese',
      'cuanto gane',
      'cuanto ganamos',
      'cuanto ganado',
      'cuanto cobramos',
      'como vamos',
      'dia de ayer',
      'mes pasado',
      'de la semana pasada',
      'facturacion',
      'como me fue',
      'como me ha ido',
      'como me va',
      'como ha ido',
      'ventas de',
      'ventas de hoy',
      'venta de',
    ],
    parametros: const [
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'mes',
      ),
    ],
    ejecutar: ventasTotales,
  ),
  FuncionConsulta(
    nombre: 'ventas_detalle',
    descripcion:
        'Qué productos se vendieron más en un periodo (top por unidades).',
    claves: const [
      'que vende mas',
      'que se vende mas',
      'mas vendido',
      'mas vendidos',
      'top ventas',
      'top de ventas',
      'lo que mas',
      'productos vendidos',
      'cuales se venden',
      'que vendi',
      'vendi ayer',
      'se vendio',
      'vende menos',
      'vendidos este',
      // Superlativo en cualquier orden: «vendi mas», «he vendido mas»,
      // «que producto vendiste mas»… tolera incluso typos en otras palabras.
      'vendi mas',
      'vendio mas',
      'vendido mas',
      'vendiste mas',
      'vendidos mas',
      'vendi menos',
      'vendido menos',
      'vendiste menos',
      'mas he vendido',
      'mas vendi',
      // Lo que NO se vende (negación explícita).
      'no se vende',
      'no vende',
      'sin ventas',
      'no lo vende',
      'nunca se vende',
    ],
    parametros: const [
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'mes',
      ),
      ParametroFuncion(
        'criterio',
        valores: ['mas_vendido', 'menos_vendido', 'sin_vender'],
        defecto: 'mas_vendido',
      ),
      ParametroFuncion('categoria'),
      ParametroFuncion('limite', esNumero: true, defecto: '5'),
    ],
    ejecutar: ventasDetalle,
  ),
  FuncionConsulta(
    nombre: 'ventas_producto',
    descripcion: 'Unidades e importe vendidos de un producto concreto.',
    claves: const [
      'vendi de',
      'ventas de',
      'cuanto vendi de',
      'se ha vendido',
      'han vendido',
    ],
    parametros: const [
      ParametroFuncion(
        'nombre',
        obligatorio: true,
        pregunta: '¿De qué producto quieres saber las ventas?',
      ),
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'mes',
      ),
    ],
    ejecutar: ventasProducto,
  ),
  FuncionConsulta(
    nombre: 'ventas_categoria',
    descripcion: 'Ventas del periodo agrupadas por categoría.',
    claves: const [
      'ventas por categoria',
      'categorias mas vendidas',
      'que categoria vende',
      'por categorias',
      'van las categorias',
      'como van las categorias',
      'categoria gano',
      'gano mas',
      // La que menos vende (y la que no vende).
      'categoria menos',
      'categorias menos',
      'mas vendida',
      'menos vendida',
      'categoria sin ventas',
      'categorias sin ventas',
    ],
    parametros: const [
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'mes',
      ),
      ParametroFuncion(
        'criterio',
        valores: ['mas_vendido', 'menos_vendido', 'sin_vender'],
        defecto: 'mas_vendido',
      ),
    ],
    ejecutar: ventasCategoria,
  ),
  FuncionConsulta(
    nombre: 'pagos_resumen',
    descripcion: 'Cobros del periodo por método de pago (efectivo, QR…).',
    claves: const [
      'cuanto cobre',
      'metodo de pago',
      'forma de pago',
      'en efectivo',
      'en qr',
      'yape',
      'cobrado',
      'resumen de pagos',
      'pagos',
    ],
    parametros: const [
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'hoy',
      ),
      ParametroFuncion(
        'metodo',
        valores: [
          'EFECTIVO',
          'QR',
          'TARJETA',
          'TARJETA_CREDITO',
          'TARJETA_DEBITO',
          'YAPE',
        ],
      ),
    ],
    ejecutar: pagosResumen,
  ),
  FuncionConsulta(
    nombre: 'facturas_resumen',
    descripcion: 'Facturas emitidas del periodo: subtotal, rebajas e IVA.',
    claves: const [
      'cuanto iva',
      'iva ',
      'facturas del',
      'factura emitida',
      'rebajas del',
    ],
    parametros: const [
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'mes',
      ),
    ],
    ejecutar: facturasResumen,
  ),
  FuncionConsulta(
    nombre: 'vendedor_top',
    descripcion:
        'Vendedores que más (o menos) han vendido, por importe de sus '
        'órdenes.',
    claves: const [
      'vendedor',
      'vendedores',
      'vendedor vende',
      'menos vende',
      'mejor vendedor',
    ],
    parametros: const [
      ParametroFuncion(
        'criterio',
        valores: ['mas_vendido', 'menos_vendido'],
        defecto: 'mas_vendido',
      ),
      ParametroFuncion(
        'periodo',
        valores: ['hoy', 'ayer', 'semana', 'semana_pasada', 'mes', 'mes_pasado', 'anio'],
        defecto: 'anio',
      ),
    ],
    ejecutar: vendedorTop,
  ),
];
