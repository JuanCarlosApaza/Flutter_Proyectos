import '../../database/database.dart';
import '../../models/row_utils.dart';
import 'catalogo.dart';
import 'consultas_ventas.dart';

/// Usuarios por nombre de login, nombre de empleado o rol.
Future<String> usuarioBuscar(DatabaseConnection db, Map<String, String> p) async {
  final termino = p['nombre'] ?? '';
  final filas = await db.query(
    'SELECT u.nombre_usuario, r.nombre AS rol, u.estado::text AS estado, '
    'e.nombre_empleado AS persona '
    'FROM usuarios u '
    'LEFT JOIN roles r ON r.rol_id = u.rol_id '
    'LEFT JOIN empleados e ON e.empleado_id = u.empleado_id '
    "WHERE u.estado <> 'ELIMINADO' "
    'AND (${ilike('u.nombre_usuario', 1)} OR ${ilike('e.nombre_empleado', 1)} '
    'OR ${ilike('r.nombre', 1)}) '
    'ORDER BY u.nombre_usuario ASC LIMIT 5',
    ['%$termino%'],
  );
  if (filas.isEmpty) return 'No hay usuarios que coincidan con «$termino».';
  String filaTexto(Map<String, Object?> fila) {
    final persona = fila['persona']?.toString().trim() ?? '';
    return '- ${fila['nombre_usuario']}'
        '${persona.isEmpty ? '' : ' ($persona)'}: '
        'rol ${fila['rol'] ?? 'sin rol'}, ${fila['estado'] ?? '?'}';
  }

  return [for (final fila in filas) filaTexto(fila)].join('\n');
}

/// Ajustes de configuración (tabla `ajustes`): clave/valor.
Future<String> ajustesListar(DatabaseConnection db, Map<String, String> p) async {
  final filas = await db.query(
    'SELECT clave, valor::text AS valor FROM ajustes ORDER BY clave LIMIT 30',
  );
  if (filas.isEmpty) return 'No hay ajustes configurados.';
  return [
    for (final fila in filas)
      '- ${fila['clave']}: ${fila['valor']}',
  ].join('\n');
}

/// Conteos de las entidades que no son ni inventario ni ventas.
Future<String> conteo(DatabaseConnection db, Map<String, String> p) async {
  final entidad = p['entidad'] ?? '';
  // La tabla y el filtro de estado se fijan aquí según la entidad elegida:
  // nunca se concatena el nombre que llega de fuera.
  final registro = switch (entidad) {
    'clientes' => ('clientes', 'ELIMINADO'),
    'proveedores' => ('proveedores', 'ELIMINADO'),
    'empleados' => ('empleados', 'ELIMINADO'),
    'usuarios' => ('usuarios', 'ELIMINADO'),
    'categorias' => ('categorias', 'ELIMINADO'),
    'productos' => ('productos', 'ELIMINADO'),
    'ordenes' => ('ordenes_pedidos', 'ELIMINADO'),
    'cotizaciones' => ('cotizaciones', 'ELIMINADO'),
    'facturas' => ('facturas', 'ELIMINADO'),
    'roles' => ('roles', 'ELIMINADO'),
    'presentaciones' => ('presentaciones', 'ELIMINADO'),
    'pagos' => ('pagos', 'ELIMINADO'),
    _ => null,
  };
  if (registro == null) return 'No conozco la entidad «$entidad».';
  final (tabla, filtro) = registro;
  final filas = await db.query(
    "SELECT COUNT(*)::int AS total FROM $tabla WHERE estado <> '$filtro'",
  );
  final total = RowUtils.intValue(
    filas.isEmpty ? null : filas.first['total'],
  );
  return 'Hay $total $entidad activos.';
}

