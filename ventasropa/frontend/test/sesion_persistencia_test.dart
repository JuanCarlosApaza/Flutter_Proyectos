import 'package:ventas/core/errors/failure.dart';
import 'package:ventas/core/network/api_client.dart';
import 'package:ventas/data/datasources/auth_remote_datasource.dart';
import 'package:ventas/data/datasources/sesion_local_datasource.dart';
import 'package:ventas/data/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API falsa: responde login/logout/me sin tocar la red.
class _RemotoFalso extends AuthRemoteDataSource {
  _RemotoFalso() : super(ApiClient(baseUrl: 'http://localhost:1'));

  /// Simula que el servidor rechaza la sesión (token caducado/revocado).
  bool rechazar = false;

  int meLlamadas = 0;
  int logoutLlamadas = 0;

  @override
  Future<Map<String, dynamic>> login({
    required String nombreUsuario,
    required String contrasena,
    required bool recuerdame,
  }) async {
    if (rechazar) {
      throw const ServerFailure(
        'Usuario o contraseña incorrectos.',
        statusCode: 401,
      );
    }
    return {
      'token': 'tok-123',
      'expiraEn': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
      'usuario': {
        'id': 1,
        'nombreUsuario': nombreUsuario,
        'nivelUsuario': 'ADMIN',
        'estado': 'ACTIVO',
      },
    };
  }

  @override
  Future<void> logout() async {
    logoutLlamadas++;
    if (rechazar) {
      throw const ServerFailure('La sesión ya no es válida.', statusCode: 401);
    }
  }

  @override
  Future<Map<String, dynamic>> me() async {
    meLlamadas++;
    if (rechazar) {
      throw const ServerFailure('La sesión ya no es válida.', statusCode: 401);
    }
    return {
      'usuario': {
        'id': 1,
        'nombreUsuario': 'carlos.admin',
        'nivelUsuario': 'ADMIN',
        'estado': 'ACTIVO',
      },
      'expiraEn': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
    };
  }
}

({AuthRepositoryImpl repo, ApiClient cliente, _RemotoFalso remoto}) _crear() {
  final cliente = ApiClient(baseUrl: 'http://localhost:1');
  final remoto = _RemotoFalso();
  final repo = AuthRepositoryImpl(remoto, SesionLocalDataSource(), cliente);
  return (repo: repo, cliente: cliente, remoto: remoto);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    '"Recordarme" guarda token y credenciales; al reabrir se restauran',
    () async {
      final (repo: repo, cliente: cliente, remoto: remoto) = _crear();

      final sesion = await repo.iniciarSesion(
        nombreUsuario: 'carlos.admin',
        contrasena: 'secreto123',
        recuerdame: true,
      );

      expect(sesion.token, 'tok-123');
      expect(
        cliente.token,
        'tok-123',
        reason: 'las peticiones llevan el token',
      );

      final guardadas = await repo.credencialesGuardadas();
      expect(guardadas, (usuario: 'carlos.admin', contrasena: 'secreto123'));

      // "Reabrir la app": hay sesión persistida y el servidor la valida.
      final restaurada = await repo.restaurarSesion();
      expect(restaurada, isNotNull);
      expect(restaurada!.token, 'tok-123');
      expect(restaurada.usuario!.nombreUsuario, 'carlos.admin');
      expect(remoto.meLlamadas, 1);
    },
  );

  test('sin "Recordarme" no se persiste nada en el equipo', () async {
    final (repo: repo, cliente: cliente, remoto: _) = _crear();

    await repo.iniciarSesion(
      nombreUsuario: 'carlos.admin',
      contrasena: 'secreto123',
      recuerdame: false,
    );

    expect(cliente.token, 'tok-123', reason: 'la sesión vale mientras dure');
    expect(await repo.credencialesGuardadas(), isNull);
    expect(await SesionLocalDataSource().sesion(), isNull);
  });

  test('cerrar sesión limpia el equipo y avisa al servidor', () async {
    final (repo: repo, cliente: cliente, remoto: remoto) = _crear();
    await repo.iniciarSesion(
      nombreUsuario: 'carlos.admin',
      contrasena: 'secreto123',
      recuerdame: true,
    );
    await repo.cerrarSesion();

    expect(remoto.logoutLlamadas, 1, reason: 'se invalida en el servidor');
    expect(cliente.token, isNull);
    expect(await repo.credencialesGuardadas(), isNull);
    expect(await SesionLocalDataSource().sesion(), isNull);
    // No se vuelve a llamar a /me: ya no hay nada que restaurar.
    expect(await repo.restaurarSesion(), isNull);
  });

  test(
    'si el servidor rechaza el token se olvida la sesión, no el usuario',
    () async {
      final (repo: repo, cliente: cliente, remoto: remoto) = _crear();

      await repo.iniciarSesion(
        nombreUsuario: 'carlos.admin',
        contrasena: 'secreto123',
        recuerdame: true,
      );

      // Otro dispositivo cerró la cuenta / la sesión caducó.
      remoto.rechazar = true;
      expect(await repo.restaurarSesion(), isNull);
      expect(remoto.meLlamadas, 1);
      expect(cliente.token, isNull);
      expect(await SesionLocalDataSource().sesion(), isNull);
      expect(await repo.credencialesGuardadas(), (
        usuario: 'carlos.admin',
        contrasena: 'secreto123',
      ), reason: 'se conservan para autocompletar el login');
    },
  );

  test('credenciales incorrectas: no se guarda ni token ni usuario', () async {
    final (repo: repo, cliente: cliente, remoto: remoto) = _crear();
    remoto.rechazar = true;

    await expectLater(
      repo.iniciarSesion(
        nombreUsuario: 'carlos.admin',
        contrasena: 'mala12345',
        recuerdame: true,
      ),
      throwsA(
        isA<ServerFailure>().having((e) => e.statusCode, 'statusCode', 401),
      ),
    );

    expect(cliente.token, isNull);
    expect(await repo.credencialesGuardadas(), isNull);
    expect(await SesionLocalDataSource().sesion(), isNull);
  });
}
