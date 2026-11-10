import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';

Widget _envuelve(Widget hijo) => MaterialApp(home: Scaffold(body: hijo));

/// Mismo reparto que aplica `ProductosPage`: lo obligatorio en la pestaña
/// «Obligatorio» (con la calculadora de ganancia junto al precio) y el
/// resto en «Opcional».
const List<CampoFormulario> _campos = [
  CampoFormulario(
    clave: 'nombre',
    etiqueta: 'Nombre *',
    pestana: 'obligatorio',
    obligatorio: true,
    minCaracteres: 2,
    maxCaracteres: 150,
  ),
  CampoFormulario(
    clave: 'precioCompra',
    etiqueta: 'Precio de compra (Bs) *',
    pestana: 'obligatorio',
    tipo: TipoCampo.decimal,
    obligatorio: true,
    min: 0.01,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'precioVenta',
    etiqueta: 'Precio de venta (Bs) *',
    pestana: 'obligatorio',
    tipo: TipoCampo.decimal,
    obligatorio: true,
    min: 0.01,
    max: 99999999.99,
  ),
  CampoFormulario(
    clave: 'gananciaPct',
    etiqueta: 'Ganancia %',
    pestana: 'obligatorio',
    tipo: TipoCampo.porcentaje,
    min: 0,
    max: 999,
    porcentajeSobre: 'precioCompra',
    porcentajeDestino: 'precioVenta',
    auxiliar: 'Precio de compra + %',
  ),
  CampoFormulario(
    clave: 'codigo',
    etiqueta: 'Código',
    pestana: 'opcional',
    maxCaracteres: 60,
  ),
  CampoFormulario(
    clave: 'stock',
    etiqueta: 'Stock',
    pestana: 'opcional',
    tipo: TipoCampo.decimal,
    min: 0,
    max: 999999.999,
  ),
];

/// Un solo campo obligatorio en la pestaña que NO está abierta: sirve para
/// comprobar que al guardar se validan también los campos invisibles.
const List<CampoFormulario> _camposConOcultoRequerido = [
  CampoFormulario(
    clave: 'nombre',
    etiqueta: 'Nombre *',
    pestana: 'obligatorio',
    obligatorio: true,
    minCaracteres: 2,
  ),
  CampoFormulario(
    clave: 'codigo',
    etiqueta: 'Código *',
    pestana: 'opcional',
    obligatorio: true,
    maxCaracteres: 60,
  ),
];

const List<PestanaFormulario> _pestanas = [
  PestanaFormulario('obligatorio', 'Obligatorio', icono: Icons.star),
  PestanaFormulario('opcional', 'Opcional', icono: Icons.tune),
];

RecursoForm _form({
  List<CampoFormulario> campos = _campos,
  Map<String, Object?> valores = const {},
  void Function(Map<String, Object?>)? guardado,
  bool esEdicion = false,
}) => RecursoForm(
  titulo: 'Producto',
  campos: campos,
  valores: valores,
  esEdicion: esEdicion,
  pestanas: _pestanas,
  onSubmit: (body) async => guardado?.call(body),
);

/// Texto escrito en el campo de texto [indice] del formulario.
String _textoEn(WidgetTester tester, int indice) => tester
    .widget<TextFormField>(find.byType(TextFormField).at(indice))
    .controller!
    .text;

Future<void> _escribe(WidgetTester tester, int indice, String texto) async {
  await tester.enterText(find.byType(TextFormField).at(indice), texto);
  await tester.pump();
}

Future<void> _guarda(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
  await tester.pump();
  await tester.pump();
}