/// Órdenes pendientes de cobro, con su importe.
Future<String> pedidosPendientes(DatabaseConnection db, Map<String, String> p) async {
  final filas = await db.query(
    'SELECT orden_id, fecha_orden, total '
    "FROM ordenes_pedidos WHERE estado = 'PENDIENTE' "
    'ORDER BY fecha_orden DESC LIMIT 10',
  );
  if (filas.isEmpty) return 'No hay pedidos pendientes de cobro.';
  var monto = 0.0;
  final lineas = <String>[];
  for (final fila in filas) {
    final importe = RowUtils.doubleValue(fila['total']);
    monto += importe;
    lineas.add(
      '- Orden ${fila['orden_id']} '
      '(${RowUtils.dateToJson(fila['fecha_orden']) ?? 'sin fecha'}): '
      'Bs ${importe.toStringAsFixed(2)}',
    );
  }
  return 'Pedidos pendientes (${filas.length}, total Bs ${monto.toStringAsFixed(2)}):\n'
      '${lineas.join('\n')}';
}

/// Cotizaciones aún vigentes.
Future<String> cotizacionesVigentes(DatabaseConnection db, Map<String, String> p) async {
  final filas = await db.query(
    'SELECT cotizacion_id, nombre_cliente, total, fecha_cotizacion '
    "FROM cotizaciones WHERE estado = 'VIGENTE' "
    'ORDER BY fecha_cotizacion DESC LIMIT 10',
  );
  if (filas.isEmpty) return 'No hay cotizaciones vigentes.';
  final lineas = [
    for (final fila in filas)
      '- Cotización ${fila['cotizacion_id']} '
      '(${fila['nombre_cliente'] ?? 'sin cliente'}, '
      '${RowUtils.dateToJson(fila['fecha_cotizacion']) ?? 'sin fecha'}): '
      'Bs ${RowUtils.doubleValue(fila['total']).toStringAsFixed(2)}',
  ];
  return 'Cotizaciones vigentes (${filas.length}):\n${lineas.join('\n')}';
}

/// Top de clientes por importe comprado (con su periodo).
///
/// `criterio = menos_compra` invierte el orden; `sin_compras` lista los
/// clientes que NO compraron nada en el periodo.
Future<String> clienteTop(DatabaseConnection db, Map<String, String> p) async {
  final periodo = periodoSql(p['periodo'] ?? 'anio');
  final criterio = p['criterio'] ?? 'mas_compra';

  if (criterio == 'sin_compras') {
    final sinCompras = await db.query(
      'SELECT nombre_cliente FROM clientes '
      "WHERE estado <> 'ELIMINADO' "
      'AND NOT EXISTS ('
      'SELECT 1 FROM ordenes_pedidos o '
      "WHERE o.estado IN ('PENDIENTE', 'PAGADO') "
      'AND ${periodo.condicion} '
      'AND (o.cliente_id = clientes.cliente_id '
      'OR o.nombre_cliente = clientes.nombre_cliente)) '
      'ORDER BY nombre_cliente ASC LIMIT 10',
    );
    if (sinCompras.isEmpty) {
      return 'Todos los clientes compraron ${periodo.etiqueta.toLowerCase()}.';
    }
    return 'Sin compras ${periodo.etiqueta.toLowerCase()}: '
        '${sinCompras.length} clientes\n'
        '${[for (final f in sinCompras) '- ${f['nombre_cliente']}'].join('\n')}';
  }

  final filas = await db.query(
    "SELECT COALESCE(nombre_cliente, '(sin cliente registrado)') AS cliente, "
    'COUNT(*)::int AS ordenes, SUM(total) AS monto '
    "FROM ordenes_pedidos WHERE estado IN ('PENDIENTE', 'PAGADO') "
    'AND ${periodo.condicion} '
    'GROUP BY nombre_cliente '
    'ORDER BY monto ${criterio == 'menos_compra' ? 'ASC' : 'DESC'}, '
        'cliente ASC LIMIT 5',
  );
  if (filas.isEmpty) return 'No hay clientes con compras en ese periodo.';
  final primero = filas.first;
  final resto = [
    for (final fila in filas.skip(1))
      '- ${fila['cliente']}: ${fila['ordenes']} órdenes, '
      'Bs ${RowUtils.doubleValue(fila['monto']).toStringAsFixed(2)}',
  ];
  final etiqueta = criterio == 'menos_compra'
      ? 'Cliente que menos compra'
      : 'Cliente que más compra';
  return '$etiqueta: ${primero['cliente']} '
      '(${primero['ordenes']} órdenes, '
      'Bs ${RowUtils.doubleValue(primero['monto']).toStringAsFixed(2)})'
      '${resto.isEmpty ? '' : '\n${resto.join('\n')}'}';
}

