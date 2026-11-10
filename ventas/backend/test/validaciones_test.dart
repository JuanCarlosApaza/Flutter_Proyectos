import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/product.dart';
import 'package:ventas_backend/src/domain/rules/estados.dart';
import 'package:ventas_backend/src/domain/rules/validaciones.dart';
import 'package:test/test.dart';

/// Reglas puras de validación y estados: sin BD ni casos de uso.
void main() {
  Matcher lanzar(int statusCode, String code) => throwsA(
    isA<AppException>()
        .having((e) => e.statusCode, 'statusCode', statusCode)
        .having((e) => e.code, 'code', code),
  );

  group('estados', () {
    test('esOrdenEditable solo admite PENDIENTE y DEVUELTO', () {
      expect(esOrdenEditable('PENDIENTE'), isTrue);
      expect(esOrdenEditable('DEVUELTO'), isTrue);
      expect(esOrdenEditable('PAGADO'), isFalse);
      expect(esOrdenEditable('CANCELADO'), isFalse);
      expect(esOrdenEditable('ELIMINADO'), isFalse);
    });

    test('ensureEstado acepta los estados de órdenes y facturas', () {
      expect(ensureEstado('PAGADO', estadosOrdenes, 'estado'), 'PAGADO');
      expect(ensureEstado('ANULADA', estadosFacturas, 'estado'), 'ANULADA');
    });

    test('ensureEstado rechaza un valor fuera del enum → 400 '
        'estado_invalido', () {
      expect(
        () => ensureEstado('INVENTADO', estadosOrdenes, 'estado'),
        lanzar(400, 'estado_invalido'),
      );
    });
  });

  group('importes', () {
    test('dinero redondea a 2 decimales', () {
      expect(dinero(2.456), 2.46);
      expect(dinero(2.451), 2.45);
      expect(dinero(7.35), 7.35);
    });

    test('NaN e infinito → 400 field_invalid', () {
      expect(
        () => ensureImportePositivo(double.nan, 'monto'),
        lanzar(400, 'field_invalid'),
      );
      expect(
        () => ensureImportePositivo(double.infinity, 'monto'),
        lanzar(400, 'field_invalid'),
      );
    });

    test('cero no vale para importes que deben ser positivos', () {
      expect(
        () => ensureImportePositivo(0, 'precioVenta'),
        lanzar(400, 'valor_no_positivo'),
      );
      // ...pero sí para los que admiten cero (rebajas).
      expect(ensureImporteNoNegativo(0, 'rebaja'), 0);
      expect(
        () => ensureImporteNoNegativo(-1, 'rebaja'),
        lanzar(400, 'valor_negativo'),
      );
    });

    test('por encima de NUMERIC(10,2) → 400 valor_demasiado_grande', () {
      expect(
        () => ensureImportePositivo(100000000, 'total'),
        lanzar(400, 'valor_demasiado_grande'),
      );
      expect(ensureImportePositivo(importeMaximo, 'total'), importeMaximo);
    });
  });

  group('precios', () {
    test('precio de venta por debajo del costo → 400 '
        'precio_venta_bajo_costo', () {
      expect(
        () => ensurePrecioVenta(1.00, 2.50),
        lanzar(400, 'precio_venta_bajo_costo'),
      );
      expect(ensurePrecioVenta(2.50, 2.50), 2.50);
      expect(ensurePrecioVenta(3.00, null), 3.00);
    });

    test(
      'precioRebaja null = sin límite; si no, no supera el precio de venta',
      () {
        expect(ensurePrecioRebaja(null, 10), isNull);
        expect(ensurePrecioRebaja(5, 10), 5);
        expect(
          () => ensurePrecioRebaja(20, 10),
          lanzar(400, 'precio_rebaja_excesivo'),
        );
        expect(() => ensurePrecioRebaja(-1, 10), lanzar(400, 'valor_negativo'));
      },
    );
  });

  group('pagos', () {
    test('método de pago fuera del catálogo → 400 metodo_pago_invalido', () {
      expect(ensureMetodoPago('EFECTIVO'), 'EFECTIVO');
      expect(ensureMetodoPago('QR'), 'QR');
      expect(
        () => ensureMetodoPago('BITCOIN'),
        lanzar(400, 'metodo_pago_invalido'),
      );
    });

    test('referencia opcional: vacía → null; larga → 400', () {
      expect(ensureReferencia(null), isNull);
      expect(ensureReferencia('   '), isNull);
      expect(ensureReferencia('  OP-123  '), 'OP-123');
      expect(
        () => ensureReferencia('r' * (referenciaMaxima + 1)),
        lanzar(400, 'referencia_demasiado_larga'),
      );
    });
  });

  group('cantidades', () {
    test('ensurePositivo exige entero mayor que cero', () {
      expect(ensurePositivo(1, 'cantidad'), 1);
      expect(
        () => ensurePositivo(0, 'cantidad'),
        lanzar(400, 'valor_no_positivo'),
      );
      expect(
        () => ensurePositivo(-3, 'cantidad'),
        lanzar(400, 'valor_no_positivo'),
      );
    });
  });

  group('productos', () {
    Product producto({String estado = 'DISPONIBLE'}) => Product(
      id: 1,
      nombre: 'Test',
      precioVenta: 5,
      stock: 10,
      estado: estado,
    );

    test('vendible rechaza producto inexistente y oculto → 404', () {
      expect(() => vendible(null, 1), lanzar(404, 'producto_no_encontrado'));
      expect(
        () => vendible(producto(estado: 'ELIMINADO'), 1),
        lanzar(404, 'producto_no_encontrado'),
      );
      expect(vendible(producto(), 1).id, 1);
    });

    test('asegurarComprable rechaza DESCONTINUADO → 409', () {
      expect(
        () => asegurarComprable(producto(estado: 'DESCONTINUADO')),
        lanzar(409, 'producto_descontinuado'),
      );
      expect(() => asegurarComprable(producto()), returnsNormally);
    });

    test('descripcion opcional: vacío → null, texto recortado', () {
      expect(ensureDescripcion(null), isNull);
      expect(ensureDescripcion(''), isNull);
      expect(ensureDescripcion('   '), isNull);
      expect(ensureDescripcion('  Jarabe para la tos  '), 'Jarabe para la tos');
      expect(ensureDescripcion('x' * descripcionMaxima), hasLength(255));
    });

    test('descripcion de 256 caracteres → 400 field_too_long', () {
      expect(
        () => ensureDescripcion('x' * (descripcionMaxima + 1)),
        lanzar(400, 'field_too_long'),
      );
    });
  });
}
