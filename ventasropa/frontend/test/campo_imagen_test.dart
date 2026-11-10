import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/presentation/widgets/campo_imagen.dart';
import 'package:ventas/presentation/widgets/imagen_recurso.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';
import 'package:ventas/presentation/widgets/recurso_tabla.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _envuelve(Widget hijo) => MaterialApp(home: Scaffold(body: hijo));

void main() {
  testWidgets('campo vacío: placeholder y botón "Subir imagen"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _envuelve(
        SubidorImagen(
          valor: '',
          etiqueta: 'Imagen del producto',
          onSubido: (_) {},
          onQuitar: () {},
        ),
      ),
    );

    expect(find.text('Sin imagen'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.text('Subir imagen'), findsOneWidget);
    expect(find.text('Cambiar imagen'), findsNothing);
    expect(find.text('Quitar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con ruta local: miniatura, cambiar y quitar', (tester) async {
    await tester.pumpWidget(
      _envuelve(
        SubidorImagen(
          valor: '/api/v1/archivos/imagenes/2dadcd13ec6fb8a9.jpg',
          etiqueta: 'Imagen del producto',
          onSubido: (_) {},
          onQuitar: () {},
        ),
      ),
    );
    // La carga de red está simulada en tests: el placeholder evita el fallo.
    await tester.pump();
    await tester.pump();

    expect(find.text('2dadcd13ec6fb8a9.jpg'), findsOneWidget);
    expect(find.text('Cambiar imagen'), findsOneWidget);
    expect(find.text('Quitar'), findsOneWidget);
    expect(find.text('Sin imagen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('formulario: el campo imagen participa en la validación', (
    tester,
  ) async {
    var enviado = false;
    await tester.pumpWidget(
      _envuelve(
        RecursoForm(
          titulo: 'Nuevo Producto',
          campos: const [
            CampoFormulario(
              clave: 'nombre',
              etiqueta: 'Nombre *',
              obligatorio: true,
            ),
            CampoFormulario(
              clave: 'imagen',
              etiqueta: 'Imagen',
              tipo: TipoCampo.imagen,
            ),
          ],
          valores: const {},
          onSubmit: (_) async => enviado = true,
        ),
      ),
    );

    expect(find.text('Imagen'), findsOneWidget);
    expect(find.text('Subir imagen'), findsOneWidget);

    // Sin nombre obligatorio no debe enviar.
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    expect(find.text('Este campo es obligatorio'), findsOneWidget);
    expect(enviado, isFalse);

    // El campo de imagen no exige valor: rellenando el nombre se envía.
    await tester.enterText(find.byType(TextFormField).first, 'Ibuprofeno');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump();
    expect(enviado, isTrue);
  });

  testWidgets('tabla con miniatura pinta la imagen en desktop y móvil', (
    tester,
  ) async {
    for (final ancho in const [1000.0, 360.0]) {
      tester.view.physicalSize = Size(ancho, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final item = Recurso.fromJson({
        'id': 1,
        'nombre': 'Ibuprofeno 600 mg',
        'imagen': '/api/v1/archivos/imagenes/c6be341279c4b788.jpg',
      });

      await tester.pumpWidget(
        _envuelve(
          SingleChildScrollView(
            child: RecursoTabla(
              columnas: const [
                ColumnaTabla(
                  clave: 'nombre',
                  etiqueta: 'Nombre',
                  miniatura: true,
                ),
              ],
              items: [item],
              onEditar: (_) {},
              onEliminar: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(ImagenRecurso),
        findsOneWidget,
        reason: 'ancho=$ancho',
      );
      expect(
        find.text('Ibuprofeno 600 mg'),
        findsOneWidget,
        reason: 'ancho=$ancho',
      );
      expect(tester.takeException(), isNull, reason: 'ancho=$ancho');
    }
  });
}
