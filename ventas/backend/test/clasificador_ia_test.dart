import 'dart:convert';

import 'package:ventas_backend/src/data/database/database.dart';
import 'package:ventas_backend/src/data/services/clasificador_ia.dart';
import 'package:ventas_backend/src/data/services/consultas/catalogo_consultas.dart';
import 'package:ventas_backend/src/data/services/ollama_service.dart';
import 'package:ventas_backend/src/data/services/resolvedor_intencion.dart';
import 'package:test/test.dart';

/// BD de mentira: solo existe «Ibuprofeno 400 mg» (y un cliente concreto).
final class _FakeDb implements DatabaseConnection {
  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    if (sql.contains('FROM clientes')) {
      return [
        if (parameters.any((p) => '$p'.contains('mari'))) {'nombre': 'María'},
      ];
    }
    if (sql.contains('FROM productos')) {
      return [
        if (parameters.any((p) => '$p'.contains('ibuprofeno')))
          {'nombre_producto': 'Ibuprofeno 400 mg'},
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

void main() {
  final clasificador = ClasificadorIA(
    ollama: OllamaService(
      url: 'http://localhost:11434',
      modelo: 'x',
      peticion: (m, u, {cuerpo, timeout}) async => throw UnimplementedError(),
    ),
    catalogo: catalogoConsultas(),
    db: _FakeDb(),
  );

  test('JSON válido elige la función y aplica los defectos', () async {
    final decision = await clasificador.interpretar(
      '{"funcion": "ventas_totales", "parametros": {"periodo": "hoy"}}',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'ventas_totales');
    expect(ejecutar.parametros['periodo'], 'hoy');
  });

  test('parámetro no enviado cae en su valor por defecto', () async {
    final decision = await clasificador.interpretar(
      '{"funcion": "alertas_stock", "parametros": {}}',
    ) as Ejecutar;
    expect(decision.funcion, 'alertas_stock');
    expect(decision.parametros['tipo'], 'stock_bajo');
    expect(decision.parametros['dias'], '60');
  });

  test('valor fuera del dominio no se ejecuta: usa el defecto', () async {
    final decision = await clasificador.interpretar(
      '{"funcion": "ventas_totales", "parametros": {"periodo": "marzo"}}',
    );
    expect((decision as Ejecutar).parametros['periodo'], 'mes');
  });

  test('falta_info obligatorio sin valor → se pregunta al usuario', () async {
    final decision = await clasificador.interpretar(
      '{"funcion": "producto_stock", "parametros": {"nombre": ""}}',
    );
    expect(decision, isA<FaltaInfo>());
    expect((decision as FaltaInfo).pregunta, contains('producto'));
  });

  test('texto libre sucio («falta_info») no llega a ejecutarse', () async {
    // Un 1.5B a veces meta los literales del prompt en los parámetros.
    final decision = await clasificador.interpretar(
      '{"funcion": "ventas_producto", '
      '"parametros": {"nombre": "falta_info", "periodo": "mes"}}',
    );
    expect(decision, isA<FaltaInfo>());
    expect((decision as FaltaInfo).pregunta, contains('producto'));
  });

  test(
    'un producto inventado por el modelo no se consulta: se pregunta',
    () async {
      // «cifrado» es plausible como texto pero no existe en la BD.
      final decision = await clasificador.interpretar(
        '{"funcion": "ventas_producto", '
        '"parametros": {"nombre": "cifrado", "periodo": "ayer"}}',
      );
      expect(decision, isA<FaltaInfo>());
      expect((decision as FaltaInfo).pregunta, contains('producto'));
    },
  );

  test('un producto que sí existe en la BD pasa la validación', () async {
    final decision = await clasificador.interpretar(
      '{"funcion": "ventas_producto", '
      '"parametros": {"nombre": "ibuprofeno", "periodo": "mes"}}',
    );
    expect(decision, isA<Ejecutar>());
    expect((decision as Ejecutar).parametros['nombre'], 'ibuprofeno');
  });

  test('clientes se validan contra la tabla de clientes', () async {
    final existente = await clasificador.interpretar(
      '{"funcion": "cliente_buscar", "parametros": {"nombre": "maria"}}',
    );
    expect(existente, isA<Ejecutar>());

    final inventado = await clasificador.interpretar(
      '{"funcion": "cliente_buscar", "parametros": {"nombre": "cifrado"}}',
    );
    expect(inventado, isA<FaltaInfo>());
  });

  test('falta_info con la pregunta que manda el modelo', () async {
    final decision = await clasificador.interpretar(
      '{"funcion": "falta_info", "pregunta": "¿De qué día hablas?"}',
    );
    expect(decision, isA<FaltaInfo>());
    expect((decision as FaltaInfo).pregunta, '¿De qué día hablas?');
  });

  test('ninguna se traduce en la decisión de no encontrar', () async {
    expect(
      await clasificador.interpretar('{"funcion": "ninguna"}'),
      isA<Ninguna>(),
    );
  });

  test('función inventada por el modelo → ninguna', () async {
    expect(
      await clasificador.interpretar('{"funcion": "inventar_recetas"}'),
      isA<Ninguna>(),
    );
  });

  test('JSON roto → ninguna, sin excepciones', () async {
    expect(
      await clasificador.interpretar('lo siento, no entiendo'),
      isA<Ninguna>(),
    );
    expect(await clasificador.interpretar('{esto no es json'), isA<Ninguna>());
  });

  test('la respuesta puede venir con texto alrededor del JSON', () async {
    final decision = await clasificador.interpretar(
      'Claro: {"funcion": "conteo", "parametros": {"entidad": "clientes"}} '
      'es lo que buscas.',
    ) as Ejecutar;
    expect(decision.funcion, 'conteo');
    expect(decision.parametros['entidad'], 'clientes');
  });

  test('el prompt incluye ejemplos y la advertencia de no inventar', () {
    final prompt = clasificador.promptSistema();
    expect(prompt, contains('Ejemplos:'));
    expect(prompt, contains('ventas_totales'));
    expect(prompt, contains('NUNCA inventes nombres'));
    expect(prompt, contains('Catálogo'));
    expect(prompt, contains('historial'));
  });

  test('extrae la línea PENSO y el JSON de la misma respuesta', () async {
    const bruto =
        'PENSO: Quiere saber qué producto tiene con más STOCK, no el '
        'más vendido.\n'
        '{"funcion": "productos_extremo", "parametros": {"criterio": "mas_stock"}}';
    expect(
      ClasificadorIA.pensamientoDe(bruto),
      'Quiere saber qué producto tiene con más STOCK, no el más vendido.',
    );
    final decision = await clasificador.interpretar(bruto);
    expect((decision as Ejecutar).funcion, 'productos_extremo');
    // Sin línea PENSO → pensamiento vacío (no se muestra nada al usuario).
    expect(ClasificadorIA.pensamientoDe('{"funcion": "ninguna"}'), isEmpty);
  });

  test('PENSO sin JSON pide el JSON de repuesto (y lo conserva)', () async {
    var llamadas = 0;
    final conRepuesto = ClasificadorIA(
      ollama: OllamaService(
        url: 'http://localhost:11434',
        modelo: 'x',
        peticion: (m, u, {cuerpo, timeout}) async {
          llamadas++;
          final contenido = llamadas == 1
              ? 'PENSO: Quiere saber el stock de ibuprofeno.'
              : '{"funcion": "producto_stock", '
                    '"parametros": {"nombre": "ibuprofeno"}}';
          return (
            codigo: 200,
            cuerpo: '{"message":{"content":${jsonEncode(contenido)}}}',
          );
        },
      ),
      catalogo: catalogoConsultas(),
    );

    final r = await conRepuesto.clasificarConPensamiento(
      'cuanto tengo de ibuprofeno',
    );

    expect(llamadas, 2);
    expect((r.decision as Ejecutar).funcion, 'producto_stock');
    expect(r.pensamiento, 'Quiere saber el stock de ibuprofeno.');
  });

  test('con historial, la conversación previa viaja a Ollama', () async {
    final capturas = <List<dynamic>>[];
    final conHistorial = ClasificadorIA(
      ollama: OllamaService(
        url: 'http://localhost:11434',
        modelo: 'x',
        peticion: (m, u, {cuerpo, timeout}) async {
          capturas.add((cuerpo as Map)['messages'] as List);
          return (
            codigo: 200,
            cuerpo: '{"message":{"content":"{\\"funcion\\": \\"ninguna\\"}"}}',
          );
        },
      ),
      catalogo: catalogoConsultas(),
    );

    await conHistorial.clasificar(
      'y del mes pasado?',
      historial: [
        (rol: 'user', contenido: 'cuanto vendi ayer'),
        (rol: 'assistant', contenido: 'Ayer no hubo ventas.'),
      ],
    );

    // system + pregunta previa + respuesta previa + pregunta actual.
    expect(capturas.single, hasLength(4));
    expect((capturas.single.first as Map)['role'], 'system');
    expect((capturas.single[1] as Map)['content'], 'cuanto vendi ayer');
    expect((capturas.single[2] as Map)['role'], 'assistant');
    expect((capturas.single.last as Map)['content'], 'y del mes pasado?');
  });
}
