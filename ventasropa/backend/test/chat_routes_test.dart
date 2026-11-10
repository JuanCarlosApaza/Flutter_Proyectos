import 'dart:convert';
import 'dart:io';

import 'package:ventas_backend/src/core/log_asistente.dart';
import 'package:ventas_backend/src/data/database/database.dart';
import 'package:ventas_backend/src/data/services/clasificador_ia.dart';
import 'package:ventas_backend/src/data/services/consultas/catalogo_consultas.dart';
import 'package:ventas_backend/src/data/services/descargador_modelo.dart';
import 'package:ventas_backend/src/data/services/narrador.dart';
import 'package:ventas_backend/src/data/services/ollama_service.dart';
import 'package:ventas_backend/src/data/services/resolvedor_intencion.dart';
import 'package:ventas_backend/src/domain/entities/ajuste.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/repositories/ajuste_repository.dart';
import 'package:ventas_backend/src/domain/usecases/ajuste_usecases.dart';
import 'package:ventas_backend/src/presentation/http/middlewares.dart';
import 'package:ventas_backend/src/presentation/routes/chat_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// BD de mentira: un solo producto, para que el snapshot lleve su fila.
final class _FakeDb implements DatabaseConnection {
  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    if (sql.contains('ILIKE')) {
      return [
        {
          'nombre_producto': 'Jeans Clásico',
          'stock': 12,
          'precio_venta': 1.5,
          'precio_rebaja': null,
          'estado': 'DISPONIBLE',
        },
      ];
    }
    if (sql.contains('GROUP BY estado')) {
      return [
        {'estado': 'DISPONIBLE', 'total': 43, 'unidades': 900},
      ];
    }
    if (sql.contains('FROM facturas')) {
      return [
        {'n': 0, 'iva': 0},
      ];
    }
    if (sql.contains('LIMIT 10')) {
      return [
        {'nombre_producto': 'Jeans Clásico', 'unidades': 30, 'monto': 45.0},
      ];
    }
    if (sql.contains('FROM cotizaciones')) {
      return [
        {'n': 0, 'monto': 0},
      ];
    }
    if (sql.contains('GROUP BY c.nombre')) {
      return [
        {'categoria': 'Camisas', 'unidades': 30, 'monto': 45.0},
      ];
    }
    return const [];
  }

  @override
  Future<void> executeScript(String sql) async {}

  @override
  Future<void> runInTransaction(
    Future<void> Function(DatabaseSession session) action,
  ) async {}

  @override
  Future<void> ping() async {}

  @override
  Future<void> close() async {}
}

/// Ajustes en memoria para el filtro `iaRoles` del chat.
final class _AjustesFalso implements AjusteRepository {
  _AjustesFalso([Map<String, String>? valores]) : _valores = {...?valores};

  final Map<String, String> _valores;

  @override
  Future<List<Ajuste>> findAjustes({int limit = 200, int offset = 0}) async {
    final ahora = DateTime.now();
    return [
      for (final entrada in _valores.entries)
        Ajuste(
          id: 0,
          clave: entrada.key,
          valor: entrada.value,
          fechaCreacion: ahora,
          fechaActualizacion: ahora,
        ),
    ];
  }

  @override
  Future<void> upsertAjustes(Map<String, String> valores) async {
    _valores.addAll(valores);
  }
}

