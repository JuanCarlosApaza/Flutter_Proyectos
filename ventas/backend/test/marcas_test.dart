// Marca de producto (catálogo de texto), las columnas de producto
// `marca_id`/`garantia_meses` y la marca del detalle de orden (línea del
// Recibo 1): reglas de la migración 023 **contra SQLite en memoria**
// (mismas migraciones que la APK), porque aquí se comprueba el SQL real
// (índice único parcial, filtro `?marcaId=`, búsqueda por nombre de marca
// y el JOIN en vivo de la línea de orden).
import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/data/database/migrator.dart';
import 'package:ventas_backend/src/data/database/sqlite_database.dart';
import 'package:ventas_backend/src/data/repositories/marca_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/product_repository_impl.dart';
import 'package:ventas_backend/src/data/repositories/venta_repository_impl.dart';
import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/entities/venta.dart';
import 'package:ventas_backend/src/domain/usecases/marca_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/producto_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/unidad_medida_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/venta_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late SqliteDatabase db;
  late Marcas marcas;
  late Productos productos;
  late Ordenes ordenes;
  late VentaRepositoryImpl ventasRepo;

  setUp(() async {
    db = SqliteDatabase(':memory:');
    await Migrator(db, engine: 'sqlite').migrate();
    marcas = Marcas(repository: MarcaRepositoryImpl(db));
    // Igual que en `app.dart`: las órdenes trabajan contra el repositorio
    // de productos (que adjunta las variantes).
    final productosRepo = ProductRepositoryImpl(db);
    productos = Productos(
      repository: productosRepo,
      unidades: Unidades(repository: FakeUnidadMedidaRepository.semilla()),
      marcas: marcas,
    );
    ventasRepo = VentaRepositoryImpl(db);
    ordenes = Ordenes(repository: ventasRepo, productos: productosRepo);
  });

  tearDown(() async => db.close());

  /// Clon de producto con algún campo cambiado (la entidad no tiene
  /// `copyWith`); solo los campos de [campos] se escriben en la BD.
  Product clonar(
    Product p, {
    int? marcaId,
    int? garantiaMeses,
    bool borrarMarca = false,
    bool borrarGarantia = false,
  }) => Product(
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
    stock: p.stock,
    stockMinimo: p.stockMinimo,
    categoriaId: p.categoriaId,
    proveedorId: p.proveedorId,
    presentacionId: p.presentacionId,
    marcaId: borrarMarca ? null : (marcaId ?? p.marcaId),
    garantiaMeses: borrarGarantia ? null : (garantiaMeses ?? p.garantiaMeses),
    estado: p.estado,
    version: p.version,
  );

  Matcher conCodigo(String code) =>
      isA<AppException>().having((e) => e.code, 'code', code);

  group('Catálogo de marcas', () {
    test('arranca vacío y crea texto puro (sin muestra hexadecimal)',
        () async {
      expect(await marcas.listar(), isEmpty);
      final samsung = await marcas.crear(nombre: 'Samsung');
      expect(samsung.id, greaterThan(0));
      expect(samsung.estado, 'ACTIVO');
      expect(await marcas.listar(), hasLength(1));
    });

    test('nombre corto/largo → 400 field_too_short / field_too_long',
        () async {
      await expectLater(
        marcas.crear(nombre: 'A'),
        throwsA(conCodigo('field_too_short')),
      );
      await expectLater(
        marcas.crear(nombre: 'X' * 51),
        throwsA(conCodigo('field_too_long')),
      );
    });

    test('el nombre es único entre vivos, sin distinguir caja', () async {
      await marcas.crear(nombre: 'Samsung');
      await expectLater(
        marcas.crear(nombre: '  samsung  '),
        throwsA(conCodigo('marca_duplicado')),
      );
      // y en la edición tampoco se puede pisar otro vivo
      final nike = await marcas.crear(nombre: 'Nike');
      await expectLater(
        marcas.actualizar(nike.id, nombre: 'SAMSUNG'),
        throwsA(conCodigo('marca_duplicado')),
      );
    });

    test('ocultar lo saca de los listados y libera su nombre', () async {
      final samsung = await marcas.crear(nombre: 'Samsung');
      await marcas.eliminar(samsung.id);
      expect(await marcas.listar(), isEmpty);
      expect((await marcas.listar(estado: 'ELIMINADO')).single.id, samsung.id);
      // El nombre vuelve a estar disponible entre vivos (índice parcial).
      final otro = await marcas.crear(nombre: 'SAMSUNG');
      expect(otro.id, isNot(samsung.id));
    });

    test('buscar por texto y obtener por id', () async {
      await marcas.crear(nombre: 'Samsung');
      await marcas.crear(nombre: 'Nike');
      expect((await marcas.listar(q: 'sams')).single.nombre, 'Samsung');
      expect((await marcas.obtener(2)).nombre, 'Nike');
      await expectLater(marcas.obtener(99), throwsA(conCodigo('marca_no_encontrada')));
    });
  });

  group('Producto con marca y garantía', () {
    test('alta con marcaId y garantiaMeses; el JSON los expone', () async {
      final samsung = await marcas.crear(nombre: 'Samsung');
      final p = await productos.crear(
        nombre: 'Televisor 50"',
        precioVenta: 1899,
        stock: 3,
        marcaId: samsung.id,
        garantiaMeses: 12,
      );
      expect(p.marcaId, samsung.id);
      expect(p.garantiaMeses, 12);
      final json = p.toJson();
      expect(json['marcaId'], samsung.id);
      expect(json['garantiaMeses'], 12);

      final releido = await productos.obtener(p.id);
      expect(releido.marcaId, samsung.id);
      expect(releido.garantiaMeses, 12);
    });

    test('producto sin marca ni garantía: ambos null', () async {
      final p = await productos.crear(nombre: 'Pan', precioVenta: 2, stock: 8);
      expect(p.marcaId, isNull);
      expect(p.garantiaMeses, isNull);
    });

    test('marcaId que no existe → 400 marca_no_encontrada', () async {
      await expectLater(
        productos.crear(
          nombre: 'Fantasma',
          precioVenta: 1,
          marcaId: 4242,
        ),
        throwsA(conCodigo('marca_no_encontrada')),
      );
      expect(await productos.listar(), isEmpty);
    });

    test('garantia fuera de 1..120 → 400 garantia_invalida', () async {
      for (final mala in const [0, -3, 121]) {
        await expectLater(
          productos.crear(
            nombre: 'Rara',
            precioVenta: 1,
            garantiaMeses: mala,
          ),
          throwsA(conCodigo('garantia_invalida')),
        );
      }
      // 1 y 120 sí se admiten (los presets del formulario son un subconjunto).
      final p = await productos.crear(
        nombre: 'Estuche',
        precioVenta: 5,
        garantiaMeses: 1,
      );
      expect(p.garantiaMeses, 1);
    });

    test('PUT marcaId/garantiaMeses con null limpia los valores', () async {
      final samsung = await marcas.crear(nombre: 'Samsung');
      final p = await productos.crear(
        nombre: 'Auriculares',
        precioVenta: 99,
        stock: 2,
        marcaId: samsung.id,
        garantiaMeses: 6,
      );
      final editado = await productos.actualizar(
        p.id,
        clonar(p, borrarMarca: true, borrarGarantia: true),
        const {'marcaId', 'garantiaMeses'},
      );
      expect(editado.marcaId, isNull);
      expect(editado.garantiaMeses, isNull);
      final releido = await productos.obtener(p.id);
      expect(releido.marcaId, isNull);
      expect(releido.garantiaMeses, isNull);
    });

    test('oculta sale de los listados, pero su asignación no se rompe',
        () async {
      final samsung = await marcas.crear(nombre: 'Samsung');
      final p = await productos.crear(
        nombre: 'Celular',
        precioVenta: 1200,
        stock: 1,
        marcaId: samsung.id,
      );
      await marcas.eliminar(samsung.id);
      // El producto conserva la marca (no se reescribe nada)…
      expect((await productos.obtener(p.id)).marcaId, samsung.id);
      // …y, como con los colores, asignar por id una marca oculta sigue
      // siendo válido: los desplegables la ocultan, la BD no.
      final otro = await productos.crear(
        nombre: 'Tablet',
        precioVenta: 800,
        marcaId: samsung.id,
      );
      expect(otro.marcaId, samsung.id);
    });
  });

  group('Listado de productos por marca', () {
    /// Dos Samsung y un Nike (más un producto sin marca).
    Future<void> sembrar() async {
      final samsung = await marcas.crear(nombre: 'Samsung');
      final nike = await marcas.crear(nombre: 'Nike');
      await productos.crear(
        nombre: 'Galaxy A15',
        precioVenta: 1200,
        stock: 1,
        marcaId: samsung.id,
      );
      await productos.crear(
        nombre: 'Galaxy S24',
        precioVenta: 3500,
        stock: 1,
        marcaId: samsung.id,
      );
      await productos.crear(
        nombre: 'Zapato deportivo',
        precioVenta: 250,
        stock: 1,
        marcaId: nike.id,
      );
      await productos.crear(nombre: 'Pan', precioVenta: 2, stock: 8);
    }

    test('?q= encuentra productos por el nombre de su marca', () async {
      await sembrar();
      final porMarca = await productos.listar(q: 'samsung');
      expect(
        [for (final p in porMarca) p.nombre],
        ['Galaxy A15', 'Galaxy S24'],
      );
      // sigue buscando también en el contenido del producto
      expect((await productos.listar(q: 'zapato')).single.nombre,
          'Zapato deportivo');
      expect(await productos.contar(q: 'samsung'), 2);
    });

    test('?marcaId= filtra por la marca del desplegable', () async {
      await sembrar();
      final nike = (await marcas.listar(q: 'nike')).single;
      final filtrados = await productos.listar(marcaId: nike.id);
      expect(filtrados.single.nombre, 'Zapato deportivo');
      expect(await productos.contar(marcaId: nike.id), 1);
      // filtro + búsqueda combinados
      expect(
        (await productos.listar(marcaId: nike.id, q: 'galaxy')),
        isEmpty,
      );
    });
  });

  group('Recibo 1: la marca del detalle de la orden', () {
    test('la línea lleva la marca en vivo del producto', () async {
      final samsung = await marcas.crear(nombre: 'Samsung');
      final p = await productos.crear(
        nombre: 'Galaxy A15',
        precioVenta: 1200,
        stock: 5,
        marcaId: samsung.id,
      );
      final orden = await ordenes.crear(
        items: [ItemOrden(productoId: p.id, cantidad: 1)],
        pagos: [pagoDePrueba(monto: 1200)],
      );

      final linea = (await ventasRepo.findDetallesByOrden(orden.id)).single;
      expect(linea.marca, 'Samsung');

      // A diferencia del color (que se congela), la marca se une en vivo:
      // renombrarla en el catálogo cambia el nombre de la línea.
      await marcas.actualizar(samsung.id, nombre: 'Samsung Bolivia');
      final despues = (await ventasRepo.findDetallesByOrden(orden.id)).single;
      expect(despues.marca, 'Samsung Bolivia');
    });

    test('un producto sin marca deja la línea en null', () async {
      final p = await productos.crear(
        nombre: 'Pan',
        precioVenta: 2,
        stock: 8,
      );
      final orden = await ordenes.crear(
        items: [ItemOrden(productoId: p.id, cantidad: 2)],
        pagos: [pagoDePrueba(monto: 4)],
      );
      final linea = (await ventasRepo.findDetallesByOrden(orden.id)).single;
      expect(linea.marca, isNull);
    });
  });
}
