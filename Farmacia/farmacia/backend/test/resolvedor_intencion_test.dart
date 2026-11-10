import 'package:farmacia_backend/src/data/database/database.dart';
import 'package:farmacia_backend/src/data/services/consultas/catalogo_consultas.dart';
import 'package:farmacia_backend/src/data/services/resolvedor_intencion.dart';
import 'package:test/test.dart';

/// BD de mentira: el lookup de productos devuelve una fila; el resto, vacío.
final class _FakeDb implements DatabaseConnection {
  final List<String> consultas = [];

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    consultas.add(sql);
    if (sql.contains('FROM usuarios')) {
      return [
        if (parameters.any(
          (p) => '$p'.contains('carlos') || '$p'.contains('cajero'),
        ))
          {'ok': 1},
      ];
    }
    if (sql.contains('FROM clientes')) {
      return [
        if (parameters.any((p) => '$p'.contains('garcia')))
          {'nombre_cliente': 'Maria Garcia'},
      ];
    }
    if (sql.contains('FROM categorias')) {
      return [
        if (parameters.any((p) => '$p'.contains('analgesico')))
          {'nombre_categoria': 'Analgésicos'},
      ];
    }
    if (sql.contains('ILIKE') && sql.contains('productos')) {
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
  final catalogo = catalogoConsultas();
  late _FakeDb db;
  late ResolvedorIntencion resolvedor;

  setUp(() {
    db = _FakeDb();
    resolvedor = ResolvedorIntencion(catalogo, db);
  });

  test('el catálogo reúne stock, ventas y otros y se describe para la IA',
      () async {
    expect(catalogo.funciones.length, greaterThanOrEqualTo(10));
    for (final nombre in [
      'producto_stock',
      'productos_extremo',
      'alertas_stock',
      'ventas_totales',
      'ventas_detalle',
      'conteo',
      'pedidos_pendientes',
    ]) {
      expect(catalogo.porNombre(nombre), isNotNull, reason: nombre);
    }
    final descripcion = catalogo.describir();
    expect(descripcion, contains('producto_stock'));
    expect(descripcion, contains('valores:'));
    expect(descripcion, contains('obligatorio'));
  });

  test('un saludo es conversacional, sin consultar la BD', () async {
    final decision = await resolvedor.resolver('¡Hola!');
    expect(decision, isA<Conversacional>());
    expect(db.consultas, isEmpty);
  });

  test('«qué está por vencer» elige alertas_stock con tipo por_vencer',
      () async {
    final decision = await resolvedor.resolver('¿qué está por vencer?');
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'alertas_stock');
    expect(ejecutar.parametros['tipo'], 'por_vencer');
  });

