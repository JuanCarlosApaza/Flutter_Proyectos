import 'package:ventas/core/widgets/confirmar_eliminacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abre el diálogo de borrado lógico desde un botón de prueba.
Future<void> _abrirDialogo(
  WidgetTester tester, {
  required Future<void> Function() onConfirmar,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => confirmarEliminacion(
              context: context,
              titulo: 'Cliente',
              descripcion: '¿Ocultar "María Pérez"?',
              onConfirmar: onConfirmar,
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

void main() {
  testWidgets('aclara que el registro solo se oculta, no se borra', (
    tester,
  ) async {
    await _abrirDialogo(tester, onConfirmar: () async {});

    expect(find.text('Ocultar Cliente'), findsOneWidget);
    expect(find.text('¿Ocultar "María Pérez"?'), findsOneWidget);
    expect(
      find.textContaining('no se elimina de la base de datos'),
      findsOneWidget,
    );
    // La acción destructiva ya no se llama "Eliminar": no se borra nada.
    expect(find.text('Eliminar'), findsNothing);
    expect(find.text('Ocultar'), findsOneWidget);
  });

  testWidgets('Cancelar cierra el diálogo sin ocultar nada', (tester) async {
    var confirmado = false;
    await _abrirDialogo(tester, onConfirmar: () async => confirmado = true);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(confirmado, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Ocultar confirma la acción y cierra el diálogo', (tester) async {
    var confirmado = false;
    await _abrirDialogo(tester, onConfirmar: () async => confirmado = true);

    await tester.tap(find.text('Ocultar'));
    await tester.pumpAndSettle();

    expect(confirmado, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
