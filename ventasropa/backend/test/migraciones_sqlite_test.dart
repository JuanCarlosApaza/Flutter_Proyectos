import 'dart:io';

import 'package:test/test.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';

/// Migraciones compartidas aplicadas sobre una base SQLite recién creada.
///
/// El esquema vigente **no** tiene precio por variante: la `019` creó la
/// columna `producto_variantes.precio` y la `020_quitar_precio_por_variante`
/// la retiró para dejar un único precio por producto (`productos.precio_
/// venta`). Aquí se comprueba justo eso, porque SQLite es el único motor al
/// que esta pareja de migraciones llega sin más cobertura.
void main() {
  late Directory dir;
  late SqliteDatabase db;
  late Migrator migrator;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('migraciones_sqlite');
    db = SqliteDatabase('${dir.path}${Platform.pathSeparator}ventas.db');
    migrator = Migrator(db, engine: 'sqlite');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// Ejecuta un INSERT con RETURNING y devuelve esa columna.
  Future<Object?> insertar(String sql, List<Object?> params) async {
    final filas = await db.query(sql, params);
    return filas.first.values.last;
  }

  test('la 020 deja la variante sin precio propio y es idempotente', () async {
    final aplicadas = await migrator.migrate();

    expect(aplicadas, contains('019_precio_por_variante'));
    expect(aplicadas, contains('020_quitar_precio_por_variante'));

    final columnas = [
      for (final fila in await db.query(
        "SELECT name FROM pragma_table_info('producto_variantes')",
      ))
        fila['name'],
    ];
    expect(columnas, isNot(contains('precio')));
    expect(columnas, contains('stock'));
    expect(columnas, contains('codigo'));

    // Segunda pasada: no hay migraciones pendientes.
    expect(await migrator.migrate(), isEmpty);
  });

  test('la 021 añade el módulo Reportes con sus 4 permisos (solo ADMIN)', () async {
    final aplicadas = await migrator.migrate();

    expect(aplicadas, contains('021_permisos_reportes'));

    final permisos = [
      for (final fila in await db.query(
        "SELECT Modulo || '.' || Accion AS clave FROM Permisos "
        "WHERE Modulo = 'reportes' ORDER BY Accion",
      ))
        fila['clave'],
    ];
    expect(permisos, [
      'reportes.crear',
      'reportes.editar',
      'reportes.eliminar',
      'reportes.ver',
    ]);

    // Ningún rol de sistema se queda con permisos que no le corresponden:
    // la matriz de Roles los podrá conceder, pero no nacen dados.
    final conPermiso = [
      for (final fila in await db.query(
        'SELECT DISTINCT r.Nombre AS rol FROM Rol_Permisos rp '
        'JOIN Roles r ON r.Rol_ID = rp.Rol_ID '
        'JOIN Permisos p ON p.Permiso_ID = rp.Permiso_ID '
        "WHERE p.Modulo = 'reportes' ORDER BY r.Nombre",
      ))
        fila['rol'],
    ];
    expect(conPermiso, ['ADMIN']);

    // Segunda pasada: la migración no se vuelve a aplicar.
    expect(await migrator.migrate(), isEmpty);
  });

  test('la 022 añade email y NIT a proveedores', () async {
    final aplicadas = await migrator.migrate();

    expect(aplicadas, contains('022_proveedores_email_nit'));

    final columnas = [
      for (final fila in await db.query(
        "SELECT name FROM pragma_table_info('proveedores')",
      ))
        fila['name'],
    ];
    expect(columnas, contains('email'));
    expect(columnas, contains('nit'));

    // Las dos columnas son opcionales: se puede dar de alta un proveedor sin
    // ellas y escribirlas después.
    final id = await insertar(
      'INSERT INTO proveedores (nombre_proveedor) VALUES (\$1) '
      'RETURNING proveedor_id',
      ['Distribuidora Norte'],
    );
    expect(
      await db.query(
        'UPDATE proveedores SET email = \$1, nit = \$2 '
        'WHERE proveedor_id = \$3 RETURNING email',
        ['contacto@norte.com.bo', '1023456027', id],
      ),
      hasLength(1),
    );

    // Segunda pasada: no hay migraciones pendientes.
    expect(await migrator.migrate(), isEmpty);
  });

  test('una variante sigue insertándose con el precio en el producto', () async {
    await migrator.migrate();

    final producto = await insertar(
      'INSERT INTO productos (nombre_producto, precio_venta, stock) '
      'VALUES (\$1, \$2, \$3) RETURNING producto_id',
      ['Pantalón mezclillo', 89.9, 10],
    );
    final talla = await insertar(
      'INSERT INTO tallas (nombre) VALUES (\$1) RETURNING talla_id',
      ['M'],
    );
    final color = await insertar(
      'INSERT INTO colores (nombre) VALUES (\$1) RETURNING color_id',
      ['Negro'],
    );
    final variante = await insertar(
      'INSERT INTO producto_variantes '
      '(producto_id, talla_id, color_id, stock, codigo) '
      'VALUES (\$1, \$2, \$3, \$4, \$5) '
      'ON CONFLICT (producto_id, talla_id, color_id) DO NOTHING '
      'RETURNING stock',
      [producto, talla, color, 5, null],
    );

    expect(variante, 5);
  });
}
