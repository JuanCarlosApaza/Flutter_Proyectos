import 'package:ventas/core/validation/reglas.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _envuelve(Widget hijo) => MaterialApp(home: Scaffold(body: hijo));

/// Mismas reglas que aplica `ProductosPage` (nombre, precios, stock).
const List<CampoFormulario> _camposProducto = [
  CampoFormulario(
    clave: 'nombre',
    etiqueta: 'Nombre *',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 150,
  ),
  CampoFormulario(
    clave: 'precioVenta',
    etiqueta: 'Precio de venta (Bs) *',
    tipo: TipoCampo.decimal,
    obligatorio: true,
    min: 0.01,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'precioCompra',
    etiqueta: 'Precio de compra (Bs)',
    tipo: TipoCampo.decimal,
    min: 0,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'stock',
    etiqueta: 'Stock *',
    tipo: TipoCampo.decimal,
    obligatorio: true,
    min: 0,
    max: 999999.999,
    decimales: 3,
  ),
];

Future<void> _rellenaProducto(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextFormField).at(0),
    'Paracetamol 500 mg',
  );
  await tester.enterText(find.byType(TextFormField).at(1), '10.50');
  await tester.enterText(find.byType(TextFormField).at(2), '7.20');
  await tester.enterText(find.byType(TextFormField).at(3), '120');
}

void main() {
  group('reglas puras (espejo del backend)', () {
    test('CI: de 7 a 15 dígitos', () {
      expect(ciValido('7654321'), isNull);
      expect(ciValido('76543210'), isNull);
      expect(ciValido('123456789012345'), isNull);
      expect(ciValido('123456'), isNotNull);
      expect(ciValido('1234567890123456'), isNotNull);
      expect(ciValido('1234567A'), isNotNull);
    });

    test('teléfono: dígitos, 6 a 15 y con formato permitido', () {
      expect(telefonoValido('+51 999 888 777'), isNull);
      expect(telefonoValido('555-1234'), isNull);
      expect(telefonoValido('llamar-33'), isNotNull);
      expect(telefonoValido('123'), isNotNull);
      expect(telefonoValido('9999999999999999'), isNotNull);
    });

    test('precio de venta no puede quedar bajo el coste', () {
      expect(ventaNoMenorQueCoste(10.5, 7.2), isNull);
      expect(ventaNoMenorQueCoste(2.0, 3.5), isNotNull);
      expect(ventaNoMenorQueCoste(null, 3.5), isNull);
      expect(ventaNoMenorQueCoste('2', '3.5'), isNotNull);
    });
  });

  testWidgets('precio de venta menor al compra: avisa y no envía', (
    tester,
  ) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Producto',
          campos: _camposProducto,
          valores: const {},
          validar: (valores) => ventaNoMenorQueCoste(
            valores['precioVenta'],
            valores['precioCompra'],
          ),
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Paracetamol 500 mg',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '2.00');
    await tester.enterText(find.byType(TextFormField).at(2), '3.50');
    await tester.enterText(find.byType(TextFormField).at(3), '10');

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(enviado, isFalse);
    expect(
      find.textContaining('no puede ser menor al precio de compra'),
      findsOneWidget,
    );
  });

  testWidgets(
    'precio de venta a 0 y stock de más de un millón: errores en el campo',
    (tester) async {
      var enviado = false;
      await tester.pumpWidget(
        _envuelve(
          RecursoForm(
            titulo: 'Nuevo Producto',
            campos: _camposProducto,
            valores: const {},
            onSubmit: (_) async => enviado = true,
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'Ibuprofeno');
      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.enterText(find.byType(TextFormField).at(3), '1000001');

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(enviado, isFalse);
      expect(find.text('Debe ser mayor o igual a 0.01'), findsOneWidget);
      expect(find.text('No puede superar 999999.999'), findsOneWidget);
    },
  );

  testWidgets('formulario de producto válido: se envía', (tester) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Producto',
          campos: _camposProducto,
          valores: const {},
          validar: (valores) => ventaNoMenorQueCoste(
            valores['precioVenta'],
            valores['precioCompra'],
          ),
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    await _rellenaProducto(tester);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump();

    expect(enviado, isTrue);
    expect(find.text('Este campo es obligatorio'), findsNothing);
  });

  testWidgets('stock con 3 decimales y precios con 2 (filtros de entrada)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Producto',
          campos: _camposProducto,
          valores: const {},
          onSubmit: (_) async {},
        ),
      ),
    );

    // El stock admite 3 cifras (precisión de gramo) y corta la cuarta.
    await tester.enterText(find.byType(TextFormField).at(3), '1.2345');
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(3))
          .controller!
          .text,
      '1.234',
    );

    // Un importe admite como máximo 2 decimales.
    await tester.enterText(find.byType(TextFormField).at(1), '2.456');
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      '2.45',
    );
  });

  testWidgets('CI: 6 dígitos dan error y el campo corta en 15', (tester) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Cliente',
          campos: const [
            CampoFormulario(
              clave: 'nombre',
              etiqueta: 'Nombre *',
              obligatorio: true,
              minCaracteres: 2,
            ),
            CampoFormulario(
              clave: 'ci',
              etiqueta: 'CI',
              soloDigitos: true,
              maxCaracteres: 15,
              validador: ciValido,
            ),
          ],
          valores: const {},
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana Torres');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(enviado, isFalse);
    expect(find.text('Debe tener entre 7 y 15 dígitos'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(1),
      '1234567890123456',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      '123456789012345',
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump();
    expect(enviado, isTrue);
  });

  testWidgets('fecha de vencimiento anterior al mínimo permitido: error', (
    tester,
  ) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Producto',
          campos: [
            CampoFormulario(
              clave: 'fechaVencimiento',
              etiqueta: 'Fecha de vencimiento',
              tipo: TipoCampo.fecha,
              minFecha: DateTime(2026, 1, 1),
            ),
          ],
          valores: const {'fechaVencimiento': '2020-01-01'},
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(enviado, isFalse);
    expect(
      find.textContaining('No puede ser anterior a 2026-01-01'),
      findsOneWidget,
    );
  });

  testWidgets('fecha de vencimiento dentro del rango: se envía', (
    tester,
  ) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Producto',
          campos: [
            CampoFormulario(
              clave: 'fechaVencimiento',
              etiqueta: 'Fecha de vencimiento',
              tipo: TipoCampo.fecha,
              minFecha: DateTime(2026, 1, 1),
            ),
          ],
          valores: const {'fechaVencimiento': '2027-06-30'},
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump();

    expect(enviado, isTrue);
  });

  testWidgets('nombre demasiado corto: error con la longitud mínima', (
    tester,
  ) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nueva Categoría',
          campos: const [
            CampoFormulario(
              clave: 'nombre',
              etiqueta: 'Nombre *',
              obligatorio: true,
              minCaracteres: 2,
              maxCaracteres: 150,
            ),
          ],
          valores: const {},
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'A');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(enviado, isFalse);
    expect(find.text('Debe tener al menos 2 caracteres'), findsOneWidget);
  });
}
