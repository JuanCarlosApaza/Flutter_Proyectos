import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/usecases/marca_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/producto_usecases.dart';
import 'package:ventas_backend/src/domain/usecases/unidad_medida_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Reglas del catálogo de unidades de medida (migración 017) y de la
/// validación de `productos.unidad` contra la BD.
void main() {
  late FakeUnidadMedidaRepository repo;
  late Unidades unidades;

  setUp(() {
    repo = FakeUnidadMedidaRepository.semilla();
    unidades = Unidades(repository: repo);
  });

  group('Unidades.asegurarUnidadVigente', () {
    test('una unidad activa devuelve su código normalizado', () async {
      expect(await unidades.asegurarUnidadVigente('kg'), 'KG');
      expect(await unidades.asegurarUnidadVigente('  UN  '), 'UN');
    });

    test('sin unidad (o vacía) se queda con UN', () async {
      expect(await unidades.asegurarUnidadVigente(null), 'UN');
      expect(await unidades.asegurarUnidadVigente('   '), 'UN');
    });

    test('código que no está en el catálogo → 400 unidad_invalida', () async {
      await expectLater(
        unidades.asegurarUnidadVigente('LIBRA'),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'unidad_invalida'),
        ),
      );
    });

    test('unidad oculta ya no se puede elegir en un producto', () async {
      await unidades.eliminar(1); // KG
      await expectLater(
        unidades.asegurarUnidadVigente('KG'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'unidad_invalida',
          ),
        ),
      );
      // Los productos que ya la usan siguen conservándola: no se revalida.
      expect(await unidades.asegurarUnidadVigente('UN'), 'UN');
    });

    test('formato del símbolo: 1-10 caracteres alfanuméricos', () async {
      await expectLater(
        unidades.asegurarUnidadVigente('K G'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'unidad_invalida',
          ),
        ),
      );
      await expectLater(
        unidades.asegurarUnidadVigente('UNIDAD_DE_MUCHOS_CARACTERES'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'unidad_invalida',
          ),
        ),
      );
    });
  });

  group('Unidades.crear', () {
    test('normaliza código y tipo en mayúsculas', () async {
      final creada = await unidades.crear(
        codigo: 'lb',
        nombre: 'Libra',
        tipo: 'peso',
        decimales: 3,
      );
      expect(creada.codigo, 'LB');
      expect(creada.tipo, 'PESO');
      expect(creada.decimales, 3);
      expect(creada.estado, 'ACTIVO');
    });

    test('tipo desconocido → 400 tipo_unidad_invalido', () async {
      await expectLater(
        unidades.crear(codigo: 'XX', nombre: 'Otro', tipo: 'VOLUMENES'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'tipo_unidad_invalido',
          ),
        ),
      );
    });

    test('decimales fuera de 0..3 → 400 decimales_invalidos', () async {
      await expectLater(
        unidades.crear(codigo: 'XX', nombre: 'Otro', decimales: 4),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'decimales_invalidos',
          ),
        ),
      );
      await expectLater(
        unidades.crear(codigo: 'XX', nombre: 'Otro', decimales: -1),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'decimales_invalidos',
          ),
        ),
      );
    });

    test('nombre corto → 400 de validación de nombre', () async {
      await expectLater(
        unidades.crear(codigo: 'XX', nombre: 'K'),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('código repetido → 409 duplicado', () async {
      await expectLater(
        unidades.crear(codigo: 'KG', nombre: 'Otra kilo'),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  group('Unidades.actualizar', () {
    test('cambiar el código está prohibido → 400 codigo_inmutable', () async {
      await expectLater(
        unidades.actualizar(1, codigo: 'KGM'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'codigo_inmutable',
          ),
        ),
      );
      // El mismo código que ya tiene no molesta (así el formulario puede
      // enviar todos los campos).
      final kg = await unidades.actualizar(1, codigo: 'KG', nombre: 'Kg');
      expect(kg.codigo, 'KG');
      expect(kg.nombre, 'Kg');
    });

    test('actualización parcial: lo que no viene conserva su valor', () async {
      final kg = await unidades.actualizar(1, decimales: 2);
      expect(kg.codigo, 'KG');
      expect(kg.nombre, 'Kilogramo');
      expect(kg.tipo, 'PESO');
      expect(kg.decimales, 2);
      expect(kg.estado, 'ACTIVO');
    });

    test('unidad inexistente → 404 unidad_no_encontrada', () async {
      await expectLater(
        unidades.actualizar(999, nombre: 'Nada'),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.code,
            'code',
            'unidad_no_encontrada',
          ),
        ),
      );
    });
  });

  group('Unidades.listar / eliminar', () {
    test('el borrado es lógico y el listado excluye los ocultos', () async {
      expect(await unidades.contar(), 4);
      await unidades.eliminar(2); // GR
      expect(await unidades.contar(), 3);
      expect(
        (await unidades.listar()).map((u) => u.codigo),
        isNot(contains('GR')),
      );
      // Se recupera pidiéndolo explícitamente y con un PUT de estado.
      final restaurada = await unidades.actualizar(2, estado: 'ACTIVO');
      expect(restaurada.estado, 'ACTIVO');
      expect(await unidades.contar(), 4);
    });

    test('buscar por texto (código o nombre)', () async {
      final porCodigo = await unidades.listar(q: 'kg');
      expect(porCodigo.single.codigo, 'KG');
      final porTipo = await unidades.listar(q: 'UNIDAD');
      expect(porTipo.map((u) => u.codigo), containsAll(['UN', 'CAJA']));
    });

    test('eliminar dos veces → 404', () async {
      await unidades.eliminar(4);
      await expectLater(
        unidades.eliminar(4),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('Productos: la unidad se valida contra el catálogo', () {
    late FakeProductoRepository productosRepo;
    late Productos productos;

    /// Clon de un producto con algún campo cambiado (la entidad no tiene
    /// `copyWith`).
    Product clonar(Product p, {String? nombre, String? unidad}) => Product(
      id: p.id,
      nombre: nombre ?? p.nombre,
      codigo: p.codigo,
      imagen: p.imagen,
      unidad: unidad ?? p.unidad,
      precioVenta: p.precioVenta,
      precioCompra: p.precioCompra,
      precioRebaja: p.precioRebaja,
      fechaVencimiento: p.fechaVencimiento,
      stock: p.stock,
      stockMinimo: p.stockMinimo,
      categoriaId: p.categoriaId,
      proveedorId: p.proveedorId,
      presentacionId: p.presentacionId,
      estado: p.estado,
      version: p.version,
    );

    setUp(() {
      productosRepo = FakeProductoRepository();
      productos = Productos(
        repository: productosRepo,
        unidades: unidades,
        marcas: Marcas(repository: FakeMarcaRepository()),
      );
    });

    test('crea con la unidad del catálogo (normalizada)', () async {
      final creado = await productos.crear(
        nombre: 'Arroz',
        precioVenta: 10,
        unidad: 'kg',
        stock: 2.5,
      );
      expect(creado.unidad, 'KG');
      expect(creado.stock, 2.5);
    });

    test('sin unidad usa UN', () async {
      final creado = await productos.crear(
        nombre: 'Servilleta',
        precioVenta: 1,
      );
      expect(creado.unidad, 'UN');
    });

    test('unidad que no existe en el catálogo → 400 y no se escribe', () async {
      await expectLater(
        productos.crear(nombre: 'Arroz', precioVenta: 10, unidad: 'LIBRA'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'unidad_invalida',
          ),
        ),
      );
      expect(productosRepo.productos, isEmpty);
    });

    test('editar sin tocar la unidad no la revalida', () async {
      final creado = await productos.crear(
        nombre: 'Arroz',
        precioVenta: 10,
        unidad: 'KG',
      );
      await unidades.eliminar(1); // KG se oculta del catálogo
      final actualizado = await productos.actualizar(
        creado.id,
        clonar(creado, nombre: 'Arroz largo'),
        {'nombre'},
      );
      expect(actualizado.unidad, 'KG');
      expect(actualizado.nombre, 'Arroz largo');
    });

    test('editar enviando una unidad desconocida → 400', () async {
      final creado = await productos.crear(
        nombre: 'Arroz',
        precioVenta: 10,
        unidad: 'KG',
      );
      await expectLater(
        productos.actualizar(creado.id, clonar(creado, unidad: 'BARRIL'), {
          'unidad',
        }),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'unidad_invalida',
          ),
        ),
      );
    });
  });
}
