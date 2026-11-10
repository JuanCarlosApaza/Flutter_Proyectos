import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ventas/domain/entities/recurso.dart';
import 'package:ventas/domain/repositories/recurso_repository.dart';
import 'package:ventas/domain/usecases/crud.dart';
import 'package:ventas/presentation/controllers/recurso_controller.dart';
import 'package:ventas/presentation/widgets/hojas_color.dart';
import 'package:ventas/presentation/widgets/recurso_form.dart';

/// Catálogo en memoria: guarda el último alta para las aserciones.
class _CatalogoFalso implements RecursoRepository {
  int _siguienteId = 10;
  Map<String, Object?>? ultimoCuerpo;

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async => ListadoRecurso(total: 0, items: []);

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimoCuerpo = body;
    return Recurso.fromJson({'id': _siguienteId++, ...body});
  }

  @override
  Future<Recurso> obtener(String ruta) async => Recurso(id: 0, datos: const {});

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) async {}
}

void main() {
  group('paleta de color', () {
    testWidgets('«Nuevo color»: se elige la muestra de la paleta y viaja '
        'en el alta', (tester) async {
      final repo = _CatalogoFalso();
      final colores = ColoresController(Crud(repository: repo));
      late BuildContext contexto;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ColoresController>.value(value: colores),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  contexto = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final futuro = pedirNuevoColor(contexto, colores: colores);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Verde botella');
      // Nada de hexadecimal: la muestra se elige de la paleta.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Elegir color'));
      await tester.pumpAndSettle();

      expect(find.text('Elige el color'), findsOneWidget);
      await tester.tap(find.byTooltip('Verde'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Aceptar'));
      await tester.pumpAndSettle();

      // De vuelta en el diálogo, el chip ya muestra el color elegido.
      expect(find.text('Cambiar color'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Crear'));
      await tester.pumpAndSettle();

      final resultado = await futuro;
      expect(resultado?.$2, 'Verde botella');
      expect(resultado?.$3, '#4CAF50');
      expect(repo.ultimoCuerpo, {
        'nombre': 'Verde botella',
        'codigoHex': '#4CAF50',
      });
    });

    testWidgets('«Sin muestra» crea el color sin hexadecimal', (tester) async {
      final repo = _CatalogoFalso();
      final colores = ColoresController(Crud(repository: repo));
      late BuildContext contexto;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ColoresController>.value(value: colores),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  contexto = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      final futuro = pedirNuevoColor(contexto, colores: colores);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Sin muestra');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Elegir color'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sin muestra'));
      await tester.pumpAndSettle();

      expect(find.text('Elegir color'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Crear'));
      await tester.pumpAndSettle();

      final resultado = await futuro;
      expect(resultado?.$2, 'Sin muestra');
      expect(resultado?.$3, isNull);
      expect(repo.ultimoCuerpo, {'nombre': 'Sin muestra', 'codigoHex': null});
    });

    testWidgets('el campo de muestra del formulario se elige de la paleta '
        'y viaja en el cuerpo', (tester) async {
      Map<String, Object?>? enviado;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecursoForm(
              titulo: 'Nuevo Color',
              campos: const [
                CampoFormulario(
                  clave: 'nombre',
                  etiqueta: 'Nombre *',
                  obligatorio: true,
                  minCaracteres: 2,
                  maxCaracteres: 50,
                ),
                CampoFormulario(
                  clave: 'codigoHex',
                  etiqueta: 'Muestra del color',
                  tipo: TipoCampo.color,
                ),
              ],
              valores: const {},
              onSubmit: (body) async => enviado = body,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Rojo fuego');
      // El campo de muestra no se teclea: al tocarlo abre la paleta.
      await tester.tap(find.byType(TextFormField).last);
      await tester.pumpAndSettle();

      expect(find.text('Elige el color'), findsOneWidget);
      await tester.tap(find.byTooltip('Rojo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Aceptar'));
      await tester.pumpAndSettle();

      expect(find.text('#F44336'), findsOneWidget);

      // Etiqueta por defecto del formulario (las páginas la cambian a
      // «Crear»/«Actualizar»).
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(enviado, isNotNull);
      expect(enviado!['nombre'], 'Rojo fuego');
      expect(enviado!['codigoHex'], '#F44336');
    });
  });
}
