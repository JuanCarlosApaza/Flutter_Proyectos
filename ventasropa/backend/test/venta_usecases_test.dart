import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/venta.dart';
import 'package:ventas_backend/src/domain/rules/validaciones.dart';
import 'package:ventas_backend/src/domain/usecases/venta_usecases.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Núcleo de negocio de ventas: importes/IVA, rebajas, pagos, stock y
/// facturas. Es la lógica con más riesgo económico del sistema.
void main() {
  late FakeProductoRepository productos;
  late FakeVentaRepository repo;
  late Ordenes ordenes;
  late Facturas facturas;

  setUp(() {
    productos = FakeProductoRepository(productos: [
      productoDePrueba(id: 1, precioVenta: 2.45, stock: 10),
      productoDePrueba(
        id: 2,
        nombre: 'Ibuprofeno 400 mg',
        precioVenta: 5.00,
        precioRebaja: 1.00,
        stock: 20,
      ),
      productoDePrueba(id: 3, nombre: 'Omeprazol', precioVenta: 8.00, stock: 3),
      productoDePrueba(
        id: 4,
        nombre: 'Vitamina C',
        precioVenta: 12.00,
        stock: 5,
        estado: 'DESCONTINUADO',
      ),
      productoDePrueba(
        id: 5,
        nombre: 'Suero oculto',
        precioVenta: 15.00,
        stock: 5,
        estado: 'ELIMINADO',
      ),
    ]);
    repo = FakeVentaRepository(productos: productos);
    ordenes = Ordenes(repository: repo, productos: productos);
    facturas = Facturas(repository: repo, ordenes: ordenes);
  });

  /// Inserta directamente en el repo una orden con el estado pedido (sin
  /// pasar por las reglas de `crear`, que es lo que se quiere probar aparte).
  Future<OrdenPedido> ordenExistente({
    String estado = 'PENDIENTE',
    double total = 7.35,
    double rebaja = 0,
    bool factura = false,
    int? empleadoId,
    int? clienteId,
    List<DetalleOrden> detalles = const [],
  }) => repo.insertOrden(
    OrdenPedido(
      id: 0,
      fechaOrden: DateTime.now().toUtc(),
      clienteId: clienteId,
      empleadoId: empleadoId,
      total: total,
      rebaja: rebaja,
      factura: factura,
      estado: estado,
      fechaCreacion: DateTime.now().toUtc(),
      fechaActualizacion: DateTime.now().toUtc(),
    ),
    detalles,
    const [],
  );

  DetalleOrden linea({int productoId = 1, double cantidad = 1}) {
    final producto = productos.porId(productoId)!;
    return DetalleOrden(
      productoId: productoId,
      varianteId: producto.variantes.first.id,
      ordenId: 0,
      nombreProducto: producto.nombre,
      cantidad: cantidad,
      precioVenta: producto.precioVenta,
      montoTotal: dinero(cantidad * producto.precioVenta),
    );
  }

  /// `throwsA` con el código de error estándar de la API.
  Matcher lanzar(int statusCode, String code) => throwsA(
    isA<AppException>()
        .having((e) => e.statusCode, 'statusCode', statusCode)
        .having((e) => e.code, 'code', code),
  );

  // --- Importes e IVA (entidad pura) ---------------------------------------

  group('importes e IVA', () {
    test('ivaDe aplica 14.94 % y no cobra sobre base no positiva', () {
      expect(ivaDe(100), 14.94);
      expect(ivaDe(0), 0);
      expect(ivaDe(-5), 0);
    });

    test('sin factura no se cobra IVA', () {
      final orden = OrdenPedido(
        id: 1,
        fechaOrden: DateTime.now(),
        total: 100,
        rebaja: 10,
        factura: false,
        estado: 'PENDIENTE',
        fechaCreacion: DateTime.now(),
        fechaActualizacion: DateTime.now(),
      );

      expect(orden.base, 90);
      expect(orden.iva, 0);
      expect(orden.totalPagar, 90);
    });

    test('con factura totalPagar es (total − rebaja) × 1.1494', () {
      final orden = OrdenPedido(
        id: 1,
        fechaOrden: DateTime.now(),
        total: 100,
        rebaja: 10,
        factura: true,
        estado: 'PENDIENTE',
        fechaCreacion: DateTime.now(),
        fechaActualizacion: DateTime.now(),
      );

      expect(orden.base, 90);
      expect(orden.iva, 13.45); // dinero(90 × 0.1494) = dinero(13.446)
      expect(orden.totalPagar, 103.45);
    });

    test('una rebaja mayor que el total deja la base en cero', () {
      final orden = OrdenPedido(
        id: 1,
        fechaOrden: DateTime.now(),
        total: 10,
        rebaja: 20,
        factura: true,
        estado: 'PENDIENTE',
        fechaCreacion: DateTime.now(),
        fechaActualizacion: DateTime.now(),
      );

      expect(orden.base, 0);
      expect(orden.iva, 0);
      expect(orden.totalPagar, 0);
    });

    test('la factura total es subtotal − rebaja + iva', () {
      final factura = Factura(
        id: 1,
        fechaFactura: DateTime.now(),
        subtotal: 100,
        rebaja: 10,
        iva: 13.45,
        estado: 'EMITIDA',
        fechaCreacion: DateTime.now(),
        fechaActualizacion: DateTime.now(),
      );

      expect(factura.total, 103.45);
    });
  });

  // --- Ordenes.crear --------------------------------------------------------

  group('Ordenes.crear', () {
    test('sin items → 400 items_vacios', () {
      expect(
        () => ordenes.crear(pagos: [pagoDePrueba(monto: 1)], items: const []),
        lanzar(400, 'items_vacios'),
      );
    });

    test('producto repetido → 400 item_duplicado', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 4.90)],
          items: const [
            ItemOrden(productoId: 1, cantidad: 1),
            ItemOrden(productoId: 1, cantidad: 1),
          ],
        ),
        lanzar(400, 'item_duplicado'),
      );
    });

    test('cantidad cero → 400 valor_no_positivo', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 1)],
          items: const [ItemOrden(productoId: 1, cantidad: 0)],
        ),
        lanzar(400, 'valor_no_positivo'),
      );
    });

    test('producto inexistente → 404 producto_no_encontrado', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 1)],
          items: const [ItemOrden(productoId: 999, cantidad: 1)],
        ),
        lanzar(404, 'producto_no_encontrado'),
      );
    });

    test('producto oculto (ELIMINADO) → 404 producto_no_encontrado', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 1)],
          items: const [ItemOrden(productoId: 5, cantidad: 1)],
        ),
        lanzar(404, 'producto_no_encontrado'),
      );
    });

    test('producto DESCONTINUADO → 409 producto_descontinuado', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 12)],
          items: const [ItemOrden(productoId: 4, cantidad: 1)],
        ),
        lanzar(409, 'producto_descontinuado'),
      );
    });

    test('stock insuficiente al crear → 409 stock_insuficiente', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 24)],
          items: const [ItemOrden(productoId: 3, cantidad: 5)],
        ),
        lanzar(409, 'stock_insuficiente'),
      );
    });

    test('rebaja mayor que el total → 400 rebaja_excesiva', () {
      expect(
        () => ordenes.crear(
          rebaja: 3.00,
          pagos: [pagoDePrueba(monto: 1)],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'rebaja_excesiva'),
      );
    });

    test(
      'rebaja sobre el tope del producto → 400 rebaja_excesiva '
      '(máximo permitido por los productos)',
      () {
        // Producto 2: precio 5.00 con tope de rebaja 1.00 por unidad.
        expect(
          () => ordenes.crear(
            rebaja: 2.00,
            pagos: [pagoDePrueba(monto: 3)],
            items: const [ItemOrden(productoId: 2, cantidad: 1)],
          ),
          lanzar(400, 'rebaja_excesiva'),
        );
      },
    );

    test('rebaja negativa → 400 valor_negativo', () {
      expect(
        () => ordenes.crear(
          rebaja: -1,
          pagos: [pagoDePrueba(monto: 2.45)],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'valor_negativo'),
      );
    });

    test('sin pagos → 400 pagos_vacios', () {
      expect(
        () => ordenes.crear(
          pagos: const [],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'pagos_vacios'),
      );
    });

    test('pago con monto cero → 400 valor_no_positivo', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 0)],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'valor_no_positivo'),
      );
    });

    test('método de pago desconocido → 400 metodo_pago_invalido', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 2.45, metodoPago: 'BITCOIN')],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'metodo_pago_invalido'),
      );
    });

    test('referencia de más de 100 caracteres → 400 '
        'referencia_demasiado_larga', () {
      expect(
        () => ordenes.crear(
          pagos: [
            pagoDePrueba(monto: 2.45, referencia: 'r' * 101),
          ],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'referencia_demasiado_larga'),
      );
    });

    test('la suma de pagos no cuadra → 400 pago_no_cuadra', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 1.00)],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'pago_no_cuadra'),
      );
    });

    test('un centavo de más ya no cuadra (tolerancia 0.009)', () {
      expect(
        () => ordenes.crear(
          pagos: [pagoDePrueba(monto: 2.46)],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'pago_no_cuadra'),
      );
    });

    test('con factura los pagos deben cubrir el IVA', () async {
      // total 2.45 con factura → iva 0.37 → totalPagar 2.82.
      await expectLater(
        ordenes.crear(
          factura: true,
          pagos: [pagoDePrueba(monto: 2.45)],
          items: const [ItemOrden(productoId: 1, cantidad: 1)],
        ),
        lanzar(400, 'pago_no_cuadra'),
      );

      final orden = await ordenes.crear(
        factura: true,
        pagos: [pagoDePrueba(monto: 2.82)],
        items: const [ItemOrden(productoId: 1, cantidad: 1)],
      );

      expect(orden.estado, 'PENDIENTE');
      expect(orden.totalPagar, closeTo(2.82, 0.005));
    });

    test('alta correcta: PENDIENTE, importes y pagos normalizados', () async {
      final orden = await ordenes.crear(
        clienteId: 9,
        empleadoId: 4,
        pagos: [pagoDePrueba(monto: 7.45)],
        items: const [
          ItemOrden(productoId: 1, cantidad: 1),
          ItemOrden(productoId: 2, cantidad: 1),
        ],
      );

      expect(orden.estado, 'PENDIENTE');
      expect(orden.total, 7.45); // 2.45 + 5.00
      expect(orden.rebaja, 0);
      expect(orden.totalPagar, 7.45);

      final guardados = await repo.findPagosByOrden(orden.id);
      expect(guardados, hasLength(1));
      expect(guardados.single.estado, 'ACTIVO');
      expect(guardados.single.monto, 7.45);

      final lineas = await repo.findDetallesByOrden(orden.id);
      expect(lineas, hasLength(2));
      expect(lineas.first.montoTotal, 2.45);
      expect(lineas.last.montoTotal, 5.00);
    });
  });

  // --- Ordenes.cambiarEstado (stock) ---------------------------------------

  group('Ordenes.cambiarEstado', () {
    test('PENDIENTE → PAGADO descuenta stock y marca descontarStock', () async {
      final orden = await ordenExistente(detalles: [linea(cantidad: 3)]);

      final pagada = await ordenes.cambiarEstado(orden.id, 'PAGADO');

      expect(pagada.estado, 'PAGADO');
      expect(
        repo.ultimoCambio,
        isNotNull,
      );
      expect(repo.ultimoCambio!.estadoActualEsperado, 'PENDIENTE');
      expect(repo.ultimoCambio!.nuevoEstado, 'PAGADO');
      expect(repo.ultimoCambio!.descontarStock, isTrue);
      expect(repo.ultimoCambio!.reponerStock, isFalse);
      expect(productos.porId(1)!.stock, 7); // 10 − 3
    });

    test('PAGADO → CANCELADO repone el stock descontado', () async {
      final orden = await ordenExistente(detalles: [linea(cantidad: 3)]);
      await ordenes.cambiarEstado(orden.id, 'PAGADO');
      expect(productos.porId(1)!.stock, 7);

      await ordenes.cambiarEstado(orden.id, 'CANCELADO');

      expect(repo.ultimoCambio!.descontarStock, isFalse);
      expect(repo.ultimoCambio!.reponerStock, isTrue);
      expect(productos.porId(1)!.stock, 10);
    });

    test('mismo estado → idempotente, no toca el repositorio', () async {
      final orden = await ordenExistente(estado: 'PAGADO');

      final resultado = await ordenes.cambiarEstado(orden.id, 'PAGADO');

      expect(resultado.id, orden.id);
      expect(repo.ultimoCambio, isNull);
    });

    test('estado inventado → 400 estado_invalido', () async {
      final orden = await ordenExistente();

      expect(
        () => ordenes.cambiarEstado(orden.id, 'INVENTADO'),
        lanzar(400, 'estado_invalido'),
      );
    });

    test('orden inexistente → 404 orden_no_encontrada', () {
      expect(() => ordenes.cambiarEstado(999, 'PAGADO'), lanzar(404, 'orden_no_encontrada'));
    });

    test('la fila cambió entre leer y bloquear → 409 estado_cambiado', () async {
      final orden = await ordenExistente();

      expect(
        () => repo.cambiarEstadoAtomico(
          orden.id,
          estadoActualEsperado: 'CANCELADO', // otro usuario lo cambió antes
          nuevoEstado: 'PAGADO',
          descontarStock: true,
          reponerStock: false,
        ),
        lanzar(409, 'estado_cambiado'),
      );
    });
  });

  // --- Edición de líneas -----------------------------------------------------

  group('líneas de la orden', () {
    test('agregarItem a una orden PAGADA → 409 orden_no_editable', () async {
      final orden = await ordenExistente(estado: 'PAGADO');

      expect(
        () => ordenes.agregarItem(orden.id, productoId: 1, cantidad: 1),
        lanzar(409, 'orden_no_editable'),
      );
    });

    test('agregarItem sin stock → 409 stock_insuficiente', () async {
      final orden = await ordenExistente();

      expect(
        () => ordenes.agregarItem(orden.id, productoId: 3, cantidad: 5),
        lanzar(409, 'stock_insuficiente'),
      );
    });

    test('agregarItem a una orden DEVUELTO está permitido', () async {
      final orden = await ordenExistente(estado: 'DEVUELTO');

      final detalle = await ordenes.agregarItem(
        orden.id,
        productoId: 1,
        cantidad: 2,
      );

      expect(detalle.cantidad, 2);
      expect(detalle.montoTotal, 4.90);
    });

    test('quitarItem de un producto que no está → 404 detalle_no_encontrado', () async {
      final orden = await ordenExistente();

      expect(
        () => ordenes.quitarItem(orden.id, 999),
        lanzar(404, 'detalle_no_encontrado'),
      );
    });
  });

  // --- Ordenes.eliminar ------------------------------------------------------

  group('Ordenes.eliminar', () {
    test('orden PAGADA → 409 orden_pagada', () async {
      final orden = await ordenExistente(estado: 'PAGADO');

      expect(() => ordenes.eliminar(orden.id), lanzar(409, 'orden_pagada'));
    });

    test('orden con factura emitida → 409 orden_con_factura', () async {
      final orden = await ordenExistente();
      await repo.insertFactura(
        Factura(
          id: 0,
          fechaFactura: DateTime.now().toUtc(),
          ordenId: orden.id,
          subtotal: 7.35,
          rebaja: 0,
          iva: 0,
          estado: 'EMITIDA',
          fechaCreacion: DateTime.now().toUtc(),
          fechaActualizacion: DateTime.now().toUtc(),
        ),
      );

      expect(() => ordenes.eliminar(orden.id), lanzar(409, 'orden_con_factura'));
    });

    test('orden inexistente → 404 orden_no_encontrada', () {
      expect(() => ordenes.eliminar(999), lanzar(404, 'orden_no_encontrada'));
    });

    test('orden PENDIENTE sin factura → borrado lógico', () async {
      final orden = await ordenExistente();

      await ordenes.eliminar(orden.id);

      expect(repo.ordenPorId(orden.id)!.estado, 'ELIMINADO');
    });
  });

  // --- Facturas ---------------------------------------------------------------

  group('Facturas', () {
    test('emitir de una orden PENDIENTE → 409 orden_no_pagada', () async {
      final orden = await ordenExistente();

      expect(() => facturas.emitir(ordenId: orden.id), lanzar(409, 'orden_no_pagada'));
    });

    test('emitir de una orden CANCELADA → 409 orden_no_pagada', () async {
      final orden = await ordenExistente(estado: 'CANCELADO');

      expect(() => facturas.emitir(ordenId: orden.id), lanzar(409, 'orden_no_pagada'));
    });

    test('segunda factura de la misma orden → 409 factura_duplicada', () async {
      final orden = await ordenExistente(estado: 'PAGADO');
      await facturas.emitir(ordenId: orden.id);

      expect(() => facturas.emitir(ordenId: orden.id), lanzar(409, 'factura_duplicada'));
    });

    test('la fila oculta sigue ocupando el UNIQUE → 409 factura_duplicada', () async {
      final orden = await ordenExistente(estado: 'PAGADO');
      await repo.insertFactura(
        Factura(
          id: 0,
          fechaFactura: DateTime.now().toUtc(),
          ordenId: orden.id,
          subtotal: 7.35,
          rebaja: 0,
          iva: 0,
          estado: 'ELIMINADO',
          fechaCreacion: DateTime.now().toUtc(),
          fechaActualizacion: DateTime.now().toUtc(),
        ),
      );

      expect(() => facturas.emitir(ordenId: orden.id), lanzar(409, 'factura_duplicada'));
    });

    test('emitir copia los importes de la orden y hereda al empleado', () async {
      final orden = await ordenExistente(
        estado: 'PAGADO',
        total: 100,
        rebaja: 10,
        factura: true,
        empleadoId: 4,
        clienteId: 9,
      );

      final factura = await facturas.emitir(ordenId: orden.id);

      expect(factura.estado, 'EMITIDA');
      expect(factura.subtotal, 100);
      expect(factura.rebaja, 10);
      expect(factura.iva, 13.45);
      expect(factura.empleadoId, 4);
      expect(factura.clienteId, 9);
      expect(factura.total, 103.45);
    });

    test('obtener una factura inexistente → 404 factura_no_encontrada', () {
      expect(() => facturas.obtener(999), lanzar(404, 'factura_no_encontrada'));
    });

    test('cambiarEstado con estado inventado → 400 estado_invalido', () async {
      final orden = await ordenExistente(estado: 'PAGADO');
      final factura = await facturas.emitir(ordenId: orden.id);

      expect(
        () => facturas.cambiarEstado(factura.id, 'INVENTADO'),
        lanzar(400, 'estado_invalido'),
      );
    });

    test('eliminar factura EMITIDA → 409 factura_emitida; '
        'ANULADA → se borra', () async {
      final orden = await ordenExistente(estado: 'PAGADO');
      final factura = await facturas.emitir(ordenId: orden.id);

      expect(() => facturas.eliminar(factura.id), lanzar(409, 'factura_emitida'));

      await facturas.cambiarEstado(factura.id, 'ANULADA');
      await facturas.eliminar(factura.id);

      expect((await facturas.obtener(factura.id)).estado, 'ELIMINADO');
    });
  });

  // --- Listados ---------------------------------------------------------------

  group('listados', () {
    test('el limit y offset se recortan a los rangos permitidos', () async {
      await ordenes.listar(limit: 500, offset: -5);

      expect(repo.ultimoListado, (limit: 200, offset: 0));
    });

    test('estado desconocido → 400 estado_invalido', () {
      expect(
        () => ordenes.listar(estado: 'INVENTADO'),
        lanzar(400, 'estado_invalido'),
      );
    });
  });
}
