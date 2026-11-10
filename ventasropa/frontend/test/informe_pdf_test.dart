import 'package:flutter_test/flutter_test.dart';

import 'package:ventas/domain/entities/reporte.dart';
import 'package:ventas/presentation/widgets/informe_pdf.dart';

/// Informe de prueba con dos productos y dos categorías (uno de ellos sin
/// ventas en la serie, para que también pase por las ramas con datos).
const _ventas = InformeVentas(
  desde: '2026-10-01',
  hasta: '2026-10-03',
  agrupacion: 'dia',
  resumen: ResumenVentas(total: 1540.5, ordenes: 7, unidades: 12),
  serie: [
    VentaPeriodo(etiqueta: '2026-10-01', ordenes: 7, total: 1540.5, unidades: 12),
  ],
);

const _detalle = InformeProductos(
  productos: [
    VentaProducto(
      productoId: 1,
      nombre: 'Jeans mezclillo',
      unidades: 8,
      monto: 1200,
      categoria: 'Pantalones',
    ),
    VentaProducto(
      productoId: 2,
      nombre: 'Camisa Oxford',
      unidades: 4,
      monto: 340.5,
      categoria: 'Camisas',
    ),
  ],
  categorias: [
    VentaCategoria(nombre: 'Pantalones', unidades: 8, monto: 1200),
    VentaCategoria(nombre: 'Camisas', unidades: 4, monto: 340.5),
  ],
);

const _vacio = InformeProductos(productos: [], categorias: []);

void main() {
  test('la hoja del informe se genera con cabecera PDF', () async {
    final doc = construirInformePdf(
      ventas: _ventas,
      detalle: _detalle,
      nombreTienda: 'Mi Tienda',
    );

    final bytes = await doc.save();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('un rango sin ventas también genera hoja (sin productos ni categorías)', () async {
    final doc = construirInformePdf(
      ventas: const InformeVentas(
        desde: '2026-10-01',
        hasta: '2026-10-01',
        agrupacion: 'dia',
        resumen: ResumenVentas(total: 0, ordenes: 0, unidades: 0),
        serie: [],
      ),
      detalle: _vacio,
      nombreTienda: 'Mi Tienda',
    );

    final bytes = await doc.save();

    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });

  test('una serie larga reparte en varias páginas sin romperse', () async {
    final doc = construirInformePdf(
      ventas: InformeVentas(
        desde: '2026-01-01',
        hasta: '2026-12-31',
        agrupacion: 'dia',
        resumen: const ResumenVentas(total: 900, ordenes: 9, unidades: 30),
        serie: [
          for (var dia = 1; dia <= 300; dia++)
            VentaPeriodo(
              etiqueta: '2026-10-${(dia % 28) + 1}',
              ordenes: 1,
              total: 3,
              unidades: 1,
            ),
        ],
      ),
      detalle: _detalle,
      nombreTienda: 'Mi Tienda',
    );

    final bytes = await doc.save();

    // 300 filas de serie: el documento no cabe en una sola página A4.
    expect(bytes.length, greaterThan(5000));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });
}
