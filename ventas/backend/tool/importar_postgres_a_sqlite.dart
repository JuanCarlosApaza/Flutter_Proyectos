// Importa una base PostgreSQL existente a un fichero SQLite nuevo.
//
// Es el paso único por cliente para quien pasa de la versión escritorio
// (PostgreSQL) a la APK offline (SQLite): vuelca todas las tablas con sus
// datos tal cual, respetando las claves foráneas y los IDs originales.
//
// Uso (desde `backend/`; lee `DB_*` del entorno o del `.env`, igual que el
// servidor):
//
//   dart run tool/importar_postgres_a_sqlite.dart C:\ruta\ventas.db
//
// El fichero de destino no debe existir (o estar vacío): se le aplica el
// esquema SQLite y se le copian los datos.
import 'dart:io';

import 'package:ventas_backend/src/core/config/app_config.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:postgres/postgres.dart';

/// Orden de volcado: cada tabla aparece después de las que referencia
/// (SQLite comprueba las claves foráneas fila a fila).
const List<String> _tablas = [
  'categorias',
  'presentaciones',
  'proveedores',
  'empleados',
  'clientes',
  'roles',
  'permisos',
  'rol_permisos',
  'usuarios',
  'productos',
  'ordenes_pedidos',
  'pagos',
  'facturas',
  'detalles_ordenes_pedidos',
  'cotizaciones',
  'detalles_cotizaciones',
  'ajustes',
  'auditoria',
  'sesiones',
];

/// Valor de PostgreSQL a parámetro de SQLite: fechas a UTC (salvo las de
/// medianoche, que son columnas `DATE` y se conservan como fecha), el resto
/// pasa tal cual (el driver ya normaliza bool y DateTime).
Object? _adaptar(Object? valor) {
  if (valor is! DateTime) return valor;
  final esMedianoche =
      valor.hour == 0 &&
      valor.minute == 0 &&
      valor.second == 0 &&
      valor.millisecond == 0;
  return esMedianoche ? valor : valor.toUtc();
}

Future<void> main(List<String> argumentos) async {
  if (argumentos.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/importar_postgres_a_sqlite.dart <destino.db>',
    );
    exit(2);
  }
  final destino = File(argumentos.first);
  if (destino.existsSync() && destino.lengthSync() > 0) {
    stderr.writeln(
      'El destino ya existe y no está vacío: ${destino.path}\n'
      'Bórralo (o usa otra ruta) para importar desde cero.',
    );
    exit(2);
  }

  final config = AppConfig.load();
  stdout.writeln(
    'Origen PostgreSQL: ${config.db.host}:${config.db.port}/${config.db.name}',
  );

  final origen = await Connection.open(
    Endpoint(
      host: config.db.host,
      port: config.db.port,
      database: config.db.name,
      username: config.db.user,
      password: config.db.password,
    ),
    settings: PoolSettings(
      connectTimeout: const Duration(seconds: 10),
      sslMode: config.db.sslMode == 'require'
          ? SslMode.require
          : SslMode.disable,
    ),
  );

  final sqlite = SqliteDatabase(destino.path);
  final aplicadas = await Migrator(sqlite, engine: 'sqlite').migrate();
  stdout.writeln('Esquema SQLite aplicado: ${aplicadas.join(', ')}');

  var total = 0;
  await sqlite.runInTransaction((session) async {
    for (final tabla in _tablas) {
      // Filas por tandas: la primera columna de cada tabla es su clave, así
      // que `ORDER BY 1` deja el orden estable para paginar con OFFSET.
      var offset = 0;
      var filasTabla = 0;
      while (true) {
        final resultados = await origen.execute(
          Sql('SELECT * FROM $tabla ORDER BY 1 LIMIT 5000 OFFSET $offset'),
        );
        if (resultados.isEmpty) break;

        final columnas = resultados.first.toColumnMap().keys.toList();
        final marcas = [for (var i = 1; i <= columnas.length; i++) '\$$i']
            .join(', ');
        final insercion =
            'INSERT INTO $tabla (${columnas.join(', ')}) VALUES ($marcas)';

        for (final fila in resultados) {
          final valores = fila.toColumnMap();
          await session.query(insercion, [
            for (final columna in columnas) _adaptar(valores[columna]),
          ]);
        }
        filasTabla += resultados.length;
        offset += resultados.length;
        if (resultados.length < 5000) break;
      }
      total += filasTabla;
      stdout.writeln('  $tabla: $filasTabla filas');
    }
  });

  await origen.close();
  await sqlite.close();

  stdout.writeln('Listo: $total filas importadas en ${destino.path}');
}
