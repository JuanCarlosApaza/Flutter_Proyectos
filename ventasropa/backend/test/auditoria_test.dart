import 'package:ventas_backend/src/core/errors/app_exception.dart';
import 'package:ventas_backend/src/domain/entities/auditoria.dart';
import 'package:ventas_backend/src/domain/entities/sesion.dart';
import 'package:ventas_backend/src/domain/entities/usuario.dart';
import 'package:ventas_backend/src/domain/usecases/auditoria_usecases.dart';
import 'package:ventas_backend/src/presentation/http/auditoria.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late FakeAuditoriaRepository repo;
  late Auditorias auditorias;

  setUp(() {
    repo = FakeAuditoriaRepository();
    auditorias = Auditorias(repository: repo);
  });

  Sesion sesionCon(Usuario usuario) => Sesion(
    token: 'token-de-prueba',
    usuarioId: usuario.id,
    expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
    usuario: usuario,
  );

  Request peticion(
    String metodo,
    String ruta, {
    Set<String> permisos = const {},
    bool conSesion = true,
  }) {
    final request = Request(metodo, Uri.parse('http://localhost$ruta'));
    if (!conSesion) return request;
    final usuario = usuarioDePrueba(id: 7, nivel: 'ADMIN', permisos: permisos);
    return request.change(context: {'sesion': sesionCon(usuario)});
  }

  group('auditarCambios (wrapper)', () {
    test(
      'una mutación registrada lleva usuario, rol, entidad y acción',
      () async {
        final handler = auditarCambios(
          (request) async => Response(200, body: '{}'),
          auditorias: auditorias,
        );

        final respuesta = await handler(peticion('PUT', '/api/v1/usuarios/27'));

        expect(respuesta.statusCode, 200);
        expect(repo.eventos, hasLength(1));
        final evento = repo.eventos.single;
        expect(evento.accion, 'ACTUALIZAR');
        expect(evento.exitoso, isTrue);
        expect(evento.usuarioId, 7);
        expect(evento.nombreUsuario, 'usuario.test');
        expect(evento.rol, 'ADMIN');
        expect(evento.entidad, 'usuarios');
        expect(evento.entidadId, 27);
        expect(evento.resumen, 'PUT /api/v1/usuarios/27 -> 200');
        expect(evento.fecha, isNotNull);
      },
    );

    test('los GET no se auditan', () async {
      final handler = auditarCambios(
        (request) async => Response(200, body: '{}'),
        auditorias: auditorias,
      );

      await handler(peticion('GET', '/api/v1/productos'));

      expect(repo.eventos, isEmpty);
    });

    test('alias de la ruta: products → productos', () async {
      final handler = auditarCambios(
        (request) async => Response(201, body: '{}'),
        auditorias: auditorias,
      );

      await handler(peticion('POST', '/api/v1/products/5'));

      expect(repo.eventos.single.entidad, 'productos');
      expect(repo.eventos.single.accion, 'CREAR');
    });

    test('una excepción se registra como fallida y se relanza', () async {
      final handler = auditarCambios(
        (request) => throw const ForbiddenException(
          'Sin permiso.',
          code: 'permiso_denegado',
        ),
        auditorias: auditorias,
      );

      await expectLater(
        handler(peticion('DELETE', '/api/v1/productos/9')),
        throwsA(isA<ForbiddenException>()),
      );

      final evento = repo.eventos.single;
      expect(evento.exitoso, isFalse);
      expect(evento.codigoError, 'permiso_denegado');
      expect(evento.accion, 'ELIMINAR');
      expect(evento.resumen, 'DELETE /api/v1/productos/9 -> 403');
    });

    test('login correcto y fallido (con la identidad intentada)', () async {
      final handler = auditarCambios((request) async {
        detalleAuditoria(request, {'nombreUsuario': 'ana'});
        return Response(200, body: '{}');
      }, auditorias: auditorias);
      // Sin sesión: el login es público.
      await handler(peticion('POST', '/api/v1/auth/login', conSesion: false));
      expect(repo.eventos.single.accion, 'LOGIN');
      expect(repo.eventos.single.detalles?['nombreUsuario'], 'ana');

      final fallido = auditarCambios((request) async {
        detalleAuditoria(request, {'nombreUsuario': 'ana'});
        throw const UnauthorizedException(
          'Usuario o contraseña incorrectos.',
          code: 'credenciales_invalidas',
        );
      }, auditorias: auditorias);
      await expectLater(
        fallido(peticion('POST', '/api/v1/auth/login', conSesion: false)),
        throwsA(isA<UnauthorizedException>()),
      );

      expect(repo.eventos.last.accion, 'LOGIN_FALLIDO');
      expect(repo.eventos.last.exitoso, isFalse);
      expect(repo.eventos.last.codigoError, 'credenciales_invalidas');
      expect(repo.eventos.last.detalles?['nombreUsuario'], 'ana');
    });

    test('logout → LOGOUT con la cuenta de la sesión', () async {
      final handler = auditarCambios(
        (request) async => Response(200, body: '{}'),
        auditorias: auditorias,
      );

      await handler(peticion('POST', '/api/v1/auth/logout'));

      expect(repo.eventos.single.accion, 'LOGOUT');
      expect(repo.eventos.single.usuarioId, 7);
    });

    test('detalleAuditoria aporta campos y admite acción propia', () async {
      final handler = auditarCambios((request) async {
        detalleAuditoria(request, {
          'campos': ['contrasena'],
        });
        detalleAuditoria(request, {
          'contrasenaCambiada': true,
        }, accion: 'RESTABLECER_CONTRASENA');
        return Response(200, body: '{}');
      }, auditorias: auditorias);

      await handler(peticion('PUT', '/api/v1/usuarios/3'));

      final evento = repo.eventos.single;
      expect(evento.accion, 'RESTABLECER_CONTRASENA');
      expect(evento.detalles?['campos'], ['contrasena']);
      expect(evento.detalles?['contrasenaCambiada'], isTrue);
    });

    test('sanitizado: contraseñas y tokens jamás llegan al detalle', () async {
      final handler = auditarCambios((request) async {
        detalleAuditoria(request, {
          'contrasena': 'secreto123',
          'claveAdmin': 'miclave',
          'token': 'abc123',
          'password': 'x',
          'nombreUsuario': 'ana',
          'anidado': {'contrasena': 'secreto123', 'rolId': 1},
          'lista': [
            {'claveAdmin': 'miclave', 'valor': 'ok'},
          ],
        });
        return Response(200, body: '{}');
      }, auditorias: auditorias);

      await handler(peticion('PUT', '/api/v1/roles/1'));

      final detalles = repo.eventos.single.detalles!;
      expect(detalles.containsKey('contrasena'), isFalse);
      expect(detalles.containsKey('claveAdmin'), isFalse);
      expect(detalles.containsKey('token'), isFalse);
      expect(detalles.containsKey('password'), isFalse);
      expect(detalles['nombreUsuario'], 'ana');
      expect((detalles['anidado'] as Map).containsKey('contrasena'), isFalse);
      expect((detalles['anidado'] as Map)['rolId'], 1);
      expect(
        ((detalles['lista'] as List).first as Map).containsKey('claveAdmin'),
        isFalse,
      );
      expect(((detalles['lista'] as List).first as Map)['valor'], 'ok');
    });

    test('detalleAuditoria fuera del wrapper es un no-op', () {
      final request = peticion('PUT', '/api/v1/usuarios/1');
      expect(() => detalleAuditoria(request, {'x': 1}), returnsNormally);
    });
  });

  group('detalleRegistro', () {
    Future<AuditoriaEvento> registrar(
      void Function(Request request) preparar,
    ) async {
      final handler = auditarCambios((request) async {
        preparar(request);
        return Response(200, body: '{}');
      }, auditorias: auditorias);
      await handler(peticion('PUT', '/api/v1/products/5'));
      return repo.eventos.single;
    }

    test('nombre + campos + diff; omite lo que no cambió', () async {
      final evento = await registrar((request) {
        detalleRegistro(
          request,
          nombre: 'Ibuprofeno 600',
          antes: {
            'nombre': 'Ibuprofeno 600',
            'precioVenta': 2.0,
            'stock': 10,
            'fechaVencimiento': DateTime(2026, 6, 30),
          },
          despues: {
            'nombre': 'Ibuprofeno 600',
            'precioVenta': 2.5,
            'stock': 10,
            // El body trae solo el día: cuenta como "sin cambio".
            'fechaVencimiento': '2026-06-30',
          },
          campos: {'nombre', 'precioVenta', 'stock', 'fechaVencimiento'},
        );
      });

      final detalles = evento.detalles!;
      expect(detalles['nombre'], 'Ibuprofeno 600');
      expect(detalles['campos'], [
        'fechaVencimiento',
        'nombre',
        'precioVenta',
        'stock',
      ]);
      final cambios = detalles['cambios'] as Map;
      expect(cambios.keys.toList(), ['precioVenta']);
      expect((cambios['precioVenta'] as Map)['antes'], 2.0);
      expect((cambios['precioVenta'] as Map)['despues'], 2.5);
    });

    test('nunca escribe credenciales en el diff', () async {
      final evento = await registrar((request) {
        detalleRegistro(
          request,
          nombre: 'ana',
          antes: {'contrasena': 'secreto123', 'estado': 'ACTIVO'},
          despues: {
            'contrasena': 'nuevapass1',
            'claveAdmin': 'klave',
            'estado': 'BLOQUEADO',
          },
          campos: {'contrasena', 'claveAdmin', 'estado'},
        );
      });

      final detalles = evento.detalles!;
      final cambios = detalles['cambios'] as Map;
      expect(cambios.containsKey('contrasena'), isFalse);
      expect(cambios.containsKey('claveAdmin'), isFalse);
      // Ni siquiera los valores sueltos aparecen en el JSON del evento.
      final json = evento.toJson().toString();
      expect(json, isNot(contains('nuevapass1')));
      expect(json, isNot(contains('klave')));
      // El estado sí cambió y queda registrado.
      expect((cambios['estado'] as Map)['despues'], 'BLOQUEADO');
    });

    test('solo nombre (POST/DELETE) y no-op fuera del wrapper', () async {
      final evento = await registrar(
        (request) => detalleRegistro(request, nombre: 'Cliente X'),
      );
      expect(evento.detalles?['nombre'], 'Cliente X');
      expect(evento.detalles?.containsKey('cambios'), isFalse);

      final suelto = peticion('DELETE', '/api/v1/clientes/9');
      expect(() => detalleRegistro(suelto, nombre: 'x'), returnsNormally);
    });
  });

  group('Auditorias (casos de uso)', () {
    test('listar convierte y pasa los filtros al repositorio', () async {
      await auditorias.listar(
        usuario: ' ana ',
        desde: '2026-09-01',
        hasta: '2026-09-30',
        entidad: 'usuarios',
        accion: 'CREAR',
      );

      final filtro = repo.ultimoFiltro!;
      expect(filtro.usuario, ' ana ');
      expect(filtro.desde, DateTime(2026, 9, 1));
      expect(filtro.hasta, DateTime(2026, 9, 30));
      expect(filtro.entidad, 'usuarios');
      expect(filtro.accion, 'CREAR');
    });

    test('contar aplica los mismos filtros y devuelve el total', () async {
      repo.eventos.addAll([
        AuditoriaEvento(
          fecha: DateTime(2026, 1, 10),
          nombreUsuario: 'ana',
          accion: 'CREAR',
          entidad: 'productos',
          resumen: 'POST /api/v1/productos -> 201',
        ),
        AuditoriaEvento(
          fecha: DateTime(2026, 1, 12),
          nombreUsuario: 'ana',
          accion: 'ACTUALIZAR',
          entidad: 'usuarios',
          resumen: 'PUT /api/v1/usuarios/2 -> 200',
        ),
        AuditoriaEvento(
          fecha: DateTime(2026, 1, 15),
          nombreUsuario: 'luis',
          accion: 'CREAR',
          entidad: 'productos',
          resumen: 'POST /api/v1/productos -> 201',
        ),
      ]);

      expect(await auditorias.contar(), 3);
      expect(await auditorias.contar(usuario: 'ana'), 2);
      expect(await auditorias.contar(entidad: 'productos'), 2);
      // Filtros combinados: solo el evento de ana sobre productos.
      expect(await auditorias.contar(usuario: 'ana', entidad: 'productos'), 1);
      // Fechas: ambos días incluidos (10 al 12 hay dos).
      expect(
        await auditorias.contar(desde: '2026-01-10', hasta: '2026-01-12'),
        2,
      );
      // Búsqueda libre sobre la fila (`q`): solo el resumen de usuarios.
      expect(await auditorias.contar(q: 'usuarios'), 1);

      // `listar` y `count` comparten filtros: la página cuadra con el total.
      final pagina = await auditorias.listar(usuario: 'ana', entidad: 'productos');
      expect(pagina, hasLength(1));
      expect(
        await auditorias.contar(usuario: 'ana', entidad: 'productos'),
        pagina.length,
      );
    });

    test('una fecha inválida responde 400 fecha_invalida', () {
      expect(
        () => auditorias.listar(desde: 'ayer'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'fecha_invalida',
          ),
        ),
      );
      expect(
        () => auditorias.limpiar('31-12-2025'),
        throwsA(
          isA<BadRequestException>().having(
            (e) => e.code,
            'code',
            'fecha_invalida',
          ),
        ),
      );
    });

    test('limpiar devuelve el recuento y limpiar vacía la tabla', () async {
      repo.eventos.addAll([
        for (final dia in [1, 15, 28]) _evento(DateTime(2026, 1, dia)),
      ]);

      // Antes del 20: los días 1 y 15 (2 eventos); queda el día 28.
      expect(await auditorias.limpiar('2026-01-20'), 2);
      expect(repo.eventos, hasLength(1));
      expect(await auditorias.limpiarTodo(), 1);
      expect(repo.eventos, isEmpty);
    });

    test('registrar no propaga el fallo de la BD', () async {
      repo.fallarAlRegistrar = true;
      await expectLater(
        auditorias.registrar(_evento(DateTime.now())),
        completes,
      );
    });
  });
}

/// Atajo: evento mínimo para los tests de casos de uso.
AuditoriaEvento _evento(DateTime fecha) => AuditoriaEvento(
  fecha: fecha,
  accion: 'CREAR',
  resumen: 'POST /api/v1/productos -> 201',
);