/// Datos de clientes por nombre.
Future<String> clienteBuscar(DatabaseConnection db, Map<String, String> p) async {
  final nombre = p['nombre'] ?? '';
  final filas = await db.query(
    'SELECT nombre_cliente, apellido, ci, telefono, '
    'estado::text AS estado '
    "FROM clientes WHERE estado <> 'ELIMINADO' "
    'AND (${ilike('nombre_cliente', 1)} OR ${ilike('apellido', 1)} '
    'OR ${ilike('ci', 1)}) '
    'ORDER BY nombre_cliente ASC LIMIT 5',
    ['%$nombre%'],
  );
  if (filas.isEmpty) return 'No hay clientes que coincidan con «$nombre».';
  return [
    for (final fila in filas)
      '- ${fila['nombre_cliente']} ${fila['apellido'] ?? ''} '
      '(CI ${fila['ci'] ?? '—'}, ${fila['telefono'] ?? 'sin teléfono'}, '
      '${fila['estado'] ?? '?'})'
      .trim(),
  ].join('\n');
}

/// Proveedores por nombre o ciudad; sin término, lista los activos.
Future<String> proveedorBuscar(DatabaseConnection db, Map<String, String> p) async {
  final termino = p['termino'] ?? '';
  final filas = await db.query(
    'SELECT nombre_proveedor, ciudad, telefono, estado::text AS estado '
    "FROM proveedores WHERE estado <> 'ELIMINADO' "
    'AND (${ilike('nombre_proveedor', 1)} OR ${ilike('ciudad', 1)}) '
    'ORDER BY nombre_proveedor ASC LIMIT 5',
    ['%$termino%'],
  );
  if (filas.isEmpty) {
    return termino.isEmpty
        ? 'No hay proveedores registrados.'
        : 'No hay proveedores que coincidan con «$termino».';
  }
  return [
    for (final fila in filas)
      '- ${fila['nombre_proveedor']}'
      '${fila['ciudad'] == null ? '' : ' (${fila['ciudad']})'}: '
      'tel ${fila['telefono'] ?? 'sin teléfono'}, '
      '${fila['estado'] ?? '?'}',
  ].join('\n');
}

