import 'dart:convert';

import 'package:ventas/core/network/api_client.dart';
import 'package:ventas/core/widgets/chat_flotante.dart';
import 'package:ventas/presentation/controllers/chat_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Respuesta JSON con la misma codificación que manda el backend (UTF-8 y
/// `charset`): sin la cabecera `http.Response` codifica en latin1 y un acento
/// rompería el decodificado del `ApiClient`.
http.Response _json(Object cuerpo, int codigo) => http.Response.bytes(
  utf8.encode(jsonEncode(cuerpo)),
  codigo,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  /// Backend falso: estado listo y una respuesta fija a cualquier pregunta.
  ApiClient api({bool ollamaActivo = true}) => ApiClient(
    baseUrl: 'http://test',
    client: MockClient((request) async {
      if (request.url.path == '/api/v1/chat/estado') {
        return _json({
          'ollamaActivo': ollamaActivo,
          'modeloListo': ollamaActivo,
          'modelo': 'ventas-qwen2.5-1.5b',
          'descarga': {'fase': 'inactivo', 'bytes': 0},
        }, 200);
      }
      return _json({'respuesta': 'Tienes 3 unidades de jeans.'}, 200);
    }),
  );

  /// Monta la burbuja igual que `app.dart`: el proveedor por encima del
  /// `MaterialApp` y el widget en el `builder`.
  Widget envoltorio(ChatController chat, {VoidCallback? onTocarPantalla}) =>
      ChangeNotifierProvider.value(
        value: chat,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: onTocarPantalla,
                child: const Text('pantalla'),
              ),
            ),
          ),
          builder: (context, child) =>
              ChatFlotante(child: child ?? const SizedBox.shrink()),
        ),
      );

  /// Bombea hasta que [listo] o se cansa: con `pumpAndSettle` los
  /// `CircularProgressIndicator` en marcha agotarían el tiempo de espera.
  Future<void> pumpHasta(WidgetTester tester, bool Function() listo) async {
    for (var i = 0; i < 60 && !listo(); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('la burbuja asoma en la pantalla y abre la hoja', (tester) async {
    final chat = ChatController(api());
    addTearDown(chat.dispose);

    await tester.pumpWidget(envoltorio(chat));
    // La pantalla original sigue debajo: la burbuja solo se superpone.
    expect(find.text('pantalla'), findsOneWidget);
    expect(find.byTooltip('Asistente'), findsOneWidget);

    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();

    expect(find.text('Asistente de la tienda'), findsOneWidget);
    // Bienvenida con ejemplos de las cifras del día.
    expect(find.text('¿Cuántos productos tengo?'), findsOneWidget);
    expect(find.text('¿Cuánto tengo de jeans?'), findsOneWidget);
  });

  testWidgets('si el rol no puede usar la IA, la burbuja no aparece', (
    tester,
  ) async {
    // El backend excluye a este rol del ajuste `iaRoles`.
    final apiExcluido = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        return _json({
          'ollamaActivo': true,
          'modeloListo': true,
          'modelo': 'ventas-qwen2.5-1.5b',
          'permitido': false,
          'descarga': {'fase': 'inactivo', 'bytes': 0},
        }, 200);
      }),
    );
    final chat = ChatController(apiExcluido);
    addTearDown(chat.dispose);
    await chat.cargarEstado();

    await tester.pumpWidget(envoltorio(chat));
    await tester.pump();

    expect(find.text('pantalla'), findsOneWidget);
    expect(find.byTooltip('Asistente'), findsNothing);
  });

  testWidgets('la capa de cierre solo bloquea la pantalla con la hoja abierta', (
    tester,
  ) async {
    var toquesEnPantalla = 0;
    final chat = ChatController(api());
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      envoltorio(chat, onTocarPantalla: () => toquesEnPantalla++),
    );

    // Hoja cerrada: la burbuja no debe comerse los toques de la app.
    await tester.tap(find.text('pantalla'));
    await tester.pump();
    expect(toquesEnPantalla, 1);

    // Hoja abierta: ahora la capa semitransparente es modal.
    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pantalla'), warnIfMissed: false);
    await tester.pump();
    expect(toquesEnPantalla, 1);

    // Al cerrar, la pantalla vuelve a ser tocable.
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('pantalla'));
    await tester.pump();
    expect(toquesEnPantalla, 2);
  });

  testWidgets('pinta los mensajes que ya hay en el controller', (
    tester,
  ) async {
    final chat = ChatController(api());
    addTearDown(chat.dispose);
    await chat.enviar('¿Cuántos productos tengo?');

    await tester.pumpWidget(envoltorio(chat));
    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuántos productos tengo?'), findsOneWidget);
    expect(find.text('Tienes 3 unidades de jeans.'), findsOneWidget);
    // Con conversación aparece el botón de limpiar.
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('escribir y enviar añade los dos turnos a la conversación', (
    tester,
  ) async {
    final chat = ChatController(api());
    addTearDown(chat.dispose);

    await tester.pumpWidget(envoltorio(chat));
    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '¿Cuánto tengo de jeans?',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    await pumpHasta(tester, () => chat.enviando == false);

    expect(find.text('¿Cuánto tengo de jeans?'), findsOneWidget);
    expect(find.text('Tienes 3 unidades de jeans.'), findsOneWidget);
    expect(chat.conversacion, hasLength(2));
  });

  testWidgets('un ejemplo de la bienvenida se envía al tocarlo', (
    tester,
  ) async {
    final chat = ChatController(api());
    addTearDown(chat.dispose);

    await tester.pumpWidget(envoltorio(chat));
    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿Cuántos productos tengo?'));
    await tester.pump();
    await pumpHasta(tester, () => chat.enviando == false);

    expect(chat.conversacion.first.esUsuario, isTrue);
    expect(chat.conversacion.first.texto, '¿Cuántos productos tengo?');
    expect(chat.conversacion, hasLength(2));
  });

  testWidgets('si Ollama está caído la cabecera lo cuenta', (tester) async {
    final chat = ChatController(api(ollamaActivo: false));
    addTearDown(chat.dispose);
    await chat.cargarEstado();

    await tester.pumpWidget(envoltorio(chat));
    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ollama no responde'), findsOneWidget);
  });

  testWidgets('limpiar vacía la conversación desde la hoja', (tester) async {
    final chat = ChatController(api());
    addTearDown(chat.dispose);
    await chat.enviar('¿Cuántos tengo?');

    await tester.pumpWidget(envoltorio(chat));
    await tester.tap(find.byTooltip('Asistente'));
    await tester.pumpAndSettle();
    expect(chat.conversacion, isNotEmpty);

    await tester.tap(find.byTooltip('Limpiar conversación'));
    await tester.pump();

    expect(chat.conversacion, isEmpty);
    expect(find.text('¿Cuántos tengo?'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
