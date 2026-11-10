import 'package:ventas/core/widgets/responsive_layout.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/presentation/widgets/desplegable_buscable.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';
import 'package:ventas/presentation/widgets/recurso_tabla.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _camposProducto = [
  CampoFormulario(clave: 'nombre', etiqueta: 'Nombre *'),
  CampoFormulario(
    clave: 'precioVenta',
    etiqueta: 'Precio de venta (Bs) *',
    tipo: TipoCampo.decimal,
  ),
  CampoFormulario(
    clave: 'categoriaId',
    etiqueta: 'Categoría',
    tipo: TipoCampo.opcion,
    opciones: [Opccion('3', 'Analgésicos')],
  ),
  CampoFormulario(
    clave: 'fechaVencimiento',
    etiqueta: 'Fecha de vencimiento',
    tipo: TipoCampo.fecha,
  ),
];

const _valores = <String, Object?>{
  'nombre': 'Paracetamol 500 mg',
  'precioVenta': 10.5,
  'categoriaId': '3',
  'fechaVencimiento': '2026-10-01',
};

/// Abre la ficha de detalle en un bottom sheet (igual que la pantalla).
Future<void> _abrirDetalle(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const RecursoForm(
                titulo: 'Detalle: Paracetamol 500 mg',
                campos: _camposProducto,
                valores: _valores,
                soloLectura: true,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Recurso _producto() =>
    const Recurso(id: 1, datos: {'nombre': 'Paracetamol 500 mg', 'stock': 12});

final _columnas = [const ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre')];

void main() {
  group('ficha de detalle (solo lectura)', () {
    testWidgets('muestra todos los valores del registro', (tester) async {
      await _abrirDetalle(tester);

      expect(find.text('Detalle: Paracetamol 500 mg'), findsOneWidget);
      expect(find.text('Paracetamol 500 mg'), findsOneWidget);
      expect(find.text('10.5'), findsOneWidget);
      // El id del desplegable se muestra con su nombre legible.
      expect(find.text('Analgésicos'), findsOneWidget);
      expect(find.text('2026-10-01'), findsOneWidget);
    });

    testWidgets('no ofrece guardar ni editar nada', (tester) async {
      await _abrirDetalle(tester);

      expect(find.text('Actualizar'), findsNothing);
      expect(find.text('Crear'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
      expect(find.text('Cerrar'), findsOneWidget);

      // Campos bloqueados: sin foco ni desplegable operativo.
      final textos = tester.widgetList<TextField>(find.byType(TextField));
      expect(textos, isNotEmpty);
      for (final campo in textos) {
        expect(campo.enabled, isFalse, reason: 'campo "$campo" editable');
      }

      // El desplegable de la ficha queda fijo: sin hoja de opciones.
      final desplegables = tester.widgetList<DesplegableBuscable>(
        find.byType(DesplegableBuscable),
      );
      expect(desplegables, isNotEmpty);
      for (final desplegable in desplegables) {
        expect(
          desplegable.enabled,
          isFalse,
          reason: 'desplegable operativo en modo lectura',
        );
      }
    });

    testWidgets('Cerrar cierra la ficha', (tester) async {
      await _abrirDetalle(tester);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.byType(RecursoForm), findsNothing);
    });
  });

  group('botón 👁 en la tabla', () {
    testWidgets('se dispara onVer al pulsarlo', (tester) async {
      Recurso? visto;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecursoTabla(
                columnas: _columnas,
                items: [_producto()],
                onVer: (item) => visto = item,
                onEditar: (_) {},
                onEliminar: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      expect(visto?.id, 1);
    });

    testWidgets('no aparece si el módulo no pide onVer', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecursoTabla(
                columnas: _columnas,
                items: [_producto()],
                onEditar: (_) {},
                onEliminar: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('también aparece en la tarjeta móvil', (tester) async {
      // Por debajo de 700 px la tabla cambia a tarjetas apiladas.
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecursoTabla(
                columnas: _columnas,
                items: [_producto()],
                onVer: (_) {},
                onEditar: (_) {},
                onEliminar: (_) {},
              ),
            ),
          ),
        ),
      );

      // Por debajo de 700 px la tabla cambia a tarjetas apiladas.
      expect(find.byType(MobileCardContainer), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });
}
