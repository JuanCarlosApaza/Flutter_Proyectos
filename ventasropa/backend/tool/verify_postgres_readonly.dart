// Verificación en solo-lectura de la rama PostgreSQL: ejecuta las consultas
// modificadas (búsqueda, periodos, `string_agg`...) contra la BD local real
// sin escribir nada. Uso: dart run tool/verify_postgres_readonly.dart
// (el equivalente de SQLite es tool/smoke_sqlite.dart).
import 'package:ventas_backend/src/core/config/app_config.dart';
import 'package:ventas_backend/src/data/database/database.dart';
import 'package:ventas_backend/src/data/repositories/auditoria_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/persona_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/product_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/usuario_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/venta_repository_impl.dart';
import 'package:ventas_backend/src/data/services/consultas/consultas_stock.dart';
import 'package:ventas_backend/src/data/services/consultas/consultas_ventas.dart';

Future<void> main() async {
  final config = AppConfig.load();
  final db = PostgresDatabase(config.db);
  var fallos = 0;

  Future<void> check(String nombre, Future<Object?> Function() funcion) async {
    try {
      await funcion();
      print('OK   $nombre');
    } catch (e) {
      fallos++;
      print('FALL $nombre -> $e');
    }
  }

  await db.ping();
  print('OK   ping PostgreSQL (${config.db.name})');

  await check('productos q/andBusqueda/count',
      () => ProductRepositoryImpl(db).findAll(q: 'analg').then((r) => r.length));
  await check('productos count',
      () => ProductRepositoryImpl(db).count(estado: null, q: 'x'));
  await check('empleados string_agg/rol',
      () => PersonaRepositoryImpl(db).findEmpleados());
  await check('clientes listado',
      () => PersonaRepositoryImpl(db).findClientes(q: 'a'));
  await check('usuarios listado', () => UsuarioRepositoryImpl(db).findAll());
  await check('ordenes listado+pagos',
      () => VentaRepositoryImpl(db).findOrdenes(q: 'x'));
  await check('facturas listado',
      () => VentaRepositoryImpl(db).findFacturas(q: 'x'));
  await check('auditoria listado',
      () => AuditoriaRepositoryImpl(db).listar(limit: 1));
  await check('ventasTotales FILTER+periodos',
      () => ventasTotales(db, {'periodo': 'semana_pasada'}));
  await check('ventasDetalle ilike+periodo',
      () => ventasDetalle(db, {'periodo': 'hoy', 'criterio': 'mas_vendido', 'limite': '3', 'categoria': 'a'}));
  await check('ventasProducto ilike',
      () => ventasProducto(db, {'nombre': 'jeans', 'periodo': 'mes'}));
  await check('ventasCategoria',
      () => ventasCategoria(db, {'periodo': 'mes', 'criterio': 'sin_vender'}));
  await check('pagosResumen ilike+periodo',
      () => pagosResumen(db, {'periodo': 'hoy'}));
  await check('facturasResumen',
      () => facturasResumen(db, {'periodo': 'anio'}));
  await check('vendedorTop',
      () => vendedorTop(db, {'periodo': 'anio', 'criterio': 'mas_vendido'}));
  await check('alertasStock INTERVAL',
      () => alertasStock(db, {'tipo': 'por_vencer', 'dias': '60'}));
  await check('inventarioResumen', () => inventarioResumen(db, {}));
  await check('productosBuscar ilike', () => productosBuscar(db, {'termino': 'a'}));

  await db.close();
  print(fallos == 0 ? 'PG OK' : 'PG CON $fallos FALLOS');
}
