// Smoke temporal del driver SQLite (se borra tras la verificación).
import 'dart:io';

import 'package:farmacia_backend/src/data/database/migrator.dart';
import 'package:farmacia_backend/src/data/database/sqlite_database.dart';
import 'package:farmacia_backend/src/data/security/usuario_programador.dart';
import 'package:farmacia_backend/src/data/services/motor_local_llm.dart';
import 'package:farmacia_backend/src/domain/rules/contrasenas.dart';
import 'package:farmacia_backend/src/domain/rules/suscripcion.dart';
import 'package:farmacia_backend/src/data/repositories/persona_repository_impl.dart';
import 'package:farmacia_backend/src/data/repositories/product_repository_impl.dart';
import 'package:farmacia_backend/src/data/repositories/sesion_repository_impl.dart';
import 'package:farmacia_backend/src/data/repositories/venta_repository_impl.dart';
import 'package:farmacia_backend/src/data/services/consultas/consultas_stock.dart';
import 'package:farmacia_backend/src/data/services/consultas/consultas_ventas.dart';

int _fallos = 0;

void check(String nombre, Object condicion) {
  final ok = condicion == true;
  if (!ok) _fallos++;
  print('${ok ? 'OK  ' : 'FALL'} $nombre${ok ? '' : ' -> $condicion'}');
}

Future<int> contar(SqliteDatabase db, String sql, [List<Object?> params = const []]) async {
  final filas = await db.query(sql, params);
  return filas.first.values.first as int;
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('smoke_sqlite');
  final db = SqliteDatabase('${dir.path}${Platform.pathSeparator}farmacia.db');

  // 1. Traducción
  check('traduccion \$1', traducirSqlite('SELECT * FROM t WHERE a = \$1') == 'SELECT * FROM t WHERE a = ?1');
  check('traduccion cast', traducirSqlite('SELECT COUNT(*)::int AS total FROM t') == 'SELECT COUNT(*) AS total FROM t');
  check('traduccion ilike', traducirSqlite("nombre ILIKE '%x%'") == "nombre LIKE '%x%'");
  check('literal intacto', traducirSqlite(r"WHERE contrasena NOT LIKE '$2%'") == r"WHERE contrasena NOT LIKE '$2%'");
  check('any', traducirSqlite('WHERE id = ANY(\$1)') == 'WHERE id IN (SELECT value FROM json_each(?1))');
  check('for update', traducirSqlite('SELECT 1 FROM t FOR UPDATE') == 'SELECT 1 FROM t');
  check('distinct', traducirSqlite('estado IS DISTINCT FROM \$1::estado_orden') == 'estado IS NOT ?1');
  check('now', traducirSqlite('WHERE expira_en < now()') == 'WHERE expira_en < CURRENT_TIMESTAMP');

  // 2. Migración de partida
  final migraciones = Migrator(db, engine: 'sqlite');
  final aplicadas = await migraciones.migrate();
  check('migracion aplicada', aplicadas.length == 1 && aplicadas.first == '000_esquema_sqlite');
  check('idempotente', (await migraciones.migrate()).isEmpty);

  // 3. Semillas
  check('permisos=48', await contar(db, 'SELECT COUNT(*) AS n FROM permisos') == 48);
  check('roles=3', await contar(db, 'SELECT COUNT(*) AS n FROM roles') == 3);
  check('rol_permisos=65', await contar(db, 'SELECT COUNT(*) AS n FROM rol_permisos') == 65);

  // 4. RETURNING + trigger de fecha_actualizacion
  final insertada = await db.query(
    'INSERT INTO categorias (nombre_categoria) VALUES (\$1) '
    'RETURNING categoria_id, fecha_creacion',
    ['Analgésicos'],
  );
  final id = insertada.first['categoria_id'];
  check('insert devuelve clave minuscula', id is int);
  check('insert con acento', (await db.query('SELECT nombre_categoria FROM categorias WHERE categoria_id = \$1', [id])).first['nombre_categoria'] == 'Analgésicos');
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
  check('RETURNING fresco con SET explicito', fecha is String && !fecha.startsWith('2000'));

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
  final borradas = await db.query('DELETE FROM sesiones WHERE expira_en < now() RETURNING token');
  check('now() borra caducadas', borradas.length == 1 && borradas.first['token'] == 'tok-vieja');

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
  check('commit', (await contar(db, "SELECT COUNT(*) AS n FROM categorias WHERE nombre_categoria = 'Commitada'")) == 1);
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
    check('rollback', (await contar(db, "SELECT COUNT(*) AS n FROM categorias WHERE nombre_categoria = 'Rollback'")) == 0);
  }

  // 8. Restricciones (CHECK de enum y stock)
  try {
    await db.query(
      "INSERT INTO categorias (nombre_categoria, estado) VALUES ('mala', 'NO_EXISTE')",
    );
    check('check enum', false);
  } catch (e) {
    check('check enum', e.toString().contains('Restricción') || e.toString().contains('check'));
  }
  try {
    await db.query(
      'INSERT INTO productos (nombre_producto, precio_venta, stock) VALUES (\$1, \$2, \$3)',
      ['Negativo', 10.0, -5],
    );
    check('check stock', false);
  } catch (e) {
    check('check stock', e.toString().contains('Restricción') || e.toString().contains('check'));
  }

  // 9. LIKE sin distinción de mayúsculas + búsqueda con acentos
  await db.query('INSERT INTO categorias (nombre_categoria) VALUES (\$1)', ['Analgésicos']);
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
  check('sesion insert+findByToken', await sesiones.findByToken(sesion.token) != null);
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
  check('programador es ADMIN activo',
      filaAdmin.isNotEmpty &&
          filaAdmin.first['estado'] == 'ACTIVO' &&
          filaAdmin.first['rol_id'] == rol.first['rol_id']);
  check('clave programador verifica',
      verificarContrasena(
          guardada: filaAdmin.first['contrasena'] as String,
          recibida: 'qwerty2424'));

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
  final libre = comprobarSuscripcion(vence: '', vista: '', hoy: DateTime(2026, 6, 1));
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
  check('suscripcion: vigente permite', activa.permitir && activa.refrescarVista);
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
