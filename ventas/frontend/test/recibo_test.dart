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

  test('el recibo 1 imprime la marca de la línea y la boleta no', () async {
    final orden = Recurso(
      id: 5,
      datos: {
        'estado': 'PAGADO',
        'fechaOrden': '2026-10-09T12:00:00Z',
        'total': 1200.0,
        'pagos': <Map<String, Object?>>[],
      },
    );

    // Sin compresión: el texto de las líneas se puede leer del PDF para
    // comprobar que la marca entra en el recibo (el color, jamás).
    final conMarca = await reciboOrden(
      orden,
      lineas: [
        Recurso(
          id: 1,
          datos: {
            'nombreProducto': 'Galaxy A15',
            'marca': 'Samsung',
            'cantidad': 1,
            'precioVenta': 1200.0,
            'montoTotal': 1200.0,
          },
        ),
      ],
      cliente: 'María Pérez',
      empleado: 'Ana Torres',
      nombreTienda: 'Mi Tienda',
      comprimir: false,
    ).save();

    // El PDF escribe cada palabra en su propio operador `TJ`, así que se
    // comprueba palabra a palabra («Galaxy A15» nunca sale contiguo).
    final texto = String.fromCharCodes(conMarca);
    expect(texto.contains('Galaxy'), isTrue);
    expect(texto.contains('A15'), isTrue);
    expect(texto.contains('Samsung'), isTrue);

    // Sin marca en la línea, no aparece ese renglón en el recibo.
    final sinMarca = await reciboOrden(
      orden,
      lineas: [
        Recurso(
          id: 2,
          datos: {
            'nombreProducto': 'Pan integral',
            'cantidad': 2,
            'precioVenta': 2.0,
            'montoTotal': 4.0,
          },
        ),
      ],
      cliente: 'María Pérez',
      empleado: 'Ana Torres',
      nombreTienda: 'Mi Tienda',
      comprimir: false,
    ).save();

    final textoSinMarca = String.fromCharCodes(sinMarca);
    expect(textoSinMarca.contains('integral'), isTrue);
    expect(textoSinMarca.contains('Samsung'), isFalse);
  });
}
