// Smoke temporal del driver SQLite (se borra tras la verificación).
import 'dart:io';

import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/security/usuario_programador.dart';
import 'package:ventas_backend/src/data/services/motor_local_llm.dart';
import 'package:ventas_backend/src/domain/rules/contrasenas.dart';
import 'package:ventas_backend/src/domain/rules/suscripcion.dart';
import 'package:ventas_backend/src/data/repositories/persona_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/product_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/sesion_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/venta_repository_impl.dart';
import 'package:ventas_backend/src/data/services/consultas/consultas_stock.dart';
import 'package:ventas_backend/src/data/services/consultas/consultas_ventas.dart';

int _fallos = 0;

void check(String nombre, Object condicion) {
  final ok = condicion == true;
  if (!ok) _fallos++;
  print('${ok ? 'OK  ' : 'FALL'} $nombre${ok ? '' : ' -> $condicion'}');
}

Future<int> contar(
  SqliteDatabase db,
  String sql, [
  List<Object?> params = const [],
]) async {
  final filas = await db.query(sql, params);
  return filas.first.values.first as int;
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('smoke_sqlite');
  final db = SqliteDatabase('${dir.path}${Platform.pathSeparator}ventas.db');

  // 1. Traducción
  check(
    'traduccion \$1',
    traducirSqlite('SELECT * FROM t WHERE a = \$1') ==
        'SELECT * FROM t WHERE a = ?1',
  );
  check(
    'traduccion cast',
    traducirSqlite('SELECT COUNT(*)::int AS total FROM t') ==
        'SELECT COUNT(*) AS total FROM t',
  );
  check(
    'traduccion ilike',
    traducirSqlite("nombre ILIKE '%x%'") == "nombre LIKE '%x%'",
  );
  check(
    'literal intacto',
    traducirSqlite(r"WHERE contrasena NOT LIKE '$2%'") ==
        r"WHERE contrasena NOT LIKE '$2%'",
  );
  check(
    'any',
    traducirSqlite('WHERE id = ANY(\$1)') ==
        'WHERE id IN (SELECT value FROM json_each(?1))',
  );
  check(
    'for update',
    traducirSqlite('SELECT 1 FROM t FOR UPDATE') == 'SELECT 1 FROM t',
  );
  check(
    'distinct',
    traducirSqlite('estado IS DISTINCT FROM \$1::estado_orden') ==
        'estado IS NOT ?1',
  );
  check(
    'now',
    traducirSqlite('WHERE expira_en < now()') ==
        'WHERE expira_en < CURRENT_TIMESTAMP',
  );

  // 2. Migración de partida: el esquema base + las compartidas (016-023).
  final migraciones = Migrator(db, engine: 'sqlite');
  final aplicadas = await migraciones.migrate();
  check(
    'migracion aplicada',
    aplicadas.length == 9 &&
        aplicadas.first == '000_esquema_sqlite' &&
        aplicadas.last == '023_marcas_garantia',
  );
  check('idempotente', (await migraciones.migrate()).isEmpty);
  // 2b. La 016 añade las columnas de venta fraccionada en SQLite.
  final columnas = await db.query(
    "SELECT name FROM pragma_table_info('productos') WHERE name IN "
    "('codigo', 'unidad', 'stock_minimo')",
  );
  check('016 columnas productos', columnas.length == 3);
  // 2c. La 017 levanta el CHECK fijo de `productos.unidad` (conservando los
  //     códigos ya escritos) y siembra el catálogo de unidades.
  check(
    '017 unidades sembradas',
    (await contar(db, 'SELECT COUNT(*) AS n FROM unidades_medida')) == 15,
  );
  await db.query(
    "INSERT INTO productos (nombre_producto, precio_venta, unidad) VALUES ('Libra', 5.0, 'LB')",
  );
  check(
    '017 unidad nueva admitida',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM productos WHERE unidad = 'LB'",
        )) ==
        1,
  );
  check(
    '017 unidades conservadas',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM productos WHERE unidad NOT IN ('UN','KG')",
        )) >=
        1,
  );
  // 2d. La 018 añade la descripción libre del producto: nula por defecto y
  //     con texto de hasta 255 caracteres cuando se escribe.
  check(
    '018 columna descripcion',
    (await db.query(
          "SELECT name FROM pragma_table_info('productos') "
          "WHERE name = 'descripcion'",
        )).length ==
        1,
  );
  check(
    '018 descripcion nula por defecto',
    (await contar(
          db,
          'SELECT COUNT(*) AS n FROM productos WHERE descripcion IS NOT NULL',
        )) ==
        0,
  );
  await db.query(
    "UPDATE productos SET descripcion = 'Para calentar' "
    "WHERE nombre_producto = 'Libra'",
  );
  check(
    '018 descripcion escrita',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM productos "
          "WHERE descripcion = 'Para calentar'",
        )) ==
        1,
  );
  try {
    await db.query(
      "INSERT INTO unidades_medida (codigo, nombre_unidad, tipo, decimales) "
      "VALUES ('XX', 'Mala', 'NO_EXISTE', 9)",
    );
    check('017 checks tipo/decimales', false);
  } catch (e) {
    check(
      '017 checks tipo/decimales',
      e.toString().contains('check') || e.toString().contains('Restricción'),
    );
  }

  // 2e. La 019 añade el módulo `reportes` y concede `reportes.ver` a los
  //     roles que ya tenían `dashboard.ver` (ADMIN y CAJERO).
  check(
    '019 permisos reportes',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM permisos WHERE modulo = 'reportes'",
        )) ==
        4,
  );
  check(
    '019 reportes.ver a ADMIN y CAJERO',
    (await contar(
          db,
          'SELECT COUNT(*) AS n FROM rol_permisos rp '
          'JOIN permisos p ON p.permiso_id = rp.permiso_id '
          "WHERE p.modulo = 'reportes' AND p.accion = 'ver'",
        )) ==
        2,
  );

  // 2f. La 020 da a ADMIN las tres acciones de escritura de `reportes`, que
  //     la 019 no concedía a nadie: con ellas ADMIN suma los mismos 56 que
  //     siembra `sql/reset_ventas.sql` (antes la ruta de migraciones dejaba 53).
  check(
    '020 ADMIN con los 56 permisos',
    (await contar(
          db,
          'SELECT COUNT(*) AS n FROM rol_permisos rp '
          'JOIN roles r ON r.rol_id = rp.rol_id '
          "WHERE r.nombre = 'ADMIN'",
        )) ==
        56,
  );
  check(
    '020 CAJERO se queda con reportes.ver',
    (await contar(
          db,
          'SELECT COUNT(*) AS n FROM rol_permisos rp '
          'JOIN permisos p ON p.permiso_id = rp.permiso_id '
          'JOIN roles r ON r.rol_id = rp.rol_id '
          "WHERE r.nombre = 'CAJERO' AND p.modulo = 'reportes'",
        )) ==
        1,
  );

  // 2g. La 021: la clave la ocupan solo las filas vivas. El catálogo de
  //     unidades pasa además por la reconstrucción de su tabla (SQLite).
  check(
    '021 catálogo de unidades intacto',
    (await contar(db, 'SELECT COUNT(*) AS n FROM unidades_medida')) == 15,
  );
  await db.query(
    "INSERT INTO productos (nombre_producto, precio_venta, codigo) "
    "VALUES ('021 a', 1.0, 'COD-021')",
  );
  await db.query(
    "UPDATE productos SET estado = 'ELIMINADO' WHERE codigo = 'COD-021'",
  );
  await db.query(
    "INSERT INTO productos (nombre_producto, precio_venta, codigo) "
    "VALUES ('021 b', 1.0, 'COD-021')",
  );
  check(
    '021 la fila oculta libera el codigo',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM productos WHERE codigo = 'COD-021'",
        )) ==
        2,
  );
  try {
    await db.query(
      "INSERT INTO productos (nombre_producto, precio_venta, codigo) "
      "VALUES ('021 c', 1.0, 'COD-021')",
    );
    check('021 dos filas vivas con el mismo codigo chocan', false);
  } catch (e) {
    check(
      '021 dos filas vivas con el mismo codigo chocan',
      e.toString().toLowerCase().contains('unique'),
    );
  }
  await db.query("DELETE FROM productos WHERE codigo = 'COD-021'");

  // 2h. La 022: catálogo de colores y variantes de stock. El nombre de color
  //     es único solo entre filas vivas y sin distinguir mayúsculas.
  check(
    '022 tablas colores y variantes',
    (await db.query(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('colores', 'producto_variantes')",
        )).length ==
        2,
  );
  await db.query(
    "INSERT INTO colores (nombre, codigo_hex) VALUES ('Rojo', '#FF0000')",
  );
  try {
    await db.query("INSERT INTO colores (nombre) VALUES ('ROJO')");
    check('022 nombre de color único entre vivos', false);
  } catch (e) {
    check(
      '022 nombre de color único entre vivos',
      e.toString().toLowerCase().contains('unique'),
    );
  }
  await db.query(
    "UPDATE colores SET estado = 'ELIMINADO' WHERE nombre = 'Rojo'",
  );
  await db.query("INSERT INTO colores (nombre) VALUES ('ROJO')");
  check(
    '022 el color oculto libera la clave',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM colores WHERE estado <> 'ELIMINADO'",
        )) ==
        1,
  );

  // Una sola «Único» viva por producto, una variante por color vivo y
  // stock que no baja de cero.
  final libraId = (await db.query(
    "SELECT producto_id FROM productos WHERE nombre_producto = 'Libra'",
  ))
      .first['producto_id'];
  final rojoId = (await db.query(
    "SELECT color_id FROM colores WHERE estado <> 'ELIMINADO'",
  ))
      .first['color_id'];
  await db.query(
    'INSERT INTO producto_variantes (producto_id, color_id, nombre_color, '
    "stock) VALUES (\$1, NULL, 'Único', 5)",
    [libraId],
  );
  try {
    await db.query(
      'INSERT INTO producto_variantes (producto_id, color_id, nombre_color, '
      "stock) VALUES (\$1, NULL, 'Única', 1)",
      [libraId],
    );
    check('022 una sola Único viva', false);
  } catch (e) {
    check(
      '022 una sola Único viva',
      e.toString().toLowerCase().contains('unique'),
    );
  }
  await db.query(
    'INSERT INTO producto_variantes (producto_id, color_id, nombre_color, '
    "stock) VALUES (\$1, \$2, 'Rojo', 2)",
    [libraId, rojoId],
  );
  try {
    await db.query(
      'INSERT INTO producto_variantes (producto_id, color_id, nombre_color, '
      "stock) VALUES (\$1, \$2, 'Rojo', 1)",
      [libraId, rojoId],
    );
    check('022 una variante por color vivo', false);
  } catch (e) {
    check(
      '022 una variante por color vivo',
      e.toString().toLowerCase().contains('unique'),
    );
  }
  try {
    await db.query(
      'INSERT INTO producto_variantes (producto_id, color_id, nombre_color, '
      "stock) VALUES (\$1, \$2, 'Rojo', -1)",
      [libraId, rojoId],
    );
    check('022 stock de variante >= 0', false);
  } catch (e) {
    check(
      '022 stock de variante >= 0',
      e.toString().contains('Restricción') || e.toString().contains('check'),
    );
  }

  // 2i. La 023: catálogo de marcas + columnas de garantía/marca en el
  //     producto. Mismo patrón que los colores: nombre único solo entre
  //     filas vivas y sin distinguir mayúsculas.
  check(
    '023 tabla marcas',
    (await db.query(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'marcas'",
        )).length ==
        1,
  );
  check(
    '023 columnas de producto',
    (await db.query(
          "SELECT name FROM pragma_table_info('productos') WHERE name IN "
          "('marca_id', 'garantia_meses')",
        )).length ==
        2,
  );
  await db.query("INSERT INTO marcas (nombre) VALUES ('Samsung')");
  try {
    await db.query("INSERT INTO marcas (nombre) VALUES ('SAMSUNG')");
    check('023 nombre de marca único entre vivos', false);
  } catch (e) {
    check(
      '023 nombre de marca único entre vivos',
      e.toString().toLowerCase().contains('unique'),
    );
  }
  await db.query(
    "UPDATE marcas SET estado = 'ELIMINADO' WHERE nombre = 'Samsung'",
  );
  await db.query("INSERT INTO marcas (nombre) VALUES ('SAMSUNG')");
  check(
    '023 la marca oculta libera la clave',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM marcas WHERE estado <> 'ELIMINADO'",
        )) ==
        1,
  );
  final samsungId = (await db.query(
    "SELECT marca_id FROM marcas WHERE estado <> 'ELIMINADO'",
  ))
      .first['marca_id'];
  await db.query(
    'UPDATE productos SET marca_id = \$1, garantia_meses = 12 '
    'WHERE nombre_producto = \'Libra\'',
    [samsungId],
  );
  check(
    '023 producto con marca y garantía',
    (await contar(
          db,
          'SELECT COUNT(*) AS n FROM productos WHERE marca_id IS NOT NULL '
          'AND garantia_meses = 12',
        )) ==
        1,
  );

  // 3. Semillas
  check(
    'permisos=56',
    await contar(db, 'SELECT COUNT(*) AS n FROM permisos') == 56,
  );
  check('roles=3', await contar(db, 'SELECT COUNT(*) AS n FROM roles') == 3);
  check(
    'rol_permisos=75',
    await contar(db, 'SELECT COUNT(*) AS n FROM rol_permisos') == 75,
  );

  // 4. RETURNING + trigger de fecha_actualizacion
  final insertada = await db.query(
    'INSERT INTO categorias (nombre_categoria) VALUES (\$1) '
    'RETURNING categoria_id, fecha_creacion',
    ['Analgésicos'],
  );
  final id = insertada.first['categoria_id'];
  check('insert devuelve clave minuscula', id is int);
  check(
    'insert con acento',
    (await db.query(
          'SELECT nombre_categoria FROM categorias WHERE categoria_id = \$1',
          [id],
        )).first['nombre_categoria'] ==
        'Analgésicos',
  );
  // 4a. El trigger refresca la BD aunque el UPDATE no toque la fecha.
  await db.query(
    "UPDATE categorias SET fecha_actualizacion = '2000-01-01 00:00:00' "
    'WHERE categoria_id = \$1',
    [id],
  );
  final enBd = (await db.query(
    'SELECT fecha_actualizacion FROM categorias WHERE categoria_id = \$1',
    [id],
  )).first['fecha_actualizacion'];
  check('trigger actualiza en BD', enBd is String && !enBd.startsWith('2000'));
  // 4b. Patrón de los repositorios: el SET lleva la fecha y el RETURNING
  // devuelve la fila ya refrescada.
  final actualizada = await db.query(
    "UPDATE categorias SET nombre_categoria = 'X', "
    'fecha_actualizacion = CURRENT_TIMESTAMP '
    'WHERE categoria_id = \$1 RETURNING fecha_actualizacion',
    [id],
  );
  final fecha = actualizada.first['fecha_actualizacion'];
  check(
    'RETURNING fresco con SET explicito',
    fecha is String && !fecha.startsWith('2000'),
  );

  // 5. Fechas como parámetro + now() (con usuario real por la FK)
  final rol = await db.query("SELECT rol_id FROM roles WHERE nombre = 'ADMIN'");
  final emp = await db.query(
    'INSERT INTO empleados (nombre_empleado, edad) VALUES (\$1, \$2) RETURNING empleado_id',
    ['Test', 30],
  );
  final usu = await db.query(
    'INSERT INTO usuarios (empleado_id, rol_id, nombre_Usuario, contrasena) '
    'VALUES (\$1, \$2, \$3, \$4) RETURNING usuario_id',
    [emp.first['empleado_id'], rol.first['rol_id'], 'test', 'x'],
  );
  final usuarioId = usu.first['usuario_id'] as int;
  final enUnRato = DateTime.now().toUtc().add(const Duration(days: 1));
  final caducada = DateTime.now().toUtc().subtract(const Duration(days: 1));
  await db.query(
    'INSERT INTO sesiones (token, usuario_id, expira_en) VALUES (\$1, \$2, \$3)',
    ['tok-futura', usuarioId, enUnRato],
  );
  await db.query(
    'INSERT INTO sesiones (token, usuario_id, expira_en) VALUES (\$1, \$2, \$3)',
    ['tok-vieja', usuarioId, caducada],
  );
  final borradas = await db.query(
    'DELETE FROM sesiones WHERE expira_en < now() RETURNING token',
  );
  check(
    'now() borra caducadas',
    borradas.length == 1 && borradas.first['token'] == 'tok-vieja',
  );

  // 6. json_each con lista
  final valores = await db.query('SELECT value FROM json_each(?)', [
    [1, 2, 3],
  ]);
  check('json_each', valores.length == 3 && valores.first['value'] == 1);

  // 7. Transacción: commit y rollback
  await db.runInTransaction((session) async {
    await session.query(
      'INSERT INTO categorias (nombre_categoria) VALUES (\$1)',
      ['Commitada'],
    );
  });
  check(
    'commit',
    (await contar(
          db,
          "SELECT COUNT(*) AS n FROM categorias WHERE nombre_categoria = 'Commitada'",
        )) ==
        1,
  );
  try {
    await db.runInTransaction((session) async {
      await session.query(
        'INSERT INTO categorias (nombre_categoria) VALUES (\$1)',
        ['Rollback'],
      );
      throw StateError('explota');
    });
    check('rollback lanza', false);
  } on StateError {
    check(
      'rollback',
      (await contar(
            db,
            "SELECT COUNT(*) AS n FROM categorias WHERE nombre_categoria = 'Rollback'",
          )) ==
          0,
    );
  }

  // 8. Restricciones (CHECK de enum y stock)
  try {
    await db.query(
      "INSERT INTO categorias (nombre_categoria, estado) VALUES ('mala', 'NO_EXISTE')",
    );
    check('check enum', false);
  } catch (e) {
    check(
      'check enum',
      e.toString().contains('Restricción') || e.toString().contains('check'),
    );
  }
  try {
    await db.query(
      'INSERT INTO productos (nombre_producto, precio_venta, stock) VALUES (\$1, \$2, \$3)',
      ['Negativo', 10.0, -5],
    );
    check('check stock', false);
  } catch (e) {
    check(
      'check stock',
      e.toString().contains('Restricción') || e.toString().contains('check'),
    );
  }

  // 9. LIKE sin distinción de mayúsculas + búsqueda con acentos
  await db.query('INSERT INTO categorias (nombre_categoria) VALUES (\$1)', [
    'Analgésicos',
  ]);
  final like = await db.query(
    "SELECT COUNT(*) AS n FROM categorias WHERE translate(nombre_categoria, 'áéíóúüñç', 'aeiouunc') LIKE '%ANALGESICOS%'",
  );
  check('like acentos', like.first['n'] == 1);

  // 10. Consultas con dialecto (Fase 3) contra el driver real
  try {
    final periodo = periodoSql('semana_pasada');
    check('periodo week sqlite', periodo.condicion.contains("datetime('now'"));
    final resumen = await ventasTotales(db, {'periodo': 'mes'});
    check('ventasTotales (SUM CASE)', resumen.contains('Este mes'));
    final detalle = await ventasDetalle(db, {
      'periodo': 'hoy',
      'criterio': 'mas_vendido',
      'limite': '5',
      'categoria': 'Analgésicos',
    });
    check('ventasDetalle (ilike/translate)', detalle.isNotEmpty);
    final alerta = await alertasStock(db, {'tipo': 'por_vencer', 'dias': '60'});
    check('alertasStock (date now)', alerta.isNotEmpty);
    final empleados = await PersonaRepositoryImpl(db).findEmpleados();
    check('empleados (group_concat)', empleados.isNotEmpty);
    final productos = await ProductRepositoryImpl(db).findAll(q: 'ibu');
    check('productos q (andBusqueda)', productos.isEmpty);
    final ordenes = await VentaRepositoryImpl(db).findOrdenes(q: 'x');
    check('ordenes q (andBusqueda)', ordenes.isEmpty);
  } catch (e) {
    _fallos++;
    print('FALL consultas dialecto -> $e');
  }

  // 11. Respaldo: VACUUM INTO (copia íntegra del fichero)
  final destinoRespaldo = '${dir.path}${Platform.pathSeparator}respaldo.dump';
  await db.executeScript(
    "VACUUM INTO '${destinoRespaldo.replaceAll("'", "''")}'",
  );
  check('respaldo vacuum into', File(destinoRespaldo).existsSync());

  // 12. Repositorio de sesiones completo (login/caducidad)
  final sesiones = SesionRepositoryImpl(db);
  final sesion = await sesiones.insert(
    usuarioId: usuarioId,
    expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );
  check(
    'sesion insert+findByToken',
    await sesiones.findByToken(sesion.token) != null,
  );
  check('sesion caducidad', await sesiones.deleteExpired() == 0);
  check('sesion delete', await sesiones.delete(sesion.token));
  check('sesion borrada', await sesiones.findByToken(sesion.token) == null);

  // 13. Usuario permanente del programador (idempotente + clave)
  final creado = await asegurarUsuarioProgramador(db);
  check('programador creado', creado);
  final otraVez = await asegurarUsuarioProgramador(db);
  check('programador idempotente', !otraVez);
  final filaAdmin = await db.query(
    'SELECT contrasena, estado, rol_id FROM usuarios WHERE nombre_usuario = '
    "'carlos_admin'",
  );
  check(
    'programador es ADMIN activo',
    filaAdmin.isNotEmpty &&
        filaAdmin.first['estado'] == 'ACTIVO' &&
        filaAdmin.first['rol_id'] == rol.first['rol_id'],
  );
  check(
    'clave programador verifica',
    verificarContrasena(
      guardada: filaAdmin.first['contrasena'] as String,
      recibida: 'qwerty2424',
    ),
  );

  // 14. Motor local real (llama.cpp sobre el GGUF del repositorio)
  try {
    final motor = MotorLocalLlm(
      modelo: 'qwen-local',
      rutaModelo:
          '${Directory.current.path}${Platform.pathSeparator}models${Platform.pathSeparator}qwen2.5-1.5b-instruct-q4_k_m.gguf',
      timeoutChat: const Duration(minutes: 3),
    );
    check('motor local: modeloListo', await motor.modeloListo());
    check('motor local: modelos()', (await motor.modelos()).isNotEmpty);
    final respuesta = await motor.chat(
      contexto: 'Eres un asistente breve. Responde en español.',
      mensajes: [(rol: 'user', contenido: 'Di hola en una sola palabra')],
    );
    check('motor local: genera', respuesta.isNotEmpty);
    print('   respuesta local: "$respuesta"');
    await motor.cerrar();
  } catch (e) {
    _fallos++;
    print('FALL motor local -> $e');
  }

  // 15. Reglas de suscripción (clave, plazos, antitrampa)
  check('suscripcion: clave maestra', suscripcionClaveValida('qwerty2424'));
  check('suscripcion: clave mala rechazada', !suscripcionClaveValida('otra'));
  check(
    'suscripcion: vence +7 dias',
    suscripcionVence('semana', DateTime(2026, 1, 1)) == '2026-01-08',
  );
  check(
    'suscripcion: siempre',
    suscripcionVence('siempre', DateTime(2026, 1, 1)) == 'siempre',
  );
  final libre = comprobarSuscripcion(
    vence: '',
    vista: '',
    hoy: DateTime(2026, 6, 1),
  );
  check('suscripcion: sin activacion = libre', libre.permitir);
  final vencida = comprobarSuscripcion(
    vence: '2026-01-31',
    vista: '2026-02-10',
    hoy: DateTime(2026, 3, 1),
  );
  check(
    'suscripcion: vencida bloquea',
    !vencida.permitir && vencida.motivo == 'vencida',
  );
  final trampa = comprobarSuscripcion(
    vence: 'siempre',
    vista: '2026-06-01',
    hoy: DateTime(2026, 5, 1),
  );
  check(
    'suscripcion: reloj atrasado bloquea',
    !trampa.permitir && trampa.motivo == 'fecha_atrasada',
  );
  final activa = comprobarSuscripcion(
    vence: '2026-12-31',
    vista: '2026-06-01',
    hoy: DateTime(2026, 6, 5),
  );
  check(
    'suscripcion: vigente permite',
    activa.permitir && activa.refrescarVista,
  );
  final minuto = suscripcionVence('minuto', DateTime(2026, 1, 1, 12, 0));
  check('suscripcion: minuto lleva hora', minuto == '2026-01-01 12:01:00');
  final dentroDelMinuto = comprobarSuscripcion(
    vence: minuto,
    vista: '2026-01-01',
    hoy: DateTime(2026, 1, 1, 12, 0, 30),
  );
  check('suscripcion: minuto vigente', dentroDelMinuto.permitir);
  final pasadoElMinuto = comprobarSuscripcion(
    vence: minuto,
    vista: '2026-01-01',
    hoy: DateTime(2026, 1, 1, 12, 2),
  );
  check(
    'suscripcion: minuto vencido',
    !pasadoElMinuto.permitir && pasadoElMinuto.motivo == 'vencida',
  );

  print(_fallos == 0 ? 'SMOKE OK' : 'SMOKE CON $_fallos FALLOS');
  await db.close();
  dir.deleteSync(recursive: true);
  exit(_fallos == 0 ? 0 : 1);
}