void main() {
  logAsistenteActivo = false;

  late Handler handler;
  late Directory carpeta;

  /// Lo último que la capa de servicio le pasó al «modelo».
  String? contextoVisto;
  List<dynamic>? mensajesVistos;

  /// Último estado que se le pidió al descargador.
  var modeloYaInstalado = true;
  var descargaLanzada = 0;

  Handler montar({
    PeticionHttp? peticion,
    int codigoCreate = 0,
    Map<String, String> ajustes = const {},
  }) {
    final ollama = OllamaService(
      url: 'http://localhost:11434',
      modelo: 'ventas-x',
      peticion:
          peticion ??
          (m, u, {cuerpo, timeout}) async {
            if (u.path == '/api/tags') {
              return (
                codigo: 200,
                cuerpo: modeloYaInstalado
                    ? '{"models":[{"name":"ventas-x:latest"}]}'
                    : '{"models":[]}',
              );
            }
            contextoVisto =
                ((cuerpo as Map)['messages'] as List).first['content']
                    as String;
            mensajesVistos = (cuerpo['messages'] as List).sublist(1);
            // El mismo modelo atiende dos puestos: clasificar (si las
            // palabras clave no bastaron) y redactar el resultado.
            if (contextoVisto!.contains('selector de funciones')) {
              return (
                codigo: 200,
                cuerpo:
                    '{"message":{"content":"{\\"funcion\\": \\"ventas_totales\\", '
                    '\\"parametros\\": {\\"periodo\\": \\"mes\\"}}"}}',
              );
            }
            return (
              codigo: 200,
              cuerpo: '{"message":{"content":"Tienes 43 productos."}}',
            );
          },
    );
    final descargador = DescargadorModelo(
      url: 'https://ejemplo.gguf',
      modelo: 'ventas-x',
      directorio: carpeta.path,
      descargar: (uri, destino, {required onProgreso}) async {
        descargaLanzada++;
        destino.writeAsStringSync('gguf-fake');
        onProgreso(10, 10);
      },
      crear: (argumentos) async => (codigo: codigoCreate, error: ''),
    );

    final catalogo = catalogoConsultas();
    final resolvedor = ResolvedorIntencion(catalogo, _FakeDb());
    final clasificador = ClasificadorIA(ollama: ollama, catalogo: catalogo);
    final narrador = Narrador(
      ollama: ollama,
      cargarContexto: () async => 'REGLAS\n{{DATOS}}',
    );

    final router = Router();
    addChatRoutes(
      router,
      ollama: ollama,
      resolvedor: resolvedor,
      clasificador: clasificador,
      narrador: narrador,
      descargador: descargador,
      ajustes: Ajustes(repository: _AjustesFalso(ajustes)),
    );
    return errorHandler()(router.call);
  }

  Request conSesion({
    String metodo = 'GET',
    String ruta = '/api/v1/chat/estado',
  }) {
    final usuario = usuarioDePrueba();
    final sesion = Sesion(
      token: 'token-de-prueba',
      usuarioId: usuario.id,
      expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
      usuario: usuario,
    );
    return Request(
      metodo,
      Uri.parse('http://localhost$ruta'),
    ).change(context: {'sesion': sesion});
  }

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('chat_rutas_test');
    handler = montar();
    contextoVisto = null;
    mensajesVistos = null;
    modeloYaInstalado = true;
    descargaLanzada = 0;
  });

  tearDown(() {
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  test('sin sesión todas las rutas responden 401', () async {
    for (final ruta in [
      '/api/v1/chat/estado',
      '/api/v1/chat/modelo/descarga',
    ]) {
      final r = await handler(
        Request('GET', Uri.parse('http://localhost$ruta')),
      );
      expect(r.statusCode, 401, reason: ruta);
    }
    final post = await handler(
      Request('POST', Uri.parse('http://localhost/api/v1/chat'), body: '{}'),
    );
    expect(post.statusCode, 401);
  });

  test('GET /estado informa de Ollama y el modelo', () async {
    final r = await handler(conSesion());
    expect(r.statusCode, 200);
    final cuerpo = await r.readAsString();
    expect(cuerpo, contains('"ollamaActivo":true'));
    expect(cuerpo, contains('"modeloListo":true'));
    expect(cuerpo, contains('"fase":"inactivo"'));
  });

  test('GET /estado con Ollama caído dice ollamaActivo false', () async {
    handler = montar(
      peticion: (m, u, {cuerpo, timeout}) async =>
          throw const SocketException('nada'),
    );
    final r = await handler(conSesion());
    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('"ollamaActivo":false'));
  });

  test('POST /chat responde 200 con el texto del modelo', () async {
    final r = await handler(
      _conSesionPost('{"mensajes":[{"role":"user","content":"¿cuántos?"}]}'),
    );

    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('Tienes 43 productos.'));
  });

  test('iaRoles: el rol fuera de la lista recibe 403 sin llamar al modelo',
      () async {
    // La sesión de prueba es ADMIN; solo CAJERO puede usar la IA.
    handler = montar(ajustes: {Ajustes.claveIaRoles: 'CAJERO'});

    final r = await handler(
      _conSesionPost('{"mensajes":[{"role":"user","content":"¿cuántos?"}]}'),
    );

    expect(r.statusCode, 403);
    expect(await r.readAsString(), contains('ia_no_permitido'));
    expect(contextoVisto, isNull, reason: 'la IA no debe gastarse');
  });

  test('iaRoles: el rol de la lista pasa y consulta', () async {
    handler = montar(ajustes: {Ajustes.claveIaRoles: 'ADMIN,CAJERO'});

    final r = await handler(
      _conSesionPost('{"mensajes":[{"role":"user","content":"¿cuántos?"}]}'),
    );

    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('Tienes 43 productos.'));
  });

  test('iaRoles: sin ajuste (vacío) puede usarlo cualquier rol', () async {
    final r = await handler(
      _conSesionPost('{"mensajes":[{"role":"user","content":"¡hola!"}]}'),
    );
    expect(r.statusCode, 200);
  });

  test('GET /estado informa si este rol puede usar la IA', () async {
    handler = montar(ajustes: {Ajustes.claveIaRoles: 'CAJERO'});
    final excluido = await handler(conSesion());
    expect(await excluido.readAsString(), contains('"permitido":false'));

    handler = montar(ajustes: {Ajustes.claveIaRoles: 'ADMIN'});
    final incluido = await handler(conSesion());
    expect(await incluido.readAsString(), contains('"permitido":true'));
  });

  test('un saludo se contesta sin llamar a la IA', () async {
    final r = await handler(
      _conSesionPost('{"mensajes":[{"role":"user","content":"¡hola!"}]}'),
    );

    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('¡Hola!'));
    expect(contextoVisto, isNull, reason: 'no debe pasar por Ollama');
  });

  test('falta el producto → el back pregunta sin llamar a la IA', () async {
    final r = await handler(
      _conSesionPost(
        '{"mensajes":[{"role":"user","content":"¿cuánto tengo de eso?"}]}',
      ),
    );

    expect(r.statusCode, 200);
    expect(
      await r.readAsString(),
      contains('¿De qué producto quieres saberlo?'),
    );
    expect(contextoVisto, isNull);
  });

  test('si el clasificador dice ninguna → respuesta fija del back', () async {
    handler = montar(
      peticion: (m, u, {cuerpo, timeout}) async {
        if (u.path == '/api/tags') {
          return (
            codigo: 200,
            cuerpo: '{"models":[{"name":"ventas-x:latest"}]}',
          );
        }
        return (
          codigo: 200,
          cuerpo: '{"message":{"content":"{\\"funcion\\": \\"ninguna\\"}"}}',
        );
      },
    );

    final r = await handler(
      _conSesionPost(
        '{"mensajes":[{"role":"user","content":"¿qué tiempo hará mañana?"}]}',
      ),
    );

    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('No encontré una respuesta'));
  });

  test('el cuerpo que llega a Ollama lleva REGLAS + los datos del producto',
      () async {
    await handler(
      _conSesionPost(
        '{"mensajes":[{"role":"user","content":"¿cuánto tengo de jeans?"}]}',
      ),
    );

    expect(contextoVisto, startsWith('REGLAS\n'));
    expect(contextoVisto, contains('Jeans Clásico'));
    expect(contextoVisto, contains('stock 12 u.'));
    // La conversación va después del system, con su rol.
    expect(mensajesVistos!.first['role'], 'user');
  });

  test('cuerpo sin mensajes → 400', () async {
    final r = await handler(_conSesionPost('{"mensajes":[]}'));
    expect(r.statusCode, 400);
    expect(await r.readAsString(), contains('mensajes_invalidos'));
  });

  test('role inválido → 400', () async {
    final r = await handler(
      _conSesionPost('{"mensajes":[{"role":"system","content":"hola"}]}'),
    );
    expect(r.statusCode, 400);
    expect(await r.readAsString(), contains('role_invalido'));
  });

  test('demasiados mensajes → 400', () async {
    final mensajes = [
      for (var i = 0; i < 41; i++) '{"role":"user","content":"m$i"}',
    ];
    final r = await handler(
      _conSesionPost('{"mensajes":[${mensajes.join(',')}]}'),
    );
    expect(r.statusCode, 400);
    expect(await r.readAsString(), contains('demasiados_mensajes'));
  });

  test('Ollama caído en POST /chat → 503 con mensaje legible', () async {
    handler = montar(
      peticion: (m, u, {cuerpo, timeout}) async =>
          throw const SocketException('nada'),
    );
    final r = await handler(
      _conSesionPost(
        '{"mensajes":[{"role":"user","content":"¿cuánto tengo de jeans?"}]}',
      ),
    );

    expect(r.statusCode, 503);
    final cuerpo = await r.readAsString();
    expect(cuerpo, contains('ollama_no_disponible'));
    expect(cuerpo, contains('ollama.com'));
  });

  test('POST /descargar arranca en segundo plano y responde 202', () async {
    modeloYaInstalado = false;
    final r = await handler(
      _conSesionPost('{}', ruta: '/api/v1/chat/modelo/descargar'),
    );

    expect(r.statusCode, 202);
    // La descarga corre en background: al empezar ya está en una fase activa.
    expect(await r.readAsString(), contains('"descarga"'));
  });

  test('si el modelo ya está instalado no descarga de nuevo', () async {
    final r = await handler(
      _conSesionPost('{}', ruta: '/api/v1/chat/modelo/descargar'),
    );

    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('ya_instalado'));
    expect(descargaLanzada, 0);
  });

  test(
    'sin el binario de ollama no se baja un GB para fallar al final',
    () async {
      handler = montar(codigoCreate: 127);
      modeloYaInstalado = false;

      final r = await handler(
        _conSesionPost('{}', ruta: '/api/v1/chat/modelo/descargar'),
      );

      expect(r.statusCode, 503);
      final cuerpo = await r.readAsString();
      expect(cuerpo, contains('ollama_no_instalado'));
      expect(cuerpo, contains('ollama.com'));
      // La comprobación va antes de lanzar la descarga: ni un byte.
      expect(descargaLanzada, 0);
    },
  );

  test('GET /descarga devuelve el estado para sondear', () async {
    final r = await handler(conSesion(ruta: '/api/v1/chat/modelo/descarga'));
    expect(r.statusCode, 200);
    expect(await r.readAsString(), contains('"fase":"inactivo"'));
  });

  test('si el PENSO de la IA coincide, viaja en la respuesta', () async {
    handler = montar(
      peticion: (m, u, {cuerpo, timeout}) async {
        if (u.path == '/api/tags') {
          return (
            codigo: 200,
            cuerpo: '{"models":[{"name":"ventas-x:latest"}]}',
          );
        }
        final sistema =
            ((cuerpo as Map)['messages'] as List).first['content'] as String;
        if (sistema.contains('selector de funciones')) {
          return (
            codigo: 200,
            cuerpo: jsonEncode({
              'message': {
                'content':
                    'PENSO: Quiere saber el stock de jeans.\n'
                    '{"funcion": "producto_stock", '
                    '"parametros": {"nombre": "jeans"}}',
              },
            }),
          );
        }
        return (
          codigo: 200,
          cuerpo: '{"message":{"content":"Tienes 12 unidades."}}',
        );
      },
    );

    final r = await handler(
      _conSesionPost(
        '{"mensajes":[{"role":"user","content":"cuanto tengo de jeans"}]}',
      ),
    );

    expect(r.statusCode, 200);
    final cuerpo = await r.readAsString();
    expect(cuerpo, contains('"pensamiento"'));
    expect(cuerpo, contains('Quiere saber el stock de jeans.'));
    expect(cuerpo, contains('Tienes 12 unidades.'));
  });

  group('normalizaProsa', () {
    test('una lista con viñetas se convierte en párrafo', () {
      final salida = normalizaProsa(
        'Sí: hay 3 agotados:\n'
        '- Jeans: stock 0 u.\n'
        '- Camiseta: stock 8 u.\n'
        '- Falda: stock 20 u.',
      );
      expect(
        salida,
        'Sí: hay 3 agotados: Jeans: stock 0 u., '
        'Camiseta: stock 8 u., Falda: stock 20 u.',
      );
      expect(salida, isNot(contains('\n-')));
    });

    test('la numeración también se unifica', () {
      final salida = normalizaProsa(
        'Los agotados son:\n1. Camiseta: stock 0\n2. Jeans: stock 0',
      );
      expect(salida, 'Los agotados son: Camiseta: stock 0, Jeans: stock 0');
    });

    test('una respuesta en prosa se queda igual', () async {
      const prosa = 'Ayer no hubo ventas.';
      expect(normalizaProsa(prosa), prosa);
    });

    test('se filtra una cabecera «## DATOS» que se cuela', () {
      expect(
        normalizaProsa('## DATOS\n\nSí: tienes 24 clientes.'),
        'Sí: tienes 24 clientes.',
      );
    });
  });
}

/// Request POST con sesión y cuerpo JSON (se separa del helper GET para no
/// arrastrar el parámetro de cuerpo a las peticiones de solo lectura).
Request _conSesionPost(String cuerpo, {String ruta = '/api/v1/chat'}) {
  final usuario = usuarioDePrueba();
  final sesion = Sesion(
    token: 'token-de-prueba',
    usuarioId: usuario.id,
    expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
    usuario: usuario,
  );
  return Request(
    'POST',
    Uri.parse('http://localhost$ruta'),
    body: cuerpo,
    headers: {'content-type': 'application/json'},
  ).change(context: {'sesion': sesion});
}
