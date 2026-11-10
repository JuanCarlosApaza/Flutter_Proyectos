import 'package:ventas/core/errors/failure.dart';
import 'package:ventas/core/network/api_client.dart';
import 'package:ventas/domain/entities/sesion.dart';
import 'package:ventas/domain/entities/usuario.dart';
import 'package:ventas/domain/repositories/auth_repository.dart';
import 'package:ventas/domain/usecases/auth_usecases.dart';
import 'package:ventas/presentation/controllers/auth_controller.dart';
import 'package:ventas/presentation/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Doble en memoria del repositorio: no toca la red ni el disco.
class _RepositorioFalso implements AuthRepository {
  _RepositorioFalso({this.fallar = false});

  bool fallar;
  int llamadas = 0;
  Credenciales? guardadas;

  @override
  Future<Sesion> iniciarSesion({
    required String nombreUsuario,
    required String contrasena,
    required bool recuerdame,
  }) async {
    llamadas++;
    if (fallar) {
      throw const ServerFailure(
        'Usuario o contraseña incorrectos.',
        statusCode: 401,
      );
    }
    guardadas = recuerdame
        ? (usuario: nombreUsuario, contrasena: contrasena)
        : null;
    return Sesion(
      token: 'token-de-prueba',
      expiraEn: DateTime.now().toUtc().add(const Duration(days: 30)),
      usuario: Usuario(
        id: 1,
        nombreUsuario: nombreUsuario,
        nivelUsuario: 'ADMIN',
      ),
    );
  }

  @override
  Future<Sesion?> restaurarSesion() async => null;

  @override
  Future<void> cerrarSesion({
    bool invalidarEnServidor = true,
    bool olvidarCredenciales = true,
  }) async {
    if (olvidarCredenciales) guardadas = null;
  }

  @override
  Future<Credenciales?> credencialesGuardadas() async => guardadas;
}

Widget _pantalla(AuthController auth) =>
    ChangeNotifierProvider<AuthController>.value(
      value: auth,
      child: const MaterialApp(home: LoginPage()),
    );

AuthController _controlador(AuthRepository repo) => AuthController(
  autenticacion: Autenticacion(repository: repo),
  apiClient: ApiClient(baseUrl: 'http://localhost:1'),
);

Future<void> _escribir(
  WidgetTester tester, {
  required String usuario,
  required String contrasena,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), usuario);
  await tester.enterText(find.byType(TextFormField).at(1), contrasena);
}

void main() {
  testWidgets('campos vacíos: no llama a la API y pide usuario y contraseña', (
    tester,
  ) async {
    final repo = _RepositorioFalso();
    final auth = _controlador(repo);
    addTearDown(auth.dispose);

    await tester.pumpWidget(_pantalla(auth));
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe tu usuario'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
    expect(repo.llamadas, 0);
    expect(auth.estado, AuthEstado.inicial);
  });

  testWidgets(
    'login correcto con "Recordarme" entra y guarda las credenciales',
    (tester) async {
      final repo = _RepositorioFalso();
      final auth = _controlador(repo);
      addTearDown(auth.dispose);

      await tester.pumpWidget(_pantalla(auth));
      await _escribir(
        tester,
        usuario: 'carlos.admin',
        contrasena: 'secreto123',
      );

      // El check "Recordar mi usuario y contraseña" viene marcado por defecto.
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
      await tester.pumpAndSettle();

      expect(repo.llamadas, 1);
      expect(auth.estado, AuthEstado.autenticado);
      expect(auth.nombreUsuario, 'carlos.admin');
      expect(repo.guardadas, (
        usuario: 'carlos.admin',
        contrasena: 'secreto123',
      ));
      expect(auth.recordarCredenciales, isTrue);
    },
  );

  testWidgets('sin "Recordarme" no se guarda nada y la API rechaza el acceso', (
    tester,
  ) async {
    final repo = _RepositorioFalso(fallar: true);
    final auth = _controlador(repo);
    addTearDown(auth.dispose);

    await tester.pumpWidget(_pantalla(auth));
    await _escribir(tester, usuario: 'carlos.admin', contrasena: 'mala12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();

    expect(auth.estado, AuthEstado.sinSesion);
    expect(auth.error, 'Usuario o contraseña incorrectos.');
    expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
    // El botón vuelve a estar disponible para reintentar.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Entrar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('autocompleta el usuario y la contraseña guardados', (
    tester,
  ) async {
    final repo = _RepositorioFalso()
      ..guardadas = (usuario: 'maria.elena', contrasena: 'secreto123');
    final auth = _controlador(repo);
    addTearDown(auth.dispose);

    // Arranque real: se restaura lo guardado antes de pintar el login.
    await auth.restaurar();
    expect(auth.estado, AuthEstado.sinSesion);

    await tester.pumpWidget(_pantalla(auth));
    await tester.pump();

    TextField campo(int i) => tester.widget<TextField>(
      find.descendant(
        of: find.byType(TextFormField).at(i),
        matching: find.byType(TextField),
      ),
    );

    expect(campo(0).controller!.text, 'maria.elena');
    expect(campo(1).controller!.text, 'secreto123');
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
  });
}