  test('«cuántos clientes tengo» elige conteo con la entidad correcta',
      () async {
    final decision = await resolvedor.resolver('¿cuántos clientes tengo?');
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'conteo');
    expect(ejecutar.parametros['entidad'], 'clientes');
  });

  test('«cuánto tengo de ibuprofeno» resuelve el nombre real de la BD',
      () async {
    final decision = await resolvedor.resolver(
      '¿cuánto tengo de ibuprofeno?',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'producto_stock');
    expect(ejecutar.parametros['nombre'], 'Ibuprofeno 400 mg');
  });

  test('producto que no existe → falta_info con la pregunta para el usuario',
      () async {
    final decision = await resolvedor.resolver(
      '¿cuánto tengo de ibuprofenio?',
    );
    expect(decision, isA<FaltaInfo>());
    expect((decision as FaltaInfo).pregunta, contains('producto'));
  });

  test('pregunta con producto no mencionado → falta_info', () async {
    final decision = await resolvedor.resolver('¿cuánto tengo de eso?');
    expect(decision, isA<FaltaInfo>());
    expect((decision as FaltaInfo).pregunta, contains('¿De qué producto'));
  });

  test('el periodo se extrae de la frase y si no, manda el defecto', () async {
    final conAyer = await resolvedor.resolver('¿cuánto vendí ayer?');
    expect(conAyer, isA<Ejecutar>());
    expect((conAyer as Ejecutar).parametros['periodo'], 'ayer');

    final sinPeriodo = await resolvedor.resolver('¿cuánto vendí?');
    expect(sinPeriodo, isA<Ejecutar>());
    expect((sinPeriodo as Ejecutar).parametros['periodo'], 'mes');
  });

  test('«mes pasado» es un periodo distinto de «mes»', () async {
    final decision = await resolvedor.resolver(
      '¿cuánto vendí el mes pasado?',
    );
    expect(decision, isA<Ejecutar>());
    expect((decision as Ejecutar).parametros['periodo'], 'mes_pasado');
  });

  test('«más barato» ordena por precio ascendente', () async {
    final decision = await resolvedor.resolver(
      '¿cuál es el producto más barato?',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'productos_extremo');
    expect(ejecutar.parametros['criterio'], 'mas_barato');
  });

  test('pregunta sin ninguna función aplicable → null (pasa a la IA)',
      () async {
    final decision = await resolvedor.resolver(
      'prefiero el color azul que el verde',
    );
    expect(decision, isNull);
    // El fallback por menciones puede haber consultado la BD buscando
    // productos/clientes, pero no decide nada sin coincidencias reales.
  });

  test('superlativo de ventas (incluso con typo) → ventas_detalle', () async {
    // Regresión: «qué procto he vendido mas» acababa en falta_info
    // preguntando por un producto que el usuario nunca mencionó.
    for (final pregunta in const [
      '¿de todos cual producto vendi mas?',
      '¿qué procto he vendido mas?',
      '¿que producto vendiste mas este mes?',
    ]) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, 'ventas_detalle', reason: pregunta);
      expect(decision.parametros['periodo'], isNotNull, reason: pregunta);
    }
  });

  test('«vence en 30 días» elige por_vencer (no stock_bajo)', () async {
    final decision = await resolvedor.resolver('¿que vence en 30 dias?');
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'alertas_stock');
    expect(ejecutar.parametros['tipo'], 'por_vencer');
    expect(ejecutar.parametros['dias'], '30');
  });

  test('«cuanto vale» sin producto → falta_info, no ninguna', () async {
    final decision = await resolvedor.resolver('¿y eso cuanto vale?');
    expect(decision, isA<FaltaInfo>());
  });

  test('«el más caro de la categoría» combina criterio + categoría', () async {
    final decision = await resolvedor.resolver(
      '¿el mas caro de la categoria analgesicos?',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'productos_extremo');
    expect(ejecutar.parametros['criterio'], 'mas_caro');
  });

  test('«cuántos productos de la categoría» cuenta la categoría, no todo',
      () async {
    final decision = await resolvedor.resolver(
      '¿cuantos productos de la categoria analgesicos?',
    );
    expect(decision, isA<Ejecutar>());
    expect((decision as Ejecutar).funcion, 'productos_categoria');
  });

  test('«menos de 10 unidades» extrae el umbral para stock_bajo', () async {
    final decision = await resolvedor.resolver(
      '¿productos con menos de 10 unidades?',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'alertas_stock');
    expect(ejecutar.parametros['umbral'], '10');
    expect(ejecutar.parametros['tipo'], 'stock_bajo');
  });

  test('«que producto tengo mas» es stock, no ventas', () async {
    for (final pregunta in const [
      '¿que producto tengo mas?',
      '¿que prodycto tengo mas?',
      'el que tengo mas no el vendido',
    ]) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, 'productos_extremo', reason: pregunta);
      expect(decision.parametros['criterio'], 'mas_stock', reason: pregunta);
    }
  });

  test('la negación anula «vendido mas»: la captura real es stock', () async {
    // «que producto tengo ma no cual vendido mas» (typo incluido): sin el
    // filtro de negación esto acababa en ventas_detalle, justo lo negado.
    final decision = await resolvedor.resolver(
      '¿que producto tengo ma no cual vendido mas?',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'productos_extremo');
    expect(ejecutar.parametros['criterio'], 'mas_stock');
  });

  test('«que cliente compra mas» es cliente_top, no un conteo', () async {
    for (final pregunta in const [
      '¿que cliente compra mas?',
      '¿cual es mi mejor cliente?',
      '¿que cliente gasto mas este mes?',
    ]) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, 'cliente_top', reason: pregunta);
    }
  });

  test('fallback por menciones: sin claves pero con algo real en la BD',
      () async {
    final producto = await resolvedor.resolver('¿tengo ibuprofeno?');
    expect(producto, isA<Ejecutar>());
    expect((producto as Ejecutar).funcion, 'producto_stock');
    expect(producto.parametros['nombre'], 'Ibuprofeno 400 mg');

    final cliente = await resolvedor.resolver('¿cliente garcia?');
    expect(cliente, isA<Ejecutar>());
    expect((cliente as Ejecutar).funcion, 'cliente_buscar');
    expect(cliente.parametros['nombre'], 'Maria Garcia');
  });

  test('cobros, IVA, roles y presentaciones tienen función propia', () async {
    final casos = <String, String>{
      '¿cuanto cobre en qr hoy?': 'pagos_resumen',
      '¿ventas en efectivo de hoy?': 'pagos_resumen',
      '¿cuanto iva lleve hoy?': 'facturas_resumen',
      '¿facturas del mes pasado?': 'facturas_resumen',
      '¿cuantos roles hay?': 'conteo',
      '¿cuantas presentaciones tenemos?': 'conteo',
      '¿productos en blister?': 'productos_presentacion',
      '¿que presentaciones hay?': 'productos_presentacion',
      '¿que ajustes hay?': 'ajustes_listar',
      '¿que rol tiene carlos_admin?': 'usuario_buscar',
      '¿usuarios con rol cajero?': 'usuario_buscar',
      '¿quien me provee ibuprofeno?': 'producto_stock',
    };
    for (final entrada in casos.entries) {
      final pregunta = entrada.key;
      final esperada = entrada.value;
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, esperada, reason: pregunta);
    }
  });

  test('cortesía con ruido: prefijos de saludo y agradecimiento', () async {
    for (final pregunta in const [
      'hola buenas como estas',
      'gracias por la ayuda',
      'buenos días, ¿cómo va todo?',
    ]) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Conversacional>(), reason: pregunta);
    }
  });

  test('«qué productos hay en X» con categoría real lista la categoría',
      () async {
    final decision = await resolvedor.resolver(
      '¿que productos hay en analgesicos?',
    );
    expect(decision, isA<Ejecutar>());
    final ejecutar = decision as Ejecutar;
    expect(ejecutar.funcion, 'productos_categoria');
    expect(ejecutar.parametros['categoria'], 'Analgésicos');
  });

  test('variantes sueltas: «el stock», «vende menos», «personal»', () async {
    final stock = await resolvedor.resolver('¿como esta el stock?');
    expect((stock as Ejecutar).funcion, 'inventario_resumen');

    final menos = await resolvedor.resolver('¿que se vende menos?');
    expect((menos as Ejecutar).funcion, 'ventas_detalle');
    expect(menos.parametros['criterio'], 'menos_vendido');

    final personal = await resolvedor.resolver('¿cuanto personal hay?');
    expect((personal as Ejecutar).funcion, 'conteo');
    expect(personal.parametros['entidad'], 'empleados');
  });

  test('ranking de vendedores: más y menos con su criterio', () async {
    final mas = await resolvedor.resolver('¿que vendedor vende mas?');
    expect(mas, isA<Ejecutar>());
    expect((mas as Ejecutar).funcion, 'vendedor_top');
    expect(mas.parametros['criterio'], 'mas_vendido');

    final menos = await resolvedor.resolver(
      '¿que vendedor es el que menos vende?',
    );
    expect((menos as Ejecutar).funcion, 'vendedor_top');
    expect(menos.parametros['criterio'], 'menos_vendido');
  });

  test('«quién ha vendido más» pregunta por personas, no por productos',
      () async {
    // Regresión: «que vendedor ha vendido mas productos» acababa en
    // ventas_detalle y se listaban productos en vez de vendedores.
    for (final pregunta in const [
      '¿que vendedor ha vendido mas productos?',
      '¿me refiero a que usuario ha vendido mas productos?',
      '¿que empleado vende mas?',
    ]) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, 'vendedor_top', reason: pregunta);
      expect(decision.parametros['criterio'], 'mas_vendido', reason: pregunta);
    }
  });

  test('«buscar/datos de» otra entidad no cae en productos ni en clientes',
      () async {
    final casos = <String, String>{
      '¿buscar empleado juan?': 'usuario_buscar',
      '¿datos del empleado juan?': 'usuario_buscar',
      '¿buscar rol cajero?': 'usuario_buscar',
      '¿buscar proveedor acme?': 'proveedor_buscar',
      '¿datos del proveedor acme?': 'proveedor_buscar',
      '¿que proveedores tenemos?': 'proveedor_buscar',
      '¿lista de usuarios?': 'usuario_buscar',
    };
    for (final entrada in casos.entries) {
      final decision = await resolvedor.resolver(entrada.key);
      expect(decision, isA<Ejecutar>(), reason: entrada.key);
      expect(
        (decision as Ejecutar).funcion,
        entrada.value,
        reason: entrada.key,
      );
    }
  });

  test('«que producto no se vende» → criterio sin_vender, no el top', () async {
    // Regresión: la negación caía en mas_vendido y respondía con los
    // productos MÁS vendidos.
    for (final pregunta in const [
      '¿que producto no se vende?',
      '¿productos sin ventas este mes?',
      '¿que no se vende?',
    ]) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, 'ventas_detalle', reason: pregunta);
      expect(decision.parametros['criterio'], 'sin_vender', reason: pregunta);
    }
  });

  test('el patrón «menos/sin» vale para clientes y categorías', () async {
    // La misma idea (más / menos / nada) con la función de cada tabla.
    final casos = <(String, String, String)>[
      ('¿que cliente gasto menos?', 'cliente_top', 'menos_compra'),
      ('¿peor cliente?', 'cliente_top', 'menos_compra'),
      ('¿que cliente no compra?', 'cliente_top', 'sin_compras'),
      ('¿clientes sin compras este mes?', 'cliente_top', 'sin_compras'),
      ('¿que categoria menos se vende?', 'ventas_categoria', 'menos_vendido'),
      ('¿la categoria mas vendida?', 'ventas_categoria', 'mas_vendido'),
      (
        '¿categorias sin ventas este mes?',
        'ventas_categoria',
        'sin_vender',
      ),
      ('¿que vendedor vende menos?', 'vendedor_top', 'menos_vendido'),
    ];
    for (final (pregunta, funcion, criterio) in casos) {
      final decision = await resolvedor.resolver(pregunta);
      expect(decision, isA<Ejecutar>(), reason: pregunta);
      expect((decision as Ejecutar).funcion, funcion, reason: pregunta);
      expect(decision.parametros['criterio'], criterio, reason: pregunta);
    }
  });

  test('el método de pago se mapea al dominio de la tabla pagos', () async {
    final decision = await resolvedor.resolver('¿cuanto cobre en qr hoy?');
    expect((decision as Ejecutar).parametros['metodo'], 'QR');
    final efectivo = await resolvedor.resolver(
      '¿ventas en efectivo de hoy?',
    );
    expect((efectivo as Ejecutar).parametros['metodo'], 'EFECTIVO');
  });

  test('ejecutar devuelve el resultado de la función del catálogo', () async {
    final texto = await resolvedor.ejecutar(
      const Ejecutar('inventario_resumen', {}),
    );
    expect(texto, contains('No hay productos'));
  });
}
