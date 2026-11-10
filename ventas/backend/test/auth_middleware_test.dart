import 'dart:io';

import 'package:ventas_backend/src/data/storage/almacenamiento_imagenes.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/repositories/sesion_repository.dart';
import 'package:ventas_backend/src/domain/usecases/auth_usecases.dart';
import 'package:ventas_backend/src/presentation/http/auth_middleware.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/archivo_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// `auth_middleware` sobre las rutas de imágenes reales: la lectura pública
/// debe seguir abierta y la subida debe exigir sesión.
void main() {
  late Directory carpeta;
  late Handler handler;

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('auth_middleware_test');
    final almacen = AlmacenamientoImagenes(rutaDirectorio: carpeta.path);
    final router = Router();
    addArchivoRoutes(router, almacen: almacen);
    final casosAuth = Autenticar(
      usuarios: FakeUsuarioRepository(),
      sesiones: _SesionesSinToken(),
    );
    handler = errorHandler()(autenticar(autenticar: casosAuth)(router.call));
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  test('POST /archivos/imagenes sin sesión → 401', () async {
    final respuesta = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v1/archivos/imagenes'),
        body: '{"nombre":"x.png","datos":"aGVsbG8="}',
      ),
    );

    expect(respuesta.statusCode, 401);
    expect(await respuesta.readAsString(), contains('sesion_requerida'));
  });

  test(
    'GET /archivos/imagenes/{nombre} sin sesión sigue público (404, no 401)',
    () async {
      final respuesta = await handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/v1/archivos/imagenes/noexiste12345.jpg',
          ),
        ),
      );

      expect(respuesta.statusCode, 404);
      expect(await respuesta.readAsString(), contains('imagen_no_encontrada'));
    },
  );

  test(
    'otro método sobre el prefijo de archivos tampoco pasa sin sesión',
    () async {
      final respuesta = await handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/api/v1/archivos/imagenes/x.png'),
        ),
      );

      expect(respuesta.statusCode, 401);
    },
  );
}

/// Sesiones que nunca validan: cualquier token es inválido.
final class _SesionesSinToken implements SesionRepository {
  @override
  Future<Sesion> insert({
    required int usuarioId,
    required DateTime expiraEn,
  }) async => Sesion(token: 'token', usuarioId: usuarioId, expiraEn: expiraEn);

  @override
  Future<Sesion?> findByToken(String token) async => null;

  @override
  Future<bool> delete(String token) async => true;

  @override
  Future<int> deleteExpired() async => 0;
}
