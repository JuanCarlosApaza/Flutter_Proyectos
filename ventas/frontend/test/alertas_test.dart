import 'package:ventas/core/widgets/alertas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Diagnóstico de la animación de las alertas.
///
/// QuickAlert dibuja la entrada con `showGeneralDialog` (200 ms, `scale` +
/// opacidad) y la cabecera con un GIF. Aquí se comprueba que la transición
/// arranca y avanza (es decir, que **no** aparece ya hecha) y que el icono
/// animado sigue ahí.
void main() {
  late BuildContext ctx;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  testWidgets('alertaExito: la entrada está animada (no aparece ya hecha)', (
    tester,
  ) async {
    await pumpApp(tester);

    alertaExito(ctx, titulo: '¡Listo!', mensaje: 'probando');

    // Frame 0: el diálogo existe y la transición acaba de empezar.
    await tester.pump();
    final ruta = ModalRoute.of(tester.element(find.byType(AlertDialog)));
    expect(ruta, isNotNull, reason: 'no se abrió el diálogo');
    expect(ruta!.animation, isNotNull);
    expect(
      ruta.animation!.status,
      AnimationStatus.forward,
      reason: 'la transición no llegó a arrancar (¿duración 0?)',
    );
    expect(ruta.animation!.value, lessThan(0.1));

    // A mitad de camino debe haber avanzado.
    await tester.pump(const Duration(milliseconds: 100));
    expect(ruta.animation!.value, greaterThan(0.1));

    // Y a los 200 ms, completada.
    await tester.pump(const Duration(milliseconds: 200));
    expect(ruta.animation!.status, AnimationStatus.completed);

    // Icono GIF de la cabecera (la "animación" que se ve dentro).
    final assetes = [
      for (final img in tester.widgetList<Image>(find.byType(Image)))
        if (img.image is AssetImage) (img.image as AssetImage).assetName,
    ];
    expect(assetes, isNotEmpty, reason: 'falta el icono de la alerta');
    expect(
      assetes.any((ruta) => ruta.endsWith('.gif')),
      isTrue,
      reason: 'el icono dejó de ser un GIF animado: $assetes',
    );
  });

  testWidgets('confirmarAccion: también entra animado', (tester) async {
    await pumpApp(tester);

    confirmarAccion(ctx, titulo: 'Confirmar', mensaje: '¿Seguro?');

    await tester.pump();
    final ruta = ModalRoute.of(tester.element(find.byType(AlertDialog)));
    expect(ruta, isNotNull);
    expect(ruta!.animation!.status, AnimationStatus.forward);

    await tester.pump(const Duration(milliseconds: 250));
    expect(ruta.animation!.status, AnimationStatus.completed);
  });
}
