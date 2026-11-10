import 'package:farmacia_backend/src/core/config/app_config.dart';
import 'package:farmacia_backend/src/data/database/database.dart';

/// Peek rápido del esquema y datos (para diseñar nuevas funciones del
/// catálogo): `dart run tool/explorar_esquema.dart`.
Future<void> main() async {
  final config = AppConfig.load();
  final db = PostgresDatabase(config.db);

  Future<void> ver(String titulo, String sql) async {
    // ignore: avoid_print
    print('\n== $titulo ==');
    try {
      final filas = await db.query(sql);
      for (final fila in filas) {
        // ignore: avoid_print
        print(fila);
      }
    } catch (e) {
      // ignore: avoid_print
      print('ERROR: $e');
    }
  }

  await ver('usuarios', 'SELECT u.nombre_usuario, r.nombre AS rol, '
      'u.estado::text AS estado FROM usuarios u '
      'LEFT JOIN roles r ON r.rol_id = u.rol_id '
      'ORDER BY u.nombre_usuario LIMIT 8');
  await ver('metodos de pago',
      'SELECT DISTINCT metodo_pago FROM pagos ORDER BY 1');
  await ver('pagos recientes',
      'SELECT metodo_pago, monto, fecha_creacion FROM pagos '
      'ORDER BY fecha_creacion DESC LIMIT 5');
  await ver('presentaciones',
      'SELECT * FROM presentaciones ORDER BY 1 LIMIT 10');
  await ver('roles',
      'SELECT * FROM roles ORDER BY 1 LIMIT 10');
  await ver('ajustes', 'SELECT * FROM ajustes LIMIT 15');
  await ver('columnas usuarios',
      "SELECT column_name FROM information_schema.columns "
      "WHERE table_name = 'usuarios' ORDER BY ordinal_position");
  await ver('columnas roles',
      "SELECT column_name FROM information_schema.columns "
      "WHERE table_name = 'roles' ORDER BY ordinal_position");

  await db.close();
}
