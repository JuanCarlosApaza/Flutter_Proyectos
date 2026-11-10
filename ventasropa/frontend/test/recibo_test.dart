import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/presentation/widgets/recibo_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los recibos van a papel de 80 mm con el mismo dato que muestra la ficha
/// de detalle; aquí se comprueba que el PDF se arma entero (abrir el
/// diálogo de impresión es cosa del sistema, no del widget).
void main() {
  test('el recibo de la orden genera su PDF con productos y pagos', () async {
    final orden = Recurso(
      id: 1,
      datos: {
        'estado': 'PAGADO',
        'fechaOrden': '2026-09-29T14:03:00Z',
        'total': 21.0,
        'pagos': [
          {'metodoPago': 'EFECTIVO', 'monto': 21.0},
        ],
      },
    );
    final lineas = [
      Recurso(
        id: 11,
        datos: {
          'nombreProducto': 'Paracetamol 500mg',
          'cantidad': 2,
          'precioVenta': 5.5,
          'montoTotal': 11.0,
        },
      ),
    ];

    final bytes = await reciboOrden(
      orden,
      lineas: lineas,
      cliente: 'María Pérez',
      empleado: 'Ana Torres',
      nombreTienda: 'Mi Tienda',
    ).save();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('el recibo de la factura genera su PDF con los importes', () async {
    // Sin orden ni fecha: los campos vacíos salen como «N/D», que sí cabe
    // en la fuente estándar (el «—» de la app tira una excepción al PDF).
    final factura = Recurso(
      id: 3,
      datos: {
        'estado': 'EMITIDA',
        'subtotal': 21.0,
        'rebaja': 1.0,
        'iva': 0.0,
        'total': 20.0,
      },
    );

    final bytes = await reciboFactura(
      factura,
      cliente: 'María Pérez',
      empleado: 'Ana Torres',
      nombreTienda: 'Mi Tienda',
    ).save();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });
}
