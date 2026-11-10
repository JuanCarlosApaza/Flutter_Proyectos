import 'package:farmacia/core/errors/failure.dart';
import 'package:farmacia/core/network/api_client.dart';
import 'package:farmacia/domain/entities/recurso.dart';
import 'package:farmacia/domain/repositories/recurso_repository.dart';
import 'package:farmacia/domain/usecases/crud.dart';
import 'package:farmacia/presentation/controllers/respaldos_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Backend falso de la carpeta de respaldos: dos `.dump` ya existentes y
/// anotación de lo que llega al `POST`.
class _RepositorioRespaldos implements RecursoRepository {
  String? ultimaRuta;
  Map<String, Object?>? ultimoBody;

  final List<Recurso> guardados = [
    Recurso.fromJson({
      'id': 0,
      'nombre': 'respaldo_2026-09-30_153000.dump',
      'bytes': 2048,
      'creado': '2026-09-30T15:30:00.000Z',
    }),
    Recurso.fromJson({
      'id': 0,
      'nombre': 'respaldo_2026-09-29_153000.dump',
      'bytes': 1048576,
      'creado': '2026-09-29T15:30:00.000Z',
    }),
  ];

  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async => ListadoRecurso(
    total: guardados.length,
    items: guardados.skip(offset).take(limit).toList(),
  );

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) async {
    ultimaRuta = ruta;
    ultimoBody = body;
    return guardados.first;
  }

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}

void main() {
  group('RespaldosController', () {
    test('cargar pinta la carpeta del servidor', () async {
      final repositorio = _RepositorioRespaldos();
      final controlador = RespaldosController(
        Crud(repository: repositorio),
        ApiClient(),
      );
      addTearDown(controlador.dispose);

      await controlador.cargar();

      expect(controlador.items, hasLength(2));
      expect(
        controlador.items.first.texto('nombre'),
        'respaldo_2026-09-30_153000.dump',
      );
      expect(controlador.vacio, isFalse);
    });

    test('respaldar llama a POST respaldos y recarga', () async {
      final repositorio = _RepositorioRespaldos();
      final controlador = RespaldosController(
        Crud(repository: repositorio),
        ApiClient(),
      );
      addTearDown(controlador.dispose);

      await controlador.respaldar();

      expect(repositorio.ultimaRuta, 'respaldos');
      expect(repositorio.ultimoBody, isEmpty);
      expect(controlador.items, isNotEmpty);
    });

    test('un fallo de la API se propaga como Failure', () async {
      final controlador = RespaldosController(
        Crud(repository: _FallaAlCrear()),
        ApiClient(),
      );
      addTearDown(controlador.dispose);

      await expectLater(controlador.respaldar(), throwsA(isA<Failure>()));
    });
  });

  group('ApiClient.getBytes', () {
    test('devuelve los bytes crudos del .dump', () async {
      final api = ApiClient(
        baseUrl: 'http://test',
        client: MockClient(
          (request) async => http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'application/octet-stream'},
          ),
        ),
      );

      expect(await api.getBytes('/api/v1/respaldos/a.dump'), [1, 2, 3, 4]);
    });

    test('un 404 se traduce al mensaje y al code de la API', () async {
      final api = ApiClient(
        baseUrl: 'http://test',
        client: MockClient(
          (request) async => http.Response.bytes(
            '{"error":{"code":"respaldo_no_encontrado",'
                    '"message":"Respaldo no encontrado."}}'
                .codeUnits,
            404,
          ),
        ),
      )..token = 'abc';

      await expectLater(
        api.getBytes('/api/v1/respaldos/no-existe.dump/descarga'),
        throwsA(
          isA<ServerFailure>()
              .having((f) => f.message, 'message', 'Respaldo no encontrado.')
              .having((f) => f.code, 'code', 'respaldo_no_encontrado'),
        ),
      );
    });

    test('sin token o con 401 se avisa a la sesión', () async {
      var caducada = false;
      final api = ApiClient(
        baseUrl: 'http://test',
        client: MockClient((request) async => http.Response('', 401)),
      )
        ..token = 'caducado'
        ..onUnauthorized = () => caducada = true;

      await expectLater(api.getBytes('/x'), throwsA(isA<ServerFailure>()));
      expect(caducada, isTrue);
    });
  });
}

/// Repositorio que rechaza cualquier creación (como haría un `403`).
class _FallaAlCrear implements RecursoRepository {
  @override
  Future<ListadoRecurso> listar(
    String recurso, {
    int limit = 200,
    int offset = 0,
    String? estado,
    String? q,
    Map<String, String>? filtros,
  }) async {
    const fuente = <Recurso>[];
    return ListadoRecurso(
      total: fuente.length,
      items: fuente.skip(offset).take(limit).toList(),
    );
  }

  @override
  Future<Recurso> crear(String ruta, Map<String, Object?> body) =>
      throw const ServerFailure('La cuenta no tiene permiso', statusCode: 403);

  @override
  Future<Recurso> obtener(String ruta) async => const Recurso(id: 0, datos: {});

  @override
  Future<Recurso> editar(String ruta, Map<String, Object?> body) =>
      throw UnimplementedError();

  @override
  Future<void> eliminar(String ruta) => throw UnimplementedError();
}