/// Entradas del catálogo restantes.
List<FuncionConsulta> funcionesOtras() => [
  FuncionConsulta(
    nombre: 'conteo',
    descripcion: 'Cuántos registros hay de una entidad (clientes, empleados…).',
    claves: const [
      'cuantos clientes',
      'cuantos proveedores',
      'cuantos empleados',
      'cuantos usuarios',
      'cuantas categorias',
      'cuantas ordenes',
      'cuantas cotizaciones',
      'cuantas facturas',
      'cuanta gente',
      'cuanto personal',
      'cuantos roles',
      'cuantas presentaciones',
      'cuantos pagos',
    ],
    parametros: const [
      ParametroFuncion(
        'entidad',
        valores: [
          'clientes',
          'proveedores',
          'empleados',
          'usuarios',
          'categorias',
          'productos',
          'ordenes',
          'cotizaciones',
          'facturas',
          'roles',
          'presentaciones',
          'pagos',
        ],
        obligatorio: true,
        pregunta: '¿De qué entidad quieres saber el total?',
      ),
    ],
    ejecutar: conteo,
  ),
  FuncionConsulta(
    nombre: 'pedidos_pendientes',
    descripcion: 'Órdenes pendientes de cobro, con importe.',
    claves: const [
      'pedidos pendientes',
      'ordenes pendientes',
      'pendientes de cobro',
      'por cobrar',
      'sin cobrar',
      'me deben',
    ],
    ejecutar: pedidosPendientes,
  ),
  FuncionConsulta(
    nombre: 'cotizaciones_vigentes',
    descripcion: 'Cotizaciones abiertas (estado VIGENTE).',
    claves: const [
      'cotizaciones',
      'cotizacion vigente',
      'cotizaciones abiertas',
      'tengo cotizaciones',
      'propuestas',
      'abiertas',
    ],
    ejecutar: cotizacionesVigentes,
  ),
  FuncionConsulta(
    nombre: 'cliente_top',
    descripcion: 'Clientes que más han comprado (top por importe).',
    claves: const [
      'cliente compra',
      'cliente que mas',
      'clientes que mas',
      'mejor cliente',
      'compra mas',
      'cliente compro',
      'gasto mas',
      'cliente gasto',
      // El que menos compra (y el que no compra).
      'peor cliente',
      'cliente que menos',
      'clientes que menos',
      'compra menos',
      'gasto menos',
      'no compra',
      'sin compras',
    ],
    parametros: const [
      ParametroFuncion(
        'periodo',
        valores: [
          'hoy',
          'ayer',
          'semana',
          'semana_pasada',
          'mes',
          'mes_pasado',
          'anio',
        ],
        defecto: 'anio',
      ),
      ParametroFuncion(
        'criterio',
        valores: ['mas_compra', 'menos_compra', 'sin_compras'],
        defecto: 'mas_compra',
      ),
    ],
    ejecutar: clienteTop,
  ),
  FuncionConsulta(
    nombre: 'cliente_buscar',
    descripcion: 'Buscar clientes por nombre, apellido o cédula.',
    claves: const [
      'cliente se llama',
      'buscar cliente',
      'datos del cliente',
      'donde esta el cliente',
      'telefono del cliente',
      'telefono de',
    ],
    parametros: const [
      ParametroFuncion(
        'nombre',
        obligatorio: true,
        pregunta: '¿Cómo se llama el cliente?',
      ),
    ],
    ejecutar: clienteBuscar,
  ),
  FuncionConsulta(
    nombre: 'usuario_buscar',
    descripcion:
        'Buscar usuarios por login, nombre del empleado o rol (ADMIN, '
        'CAJERO…).',
    claves: const [
      'que rol',
      'rol de',
      'tiene rol',
      'usuarios con',
      'nombre de usuario',
      'quien es admin',
      'administrador',
      'usuario',
      'buscar empleado',
      'buscar empleados',
      'datos del empleado',
      'buscar rol',
    ],
    parametros: const [
      ParametroFuncion(
        'nombre',
        // Sin nombre lista los primeros usuarios («lista de usuarios»);
        // con nombre inexistente el clasificador sigue preguntando.
        pregunta: '¿De qué usuario hablas?',
      ),
    ],
    ejecutar: usuarioBuscar,
  ),
  FuncionConsulta(
    nombre: 'proveedor_buscar',
    descripcion:
        'Buscar proveedores por nombre o ciudad; sin término lista los '
        'primeros proveedores activos.',
    claves: const [
      'buscar proveedor',
      'buscar proveedores',
      'datos del proveedor',
      'que proveedores',
    ],
    parametros: const [ParametroFuncion('termino')],
    ejecutar: proveedorBuscar,
  ),
  FuncionConsulta(
    nombre: 'ajustes_listar',
    descripcion: 'Ajustes de configuración del sistema (clave/valor).',
    claves: const [
      'ajustes',
      'configuracion',
      'ajuste',
    ],
    ejecutar: ajustesListar,
  ),
];
