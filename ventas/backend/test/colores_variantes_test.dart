import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/repositories/color_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/cotizacion_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/marca_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/product_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/venta_repository_impl.dart';
import 'package:ventas_backend/src/domain/entities/color.dart';
import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/entities/venta.dart';
import 'package:ventas_backend/src/domain/usecases/color_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/cotizacion_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/marca_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/producto_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/unidad_medida_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/venta_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

// Colores (catálogo), variantes de producto y su uso en ventas y
// cotizaciones: reglas de la migración 022 **contra SQLite en memoria**
// (mismas migraciones que la APK), porque aquí se comprueba el SQL real
// (índices únicos parciales, reescritura de variantes, kardex y cobro).
void main() {
  late SqliteDatabase db;
  late Colores colores;
  late Productos productos;
  late Ordenes ordenes;
  late Cotizaciones cotizaciones;

  setUp(() async {
    db = SqliteDatabase(':memory:');
    await Migrator(db, engine: 'sqlite').migrate();
    colores = Colores(repository: ColorRepositoryImpl(db));
    // Igual que en `app.dart`: órdenes y cotizaciones trabajan contra el
    // repositorio de productos (que adjunta las variantes), no contra el
    // caso de uso de productos.
    final productosRepo = ProductRepositoryImpl(db);
    productos = Productos(
      repository: productosRepo,
      unidades: Unidades(repository: FakeUnidadMedidaRepository.semilla()),
      marcas: Marcas(repository: MarcaRepositoryImpl(db)),
    );
    ordenes = Ordenes(
      repository: VentaRepositoryImpl(db),
      productos: productosRepo,
    );
    cotizaciones = Cotizaciones(
      repository: CotizacionRepositoryImpl(db),
      productos: productosRepo,
    );
  });

  tearDown(() async => db.close());

  /// Clon de producto con algún campo cambiado (la entidad no tiene
  /// `copyWith`); solo los campos de [campos] se escriben en la BD.
  Product clonar(Product p, {double? stock}) => Product(
    id: p.id,
    nombre: p.nombre,
    codigo: p.codigo,
    imagen: p.imagen,
    descripcion: p.descripcion,
    unidad: p.unidad,
    precioVenta: p.precioVenta,
    precioCompra: p.precioCompra,
    precioRebaja: p.precioRebaja,
    fechaVencimiento: p.fechaVencimiento,
    stock: stock ?? p.stock,
    stockMinimo: p.stockMinimo,
    categoriaId: p.categoriaId,
    proveedorId: p.proveedorId,
    presentacionId: p.presentacionId,
    estado: p.estado,
    version: p.version,
  );

  Matcher conCodigo(String code) =>
      isA<AppException>().having((e) => e.code, 'code', code);

  group('Catálogo de colores', () {
    test('arranca vacío y crea con muestra #RRGGBB normalizada', () async {
      expect(await colores.listar(), isEmpty);
      final rojo = await colores.crear(nombre: 'Rojo', codigoHex: 'FF0000');
      expect(rojo.id, greaterThan(0));
      expect(rojo.codigoHex, '#FF0000');
      expect(rojo.estado, 'ACTIVO');
      expect(await colores.listar(), hasLength(1));
    });

    test('muestra que no es #RRGGBB → 400 codigo_hex_invalido', () async {
      for (final mala in const ['verde', '#12345', '#GGGGGG', '00FF00FF']) {
        await expectLater(
          colores.crear(nombre: 'Mala', codigoHex: mala),
          throwsA(conCodigo('codigo_hex_invalido')),
        );
      }
      expect(await colores.listar(), isEmpty);
    });

    test('nombre corto/largo → 400 field_too_short / field_too_long', () async {
      await expectLater(
        colores.crear(nombre: 'A'),
        throwsA(conCodigo('field_too_short')),
      );
      await expectLater(
        colores.crear(nombre: 'X' * 51),
        throwsA(conCodigo('field_too_long')),
      );
    });

    test('el nombre es único entre vivos, sin distinguir caja', () async {
      await colores.crear(nombre: 'Rojo');
      await expectLater(
        colores.crear(nombre: '  rojo  '),
        throwsA(conCodigo('color_duplicado')),
      );
      // y en la edición tampoco se puede pisar otro vivo
      final azul = await colores.crear(nombre: 'Azul');
      await expectLater(
        colores.actualizar(azul.id, nombre: 'ROJO'),
        throwsA(conCodigo('color_duplicado')),
      );
    });

    test('ocultar lo saca de los listados y libera su nombre', () async {
      final rojo = await colores.crear(nombre: 'Rojo');
      await colores.eliminar(rojo.id);
      expect(await colores.listar(), isEmpty);
      expect((await colores.listar(estado: 'ELIMINADO')).single.id, rojo.id);
      // El nombre vuelve a estar disponible entre vivos (índice parcial).
      final otro = await colores.crear(nombre: 'ROJO');
      expect(otro.id, isNot(rojo.id));
    });

    test('un oculto se restaura con un PUT', () async {
      final verde = await colores.crear(nombre: 'Verde');
      await colores.eliminar(verde.id);
      final restaurado = await colores.actualizar(verde.id, estado: 'ACTIVO');
      expect(restaurado.estado, 'ACTIVO');
      expect(await colores.listar(), hasLength(1));
    });

    test('la muestra se cambia y se quita con null explícito', () async {
      final azul = await colores.crear(nombre: 'Azul', codigoHex: '#0000FF');
      final conMuestra = await colores.actualizar(
        azul.id,
        codigoHex: '00FF00',
        fijarCodigoHex: true,
      );
      expect(conMuestra.codigoHex, '#00FF00');
      final sinMuestra = await colores.actualizar(
        azul.id,
        fijarCodigoHex: true,
      );
      expect(sinMuestra.codigoHex, isNull);
    });

    test('buscar por texto y obtener por id', () async {
      await colores.crear(nombre: 'Rojo');
      await colores.crear(nombre: 'Azul');
      expect((await colores.listar(q: 'roj')).single.nombre, 'Rojo');
      expect(
        (await colores.obtener(2)).nombre,
        'Azul',
      );
      await expectLater(
        colores.obtener(999),
        throwsA(conCodigo('color_no_encontrada')),
      );
    });
  });

  group('Variantes del producto', () {
    test('sin filas de color nace la variante Único con el stock del cuerpo',
        () async {
      final p = await productos.crear(nombre: 'Pan', precioVenta: 2, stock: 8);
      expect(p.stock, 8);
      expect(p.variantes, hasLength(1));
      expect(p.variantes.single.nombreColor, 'Único');
      expect(p.variantes.single.colorId, isNull);
      expect(p.variantes.single.stock, 8);
      expect(p.variantes.single.vendible, isTrue);
    });

    test(
      'con filas el stock agregado es la suma (el stock del cuerpo se ignora) '
      'y el color falta se autocrea',
      () async {
        final rojo = await colores.crear(nombre: 'Rojo', codigoHex: '#FF0000');
        final p = await productos.crear(
          nombre: 'Camisa',
          precioVenta: 50,
          stock: 999,
          variantes: [
            VarianteEntrada(colorId: rojo.id, cantidad: 10),
            const VarianteEntrada(color: 'Azul', cantidad: 5),
          ],
        );
        expect(p.stock, 15);
        expect(
          p.variantes.map((v) => v.nombreColor),
          containsAll(['Rojo', 'Azul']),
        );
        final azul = p.variantes.singleWhere((v) => v.colorId != rojo.id);
        expect(azul.stock, 5);
        expect(azul.codigoHex, isNull);

        // «Azul» no existía: se autocreó ACTIVO; «Rojo» conserva su muestra.
        final catalogo = await colores.listar();
        expect(catalogo, hasLength(2));
        expect(
          catalogo.singleWhere((c) => c.nombre == 'Azul').estado,
          'ACTIVO',
        );
        expect(p.variantes.firstWhere((v) => v.colorId == rojo.id).codigoHex,
            '#FF0000');
      },
    );

    test('un color existente no se duplica aunque cambie la caja', () async {
      await productos.crear(
        nombre: 'Gorra',
        precioVenta: 10,
        variantes: const [VarianteEntrada(color: 'Negro', cantidad: 2)],
      );
      final p2 = await productos.crear(
        nombre: 'Bufanda',
        precioVenta: 10,
        variantes: const [VarianteEntrada(color: 'NEGRO', cantidad: 3)],
      );
      final catalogo = await colores.listar();
      expect(catalogo, hasLength(1));
      expect(p2.variantes.single.colorId, catalogo.single.id);
      expect(p2.variantes.single.nombreColor, 'Negro');
    });

    test('filas inválidas → 400 con su código y nada se escribe', () async {
      await expectLater(
        productos.crear(
          nombre: 'Falda',
          precioVenta: 10,
          variantes: const [VarianteEntrada(cantidad: 1)],
        ),
        throwsA(conCodigo('variante_invalida')),
      );
      await expectLater(
        productos.crear(
          nombre: 'Falda',
          precioVenta: 10,
          variantes: const [VarianteEntrada(colorId: 999, cantidad: 1)],
        ),
        throwsA(conCodigo('color_no_encontrada')),
      );
      await expectLater(
        productos.crear(
          nombre: 'Falda',
          precioVenta: 10,
          variantes: const [VarianteEntrada(color: 'Verde', cantidad: -1)],
        ),
        throwsA(conCodigo('valor_negativo')),
      );
      await expectLater(
        productos.crear(
          nombre: 'Falda',
          precioVenta: 10,
          variantes: const [
            VarianteEntrada(color: 'Verde', cantidad: 1),
            VarianteEntrada(color: 'VERDE', cantidad: 2),
          ],
        ),
        throwsA(conCodigo('variante_duplicada')),
      );
      expect(await productos.listar(), isEmpty);
      expect(await colores.listar(), isEmpty);
    });

    test('editar variantes reescribe: retira las que no siguen y recalcula',
        () async {
      final rojo = await colores.crear(nombre: 'Rojo');
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: [
          VarianteEntrada(colorId: rojo.id, cantidad: 10),
          const VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      final azul = p.variantes.singleWhere((v) => v.colorId != rojo.id);

      final editado = await productos.actualizar(
        p.id,
        clonar(p),
        const {'variantes'},
        variantes: [VarianteEntrada(colorId: rojo.id, cantidad: 3)],
      );
      expect(editado.stock, 3);
      expect(editado.variantes, hasLength(1));
      expect(editado.variantes.single.stock, 3);

      // La variante retirada queda como ELIMINADO (borrado lógico), no se
      // borra la fila: las líneas de venta viejas siguen apuntando a ella.
      final filas = await db.query(
        'SELECT estado FROM producto_variantes WHERE producto_id = \$1',
        [p.id],
      );
      expect(
        filas.map((r) => r['estado'] as String),
        containsAll(['ACTIVO', 'ELIMINADO']),
      );

      // El cambio de agregado es un movimiento de kardex (15 → 3).
      final mov = await db.query(
        'SELECT motivo, cantidad, stock_resultante FROM movimientos_stock '
        'WHERE producto_id = \$1',
        [p.id],
      );
      expect(mov, hasLength(1));
      expect(mov.first['motivo'], 'AJUSTE');
      expect((mov.first['cantidad'] as num).toDouble(), -12.0);
      expect((mov.first['stock_resultante'] as num).toDouble(), 3.0);
      expect(azul.varianteId, greaterThan(0));
    });

    test('reaparecer un color retirado revive su fila (mismo varianteId)',
        () async {
      final rojo = await colores.crear(nombre: 'Rojo');
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: [
          VarianteEntrada(colorId: rojo.id, cantidad: 10),
          const VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      final azul = p.variantes.singleWhere((v) => v.colorId != rojo.id);
      await productos.actualizar(
        p.id,
        clonar(p),
        const {'variantes'},
        variantes: [VarianteEntrada(colorId: rojo.id, cantidad: 3)],
      );

      final rehecho = await productos.actualizar(
        p.id,
        clonar(p),
        const {'variantes'},
        variantes: [
          VarianteEntrada(colorId: rojo.id, cantidad: 4),
          const VarianteEntrada(color: 'Azul', cantidad: 6),
        ],
      );
      expect(rehecho.stock, 10);
      final azulAhora = rehecho.variantes.singleWhere(
        (v) => v.colorId == azul.colorId,
      );
      expect(azulAhora.varianteId, azul.varianteId);
      expect(azulAhora.estado, 'ACTIVO');
      expect(azulAhora.stock, 6);
    });

    test('lista vacía vuelve a la variante Único con el stock del cuerpo',
        () async {
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: [
          const VarianteEntrada(color: 'Rojo', cantidad: 10),
          const VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      final u = await productos.actualizar(
        p.id,
        clonar(p, stock: 7),
        const {'stock', 'variantes'},
        variantes: const [],
      );
      expect(u.stock, 7);
      expect(u.variantes, hasLength(1));
      expect(u.variantes.single.nombreColor, 'Único');
      expect(u.variantes.single.stock, 7);
    });

    test('solo "stock" con una única variante la sincroniza', () async {
      final p = await productos.crear(nombre: 'Pan', precioVenta: 2, stock: 8);
      final s = await productos.actualizar(
        p.id,
        clonar(p, stock: 5),
        const {'stock'},
      );
      expect(s.stock, 5);
      expect(s.variantes.single.stock, 5);
    });

    test('solo "stock" con varias variantes → 400 stock_por_variante', () async {
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: [
          const VarianteEntrada(color: 'Rojo', cantidad: 10),
          const VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      await expectLater(
        productos.actualizar(p.id, clonar(p, stock: 50), const {'stock'}),
        throwsA(conCodigo('stock_por_variante')),
      );
      // No se escribió nada.
      expect((await productos.obtener(p.id)).stock, 15);
    });

    test('agotada = sin stock; vendible exige seguir viva', () async {
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: const [
          VarianteEntrada(color: 'Rojo', cantidad: 0),
          VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      final vacia = p.variantes.singleWhere(
        (v) => v.nombreColor == 'Rojo',
      );
      expect(vacia.agotada, isTrue);
      expect(vacia.vendible, isFalse);
      final llena = p.variantes.singleWhere((v) => v.nombreColor == 'Azul');
      expect(llena.vendible, isTrue);
      expect(llena.agotada, isFalse);
    });
  });

  group('Ventas con variantes', () {
    /// Crea Camisa con Rojo(10) y Azul(5) y devuelve (producto, color Rojo).
    Future<(Product, Color)> camisa() async {
      final rojo = await colores.crear(nombre: 'Rojo', codigoHex: '#FF0000');
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: [
          VarianteEntrada(colorId: rojo.id, cantidad: 10),
          const VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      return (p, rojo);
    }

    test('la venta descuenta la variante elegida y el agregado (al cobrar)',
        () async {
      final (p, rojo) = await camisa();
      final orden = await ordenes.crear(
        items: [
          ItemOrden(productoId: p.id, cantidad: 4, colorId: rojo.id),
        ],
        pagos: [pagoDePrueba(monto: 200)],
      );

      // Crear la orden no mueve stock todavía: se descuenta al cobrar.
      var actual = (await productos.obtener(p.id));
      expect(actual.stock, 15);
      expect(
        actual.variantes.singleWhere((v) => v.colorId == rojo.id).stock,
        10,
      );

      await ordenes.cambiarEstado(orden.id, 'PAGADO');
      actual = (await productos.obtener(p.id));
      expect(actual.stock, 11);
      final rojoAhora = actual.variantes.singleWhere(
        (v) => v.colorId == rojo.id,
      );
      expect(rojoAhora.stock, 6);
      expect(
        actual.variantes.singleWhere((v) => v.colorId != rojo.id).stock,
        5,
      );

      // El kardex de la venta lleva la variante concreta.
      final mov = await db.query(
        'SELECT variante_id, motivo FROM movimientos_stock '
        'WHERE orden_id = \$1',
        [orden.id],
      );
      expect(mov.single['motivo'], 'VENTA');
      expect(mov.single['variante_id'], rojoAhora.varianteId);
    });

    test('con una sola variante no hace falta pista de color', () async {
      final p = await productos.crear(nombre: 'Pan', precioVenta: 2, stock: 8);
      final orden = await ordenes.crear(
        items: [ItemOrden(productoId: p.id, cantidad: 3)],
        pagos: [pagoDePrueba(monto: 6)],
      );
      final linea = (await ordenes.detallesDe(orden.id)).single;
      expect(linea.nombreColor, 'Único');
      expect(linea.varianteId, p.variantes.single.varianteId);
    });

    test('con varias variantes sin pista → 400 variante_requerida', () async {
      final (p, _) = await camisa();
      await expectLater(
        ordenes.crear(
          items: [ItemOrden(productoId: p.id, cantidad: 1)],
          pagos: [pagoDePrueba(monto: 50)],
        ),
        throwsA(conCodigo('variante_requerida')),
      );
    });

    test('pistas que no corresponden → 400 variante_no_encontrada', () async {
      final (p, rojo) = await camisa();
      await expectLater(
        ordenes.crear(
          items: [
            ItemOrden(productoId: p.id, cantidad: 1, varianteId: 9999),
          ],
          pagos: [pagoDePrueba(monto: 50)],
        ),
        throwsA(conCodigo('variante_no_encontrada')),
      );
      await expectLater(
        ordenes.crear(
          items: [ItemOrden(productoId: p.id, cantidad: 1, color: 'Verde')],
          pagos: [pagoDePrueba(monto: 50)],
        ),
        throwsA(conCodigo('variante_no_encontrada')),
      );
      expect(
        (await productos.obtener(p.id)).variantes
            .every((v) => v.stock > 0),
        isTrue,
      );
      expect(rojo.id, greaterThan(0));
    });

    test(
      'dos colores del mismo producto son dos líneas; repetir la variante es '
      'item_duplicado',
      () async {
        final (p, rojo) = await camisa();
        final orden = await ordenes.crear(
          items: [
            ItemOrden(productoId: p.id, cantidad: 1, colorId: rojo.id),
            ItemOrden(productoId: p.id, cantidad: 2, color: 'Azul'),
          ],
          pagos: [pagoDePrueba(monto: 150)],
        );
        final lineas = await ordenes.detallesDe(orden.id);
        expect(lineas, hasLength(2));
        expect(
          lineas.map((l) => l.varianteId).toSet(),
          hasLength(2),
        );

        // La misma variante por id y por color también es duplicado
        // (la clave se comprueba después de resolver).
        await expectLater(
          ordenes.crear(
            items: [
              ItemOrden(productoId: p.id, cantidad: 1, varianteId: rojo.id),
              ItemOrden(productoId: p.id, cantidad: 1, colorId: rojo.id),
            ],
            pagos: [pagoDePrueba(monto: 100)],
          ),
          throwsA(conCodigo('item_duplicado')),
        );
      },
    );

    test('variante sin stock → 409 stock_insuficiente diciendo el color',
        () async {
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 50,
        variantes: const [
          VarianteEntrada(color: 'Rojo', cantidad: 10),
          VarianteEntrada(color: 'Azul', cantidad: 0),
        ],
      );
      await expectLater(
        ordenes.crear(
          items: [ItemOrden(productoId: p.id, cantidad: 1, color: 'Azul')],
          pagos: [pagoDePrueba(monto: 50)],
        ),
        throwsA(
          isA<ConflictException>()
              .having((e) => e.code, 'code', 'stock_insuficiente')
              .having((e) => e.message, 'message', contains('Azul')),
        ),
      );
    });

    test('el nombre del color queda congelado en el historial', () async {
      final (p, rojo) = await camisa();
      final orden = await ordenes.crear(
        items: [
          ItemOrden(productoId: p.id, cantidad: 1, colorId: rojo.id),
        ],
        pagos: [pagoDePrueba(monto: 50)],
      );
      await colores.actualizar(rojo.id, nombre: 'Carmín');

      final linea = (await ordenes.detallesDe(orden.id)).single;
      expect(linea.nombreColor, 'Rojo');
      expect(linea.toJson()['nombreColor'], 'Rojo');
    });

    test('agregarItem por variante crea una segunda línea y repetir reemplaza',
        () async {
      final (p, rojo) = await camisa();
      final orden = await ordenes.crear(
        items: [
          ItemOrden(productoId: p.id, cantidad: 1, colorId: rojo.id),
        ],
        pagos: [pagoDePrueba(monto: 50)],
      );
      final segunda = await ordenes.agregarItem(
        orden.id,
        productoId: p.id,
        cantidad: 2,
        color: 'Azul',
      );
      expect(segunda.nombreColor, 'Azul');
      expect(await ordenes.detallesDe(orden.id), hasLength(2));

      final misma = await ordenes.agregarItem(
        orden.id,
        productoId: p.id,
        cantidad: 7,
        colorId: rojo.id,
      );
      final lineas = await ordenes.detallesDe(orden.id);
      expect(lineas, hasLength(2));
      expect(
        lineas.singleWhere((l) => l.varianteId == misma.varianteId).cantidad,
        7,
      );
    });

    test('quitar una línea por variante no toca la otra', () async {
      final (p, rojo) = await camisa();
      final orden = await ordenes.crear(
        items: [
          ItemOrden(productoId: p.id, cantidad: 1, colorId: rojo.id),
          ItemOrden(productoId: p.id, cantidad: 1, color: 'Azul'),
        ],
        pagos: [pagoDePrueba(monto: 100)],
      );
      await ordenes.quitarItem(
        orden.id,
        p.id,
        varianteId: p.variantes.singleWhere((v) => v.colorId == rojo.id).varianteId,
      );
      final restantes = await ordenes.detallesDe(orden.id);
      expect(restantes, hasLength(1));
      expect(restantes.single.nombreColor, 'Azul');

      // Sin varianteId se van todas las líneas de ese producto.
      await ordenes.quitarItem(orden.id, p.id);
      expect(await ordenes.detallesDe(orden.id), isEmpty);
    });

    test('devolver el pago repone variante y agregado', () async {
      final (p, rojo) = await camisa();
      final orden = await ordenes.crear(
        items: [
          ItemOrden(productoId: p.id, cantidad: 4, colorId: rojo.id),
        ],
        pagos: [pagoDePrueba(monto: 200)],
      );
      await ordenes.cambiarEstado(orden.id, 'PAGADO');
      await ordenes.cambiarEstado(orden.id, 'CANCELADO');

      final actual = (await productos.obtener(p.id));
      expect(actual.stock, 15);
      expect(
        actual.variantes.singleWhere((v) => v.colorId == rojo.id).stock,
        10,
      );
      final motivos = await db.query(
        'SELECT motivo FROM movimientos_stock WHERE orden_id = \$1 '
        'ORDER BY movimiento_id',
        [orden.id],
      );
      expect(motivos.map((m) => m['motivo']), ['VENTA', 'DEVOLUCION']);
    });
  });

  group('Cotizaciones con variantes', () {
    test('admite el mismo producto en dos colores y no mueve stock', () async {
      final p = await productos.crear(
        nombre: 'Camisa',
        precioVenta: 10,
        variantes: const [
          VarianteEntrada(color: 'Rojo', cantidad: 10),
          VarianteEntrada(color: 'Azul', cantidad: 5),
        ],
      );
      final c = await cotizaciones.crear(
        items: [
          ItemOrden(productoId: p.id, cantidad: 1, color: 'Rojo'),
          ItemOrden(productoId: p.id, cantidad: 2, color: 'Azul'),
        ],
      );
      expect(c.detalles, hasLength(2));
      expect(c.total, 30);
      expect(
        c.detalles.every((d) => d.varianteId != null && d.nombreColor != null),
        isTrue,
      );
      expect((await productos.obtener(p.id)).stock, 15);
    });
  });
}