/// Orden de los campos de la pestaña «Obligatorio»: 0 nombre, 1 precio de
/// compra, 2 precio de venta y 3 ganancia % («Código» y «Stock» viven en
/// la pestaña «Opcional» y no están montados).
void main() {
  group('pestañas Obligatorio / Opcional', () {
    testWidgets('cada campo se pinta en su pestaña y no en la otra', (
      tester,
    ) async {
      await tester.pumpWidget(_envuelve(_form()));
      await tester.pumpAndSettle();

      // Pestaña inicial: la primera del listado, con su estrella.
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('Precio de compra (Bs) *'), findsOneWidget);
      expect(find.text('Ganancia %'), findsOneWidget);
      expect(find.text('Código'), findsNothing);
      expect(find.text('Stock'), findsNothing);

      await tester.tap(find.text('Opcional'));
      await tester.pumpAndSettle();

      expect(find.text('Código'), findsOneWidget);
      expect(find.text('Stock'), findsOneWidget);
      expect(find.text('Nombre *'), findsNothing);
      expect(find.text('Precio de venta (Bs) *'), findsNothing);
    });

    testWidgets(
      'al guardar se validan TODAS las pestañas y se salta a la que falla',
      (tester) async {
        var enviado = false;
        await tester.pumpWidget(
          _envuelve(
            _form(
              campos: _camposConOcultoRequerido,
              guardado: (_) {
                enviado = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Rellena lo de la pestaña visible e intenta guardar.
        await _escribe(tester, 0, 'Paracetamol 500 mg');
        await _guarda(tester);

        // REGLA DE ORO: el «Código *» de la pestaña oculta también cuenta.
        expect(enviado, isFalse);
        expect(find.text('Código *'), findsOneWidget);
        expect(find.text('Este campo es obligatorio'), findsOneWidget);

        // Se rellena lo que falta y ahora sí se envía.
        await _escribe(tester, 0, 'MED-01');
        await _guarda(tester);
        expect(enviado, isTrue);
      },
    );

    testWidgets('un campo obligatorio vacío de la pestaña visible se ve', (
      tester,
    ) async {
      var enviado = false;
      await tester.pumpWidget(
        _envuelve(_form(guardado: (_) => enviado = true)),
      );
      await tester.pumpAndSettle();

      await _guarda(tester);

      // Nombre, precio de compra y precio de venta, los tres vacíos.
      expect(enviado, isFalse);
      expect(find.text('Este campo es obligatorio'), findsNWidgets(3));
    });
  });

  group('calculadora de porcentaje bidireccional', () {
    testWidgets('el % calcula el destino sobre la base (80 + 25 % = 100)', (
      tester,
    ) async {
      await tester.pumpWidget(_envuelve(_form()));
      await tester.pumpAndSettle();

      await _escribe(tester, 1, '80'); // precio de compra
      await _escribe(tester, 3, '25'); // ganancia %

      expect(_textoEn(tester, 2), '100');
    });

    testWidgets('escribir el destino a mano deja el % con ese margen', (
      tester,
    ) async {
      await tester.pumpWidget(_envuelve(_form()));
      await tester.pumpAndSettle();

      await _escribe(tester, 1, '80');
      await _escribe(tester, 2, '100');

      expect(_textoEn(tester, 3), '25');
    });

    testWidgets('cambiar la base re-aplica el % ya escrito', (tester) async {
      await tester.pumpWidget(_envuelve(_form()));
      await tester.pumpAndSettle();

      await _escribe(tester, 1, '80');
      await _escribe(tester, 3, '25');
      expect(_textoEn(tester, 2), '100');

      // El costo nuevo arrastra al precio con el mismo 25 %.
      await _escribe(tester, 1, '90');
      expect(_textoEn(tester, 2), '112.5');
      expect(_textoEn(tester, 3), '25');
    });

    testWidgets('un % con decimales redondea el destino a 2 cifras', (
      tester,
    ) async {
      await tester.pumpWidget(_envuelve(_form()));
      await tester.pumpAndSettle();

      await _escribe(tester, 1, '89.9');
      await _escribe(tester, 3, '12.5');

      expect(_textoEn(tester, 2), '101.14'); // 89,9 × 1,125 = 101,1375
    });

    testWidgets('sin base > 0 no calcula y lo dice en la validación', (
      tester,
    ) async {
      var enviado = false;
      await tester.pumpWidget(
        _envuelve(_form(guardado: (_) => enviado = true)),
      );
      await tester.pumpAndSettle();

      await _escribe(tester, 0, 'Paracetamol 500 mg');
      await _escribe(tester, 2, '100');
      // Sin precio de compra no hay nada que calcular ni que validar.
      await _escribe(tester, 3, '25');
      await _guarda(tester);

      expect(enviado, isFalse);
      expect(
        find.text('Escribe el precio de compra: sobre él se calcula este %'),
        findsOneWidget,
      );
      expect(_textoEn(tester, 2), '100'); // el precio tecleado no se toca
    });

    testWidgets('el rango del % es de 0 a 999', (tester) async {
      var enviado = false;
      await tester.pumpWidget(
        _envuelve(_form(guardado: (_) => enviado = true)),
      );
      await tester.pumpAndSettle();

      await _escribe(tester, 0, 'Paracetamol 500 mg');
      await _escribe(tester, 1, '80');
      await _escribe(tester, 3, '1000');
      await _guarda(tester);

      expect(enviado, isFalse);
      expect(find.text('No puede superar 999'), findsOneWidget);
    });

    testWidgets('la calculadora no viaja al backend', (tester) async {
      Map<String, Object?>? cuerpo;
      await tester.pumpWidget(_envuelve(_form(guardado: (b) => cuerpo = b)));
      await tester.pumpAndSettle();

      await _escribe(tester, 0, 'Paracetamol 500 mg');
      await _escribe(tester, 1, '80');
      await _escribe(tester, 3, '25'); // → precio de venta 100
      expect(_textoEn(tester, 2), '100');
      await _guarda(tester);

      expect(cuerpo, isNotNull);
      expect(cuerpo!['precioVenta'], 100);
      expect(cuerpo!['precioCompra'], 80);
      expect(cuerpo!.containsKey('gananciaPct'), isFalse);
    });

    testWidgets('al editar se precarga el margen real del registro', (
      tester,
    ) async {
      await tester.pumpWidget(
        _envuelve(
          _form(
            esEdicion: true,
            valores: const {'precioCompra': 80, 'precioVenta': 100},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textoEn(tester, 3), '25');
    });

    testWidgets('un precio por debajo del coste deja el % vacío', (
      tester,
    ) async {
      await tester.pumpWidget(
        _envuelve(
          _form(
            esEdicion: true,
            valores: const {'precioCompra': 80, 'precioVenta': 70},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textoEn(tester, 3), '');
    });

    testWidgets('el % se pinta en la misma fila que su destino', (
      tester,
    ) async {
      await tester.pumpWidget(_envuelve(_form()));
      await tester.pumpAndSettle();

      final destino = find.byType(TextFormField).at(2); // precio de venta
      final porcentaje = find.byType(TextFormField).at(3); // ganancia %
      final filasDestino = tester
          .widgetList<Row>(
            find.ancestor(of: destino, matching: find.byType(Row)),
          )
          .toList();
      final filasPorcentaje = tester
          .widgetList<Row>(
            find.ancestor(of: porcentaje, matching: find.byType(Row)),
          )
          .toList();

      expect(
        filasDestino.where(filasPorcentaje.contains),
        isNotEmpty,
        reason: 'precio y % deben compartir fila',
      );
      expect(find.text('Precio de compra + %'), findsOneWidget);
      expect(find.text('Ganancia %'), findsOneWidget);
    });
  });
}
