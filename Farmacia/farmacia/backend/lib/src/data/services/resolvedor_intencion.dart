import '../database/database.dart';
import 'consultas/catalogo.dart';

/// Decisión tomada para una pregunta, ya sea por palabras clave o por la IA.
sealed class Decision {
  const Decision();
}

/// Ejecuta la función del catálogo con estos parámetros ya validados.
final class Ejecutar extends Decision {
  const Ejecutar(this.funcion, this.parametros);

  final String funcion;
  final Map<String, String> parametros;
}

/// Falta una variable obligatoria: se le pregunta al usuario sin ejecutar.
final class FaltaInfo extends Decision {
  const FaltaInfo(this.pregunta);

  final String pregunta;
}

/// Nada encaja: respuesta directa del back, la IA no interviene.
final class Ninguna extends Decision {
  const Ninguna();
}

/// Conversación sin datos (saludos, agradecimientos, «¿qué puedes hacer?»).
final class Conversacional extends Decision {
  const Conversacional(this.respuesta);

  final String respuesta;
}

/// Paso 1 del pipeline: casar la pregunta con el catálogo sin llamar a la
/// IA (gratis e instantáneo). Si no hay match claro devuelve `null` para
/// que pase al clasificador.
///
/// La pregunta se normaliza (minúsculas, sin acentos) y cada función suma
/// peso por cada frase gatillo que aparezca: gana la de mayor puntuación.
final class ResolvedorIntencion {
  ResolvedorIntencion(this.catalogo, this.db);

  final CatalogoConsultas catalogo;
  final DatabaseConnection db;

  /// Palabras con las que no se busca producto ni categoría (muletillas):
  /// muletillas, verbos de pregunta y referencias temporales. Sin filtrar,
  /// «este» de «cuánto vendí **este** mes» casaba con «Gasas Est**este**riles».
  static const Set<String> _muletillas = {
    'cuanto', 'cuanta', 'cuantos', 'cuantas', 'cual', 'cuales', 'como',
    'donde', 'cuando', 'quien', 'quienes', 'porque', 'tengo', 'tienes',
    'tenemos', 'hay', 'esta', 'estan', 'estoy', 'puedo', 'puede', 'pueden',
    'dame', 'dime', 'dinos', 'hacer', 'hazme', 'producto', 'productos',
    'medicamento', 'medicamentos', 'farmacia', 'stock', 'precio', 'precios',
    'vender', 'venta', 'ventas', 'pago', 'pagos', 'orden', 'ordenes',
    'factura', 'facturas', 'cliente', 'clientes', 'del', 'de', 'la', 'el',
    'los', 'las', 'un', 'una', 'unos', 'unas', 'que', 'y', 'o', 'a', 'en',
    'con', 'para', 'por', 'su', 'sus', 'es', 'son', 'mi', 'mis', 'me',
    'te', 'se', 'lo', 'al', 'yo', 'mas', 'menos', 'todo', 'todos',
    // Tiempo y verbos: nunca son nombres de producto.
    'este', 'estos', 'estas', 'ese', 'esos', 'esas', 'ayer', 'hoy',
    'manana', 'semana', 'mes', 'ano', 'pasado', 'pasada', 'ultimo',
    'ultima', 'actual', 'actuales', 'vendi', 'vendio', 'vendidos',
    'vendido', 'vendida', 'vendidas', 'compre', 'comprado', 'quiere',
    'quiero', 'necesito', 'buscar', 'busco', 'busca', 'existe', 'existen',
    'saber', 'decir', 'ver', 'dias', 'dia',
    'telefono', 'correo', 'email', 'datos', 'cedula', 'apellido',
    'usuarios', 'presentaciones', 'tiene',
    // Personas y otras tablas: nunca son nombres de producto ni término
    // de búsqueda libre («buscar empleado juan» no busca en productos).
    'usuario', 'empleado', 'empleados', 'proveedor', 'proveedores',
  };

  /// Saludos y cortesías: se responden aquí sin tocar la BD ni la IA.
  static const Map<String, String> _cortesia = {
    'hola': '¡Hola! Pregúntame por stock, ventas, clientes o cotizaciones.',
    'buenas': '¡Buenas! Pregúntame por stock, ventas, clientes o cotizaciones.',
    'buenos dias': '¡Buenos días! ¿Qué necesitas saber del negocio?',
    'buenas tardes': '¡Buenas tardes! ¿Qué necesitas saber del negocio?',
    'buenas noches': '¡Buenas noches! ¿Qué necesitas saber del negocio?',
    'gracias': '¡A ti! Aquí sigo cuando quieras.',
    'grax': '¡A ti! Aquí sigo cuando quieras.',
    'adios': '¡Hasta luego!',
    'chao': '¡Hasta luego!',
    'que puedes hacer':
        'Puedo consultar stock, ventas, productos por vencer, clientes, '
        'pedidos pendientes y cotizaciones. Pregunta en lenguaje natural.',
    'que sabes hacer':
        'Puedo consultar stock, ventas, productos por vencer, clientes, '
        'pedidos pendientes y cotizaciones. Pregunta en lenguaje natural.',
    'que sabes': 'Puedo consultar stock, ventas, clientes y cotizaciones.',
    'ayuda': 'Pregúntame, por ejemplo: «¿qué vendí este mes?» o '
        '«¿qué está por vencer?».',
    'que puedes': 'Puedo consultar stock, ventas, clientes y cotizaciones.',
    'quien eres': 'Soy el asistente de la farmacia: consulto stock, '
        'ventas, clientes y cotizaciones por ti.',
    'quien eres tu': 'Soy el asistente de la farmacia: consulto stock, '
        'ventas, clientes y cotizaciones por ti.',
    'que eres': 'Soy el asistente interno de la farmacia.',
  };

  /// Devuelve la decisión, o `null` si la pregunta necesita al clasificador.
  Future<Decision?> resolver(String pregunta) async {
    final normalizada = normalizar(pregunta);
    if (normalizada.isEmpty) return null;

    final comoFrase = normalizada
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cortesia = _cortesia[comoFrase];
    if (cortesia != null) return Conversacional(cortesia);
    // Prefijos: «hola buenas, ¿cómo estás?» o «gracias por la ayuda»
    // también son cortesía… pero solo si la frase es corta: «buenas, me
    // puedes decir qué productos hay» empieza igual y es una consulta.
    if (comoFrase.length <= 25) {
      for (final inicio in const [
        'hola',
        'buenas',
        'buenos',
        'gracias',
        'chao',
        'adios',
      ]) {
        if (comoFrase.startsWith(inicio)) {
          return Conversacional(_cortesia[inicio] ?? _cortesia['hola']!);
        }
      }
    }

    // Fuera de alcance con forma fija: acciones sobre la BD, predicciones,
    // inglés y chit-chat personal. Se resuelven aquí, sin tocar la IA.
    if (RegExp(
      r'\b(what|how|when|where|why|which|please|tell me|could you)\b',
    ).hasMatch(comoFrase)) {
      return const Ninguna();
    }
    const fueraDeAlcance = [
      'me siento', 'como estoy', 'que tal estoy',
      'reponer stock', 'creame', 'crear', 'borrar', 'borrame',
      'eliminar', 'modificar', 'registrar', 'actualizar', 'guardar',
      'venderemos', 'vendere', 'vendera',
      'recomiendame', 'recomienda', 'recomendar',
      'tu vida', 'de tu vida',
      'costaba', 'valia',
      'curar', 'sintoma', 'dolor',
      'que tiempo', 'clima', 'llover', 'pasara manana',
      'apaga', 'enciende', 'escribe un', 'escribeme',
      'mejor marca', 'del mercado',
    ];
    if (fueraDeAlcance.any(comoFrase.contains)) return const Ninguna();

    // Aritmética («2 + 2», «2 mas 2»): nada del catálogo la resuelve y el
    // «cuanto es» de ventas respondería con una cifra de negocio.
    if (RegExp(r'\d\s*([+\-*/x×]|mas|menos|por)\s*\d').hasMatch(comoFrase)) {
      return const Ninguna();
    }

    final puntuado = _puntuar(normalizada);
    if (puntuado == null) return _decidirPorMenciones(normalizada);

    var (funcion, segunda) = puntuado;
    // «el más caro de analgésicos»: si gana productos_categoria pero otra
    // función también encaja y admite categoría, manda ESA con la categoría
    // (responde el «cuál», no lista la categoría entera). Y al revés con
    // «cuántos productos de la categoría X»: manda la que contesta el
    // conteo de ESA categoría, no el inventario general.
    if (funcion.nombre == 'productos_categoria' &&
        segunda != null &&
        segunda.parametros.any((p) => p.nombre == 'categoria')) {
      funcion = segunda;
    } else if (funcion.nombre == 'inventario_resumen' &&
        segunda?.nombre == 'productos_categoria') {
      funcion = segunda!;
    } else if (funcion.nombre == 'ventas_totales' &&
        segunda?.nombre == 'ventas_detalle' &&
        (normalizada.contains('top ') ||
            normalizada.contains('lo que mas') ||
            normalizada.contains('mas vendido'))) {
      // «top de ventas…»: el «ventas de» le daba más puntos a totales,
      // pero piden el ranking de productos.
      funcion = segunda!;
    }
    // «que productos hay en analgésicos»: si la frase nombra una categoría
    // real, listamos ESA categoría aunque la pregunta empiece con «buscar».
    if (funcion.nombre == 'productos_buscar') {
      final cat = await _categoriaMencionada(normalizada);
      if (cat != null) {
        funcion = catalogo.porNombre('productos_categoria') ?? funcion;
      }
    }
    // «de paracetamol cuanto vendi»: si las ventas ganan pero la frase
    // nombra un producto real, manda ventas_producto con ese nombre.
    if (funcion.nombre == 'ventas_totales' ||
        funcion.nombre == 'ventas_detalle') {
      final producto = await _productoMencionado(normalizada);
      if (producto != null) {
        funcion = catalogo.porNombre('ventas_producto') ?? funcion;
      }
    }
    // «¿qué vendedor/usuario ha vendido más productos?»: pregunta por
    // PERSONAS que venden, no por productos. Sin esto «vendido mas» gana
    // para ventas_detalle y se lista el top de productos.
    if ((funcion.nombre == 'ventas_detalle' ||
            funcion.nombre == 'ventas_totales') &&
        _esRankingDePersonas(normalizada)) {
      funcion = catalogo.porNombre('vendedor_top') ?? funcion;
    }
    final parametros = await _parametrosDe(funcion, normalizada);
    return _validar(funcion, parametros);
  }

  /// ¿Pregunta por quién vende? Persona (vendedor, empleado, usuario) +
  /// verbo de venta + superlativo («mas», «mejor», «quien», «top»).
  static bool _esRankingDePersonas(String t) =>
      RegExp(r'\b(vendedor|vendedores|empleado|empleados|usuario|usuarios)\b')
          .hasMatch(t) &&
      RegExp(r'\bvend\w*').hasMatch(t) &&
      RegExp(r'\b(mas|menos|mejor|mejores|quien|top)\b').hasMatch(t);

  /// Ejecuta la función decidida y devuelve su resultado en texto plano.
  Future<String> ejecutar(Ejecutar decision) async {
    final funcion = catalogo.porNombre(decision.funcion);
    if (funcion == null) return 'No encontré una respuesta para eso.';
    return funcion.ejecutar(db, decision.parametros);
  }

  /// Último recurso sin IA: si ninguna clave encajó pero la frase nombra
  /// algo real de la BD, se resuelve por mención directa.
  ///
  /// * «tengo ibuprofeno» / «donde tengo X» → stock de ese producto.
  /// * «cliente garcia» / «tienes a maria» → ese cliente.
  ///
  /// Si nada coincide, `null` → clasificador.
  Future<Decision?> _decidirPorMenciones(String t) async {
    const posesion = [
      'tengo', 'cuanto', 'donde', 'precio', 'cuesta', 'vale', 'queda',
      'stock',
    ];
    if (posesion.any(t.contains)) {
      final producto = await _productoMencionado(t);
      if (producto != null) {
        return Ejecutar(
          'producto_stock',
          Map.unmodifiable({'nombre': producto}),
        );
      }
    }
    final persona = await _personaMencionada(t);
    if (persona != null) {
      return Ejecutar('cliente_buscar', Map.unmodifiable({'nombre': persona}));
    }
    return null;
  }

  /// Puntúa cada función del catálogo y devuelve la mejor junto con la
  /// segunda (si la hay). Si empata o ninguna llega a un punto mínimo →
  /// `null` (al clasificador).
  ///
  /// **Dos pasadas**: primero con coincidencia exacta (como siempre); solo
  /// si NADA casó exacto se repite con tolerancia a typos («por venser»),
  /// y solo cuenta una clave cuya palabra tenga un error real — evita que
  /// palabras comunes suelten funciones falsas.
  (FuncionConsulta, FuncionConsulta?)? _puntuar(String normalizada) {
    final exacto = _puntuarCon(normalizada, conTypo: false);
    if (exacto != null) return exacto;
    return _puntuarCon(normalizada, conTypo: true);
  }

  (FuncionConsulta, FuncionConsulta?)? _puntuarCon(
    String normalizada, {
    required bool conTypo,
  }) {
    FuncionConsulta? mejor;
    var mejorPuntos = 0;
    FuncionConsulta? segunda;
    var segundoPuntos = 0;
    for (final funcion in catalogo.funciones) {
      var puntos = 0;
      for (final clave in funcion.claves) {
        final idx = normalizada.indexOf(clave);
        if (idx >= 0) {
          if (_estaNegada(normalizada, idx)) continue;
          puntos += clave.length;
          continue;
        }
        if (conTypo && _typosDe(normalizada, clave) > 0) {
          puntos += clave.length;
        }
      }
      if (puntos == 0) continue;
      if (puntos > mejorPuntos) {
        segundoPuntos = mejorPuntos;
        segunda = mejor;
        mejorPuntos = puntos;
        mejor = funcion;
      } else if (puntos > segundoPuntos) {
        segundoPuntos = puntos;
        segunda = funcion;
      }
    }
    if (mejor == null || mejorPuntos < 4) return null;
    // Empate entre dos funciones → decisión ambigua, mejor la IA.
    if (mejorPuntos == segundoPuntos) return null;
    return (mejor, segunda);
  }

  /// ¿Hay un «no» suelto inmediatamente antes de la clave (ventana de 10
  /// caracteres)? «no hay productos sin stock» no niega «sin stock» porque
  /// «no» queda demasiado lejos.
  static bool _estaNegada(String normalizada, int indice) {
    final previo = normalizada.substring(0, indice);
    final ventana = previo.length > 10
        ? previo.substring(previo.length - 10)
        : previo;
    return RegExp(r'\bno\b').hasMatch(ventana);
  }

  /// Cuántas palabras de la clave aparecen en la frase con un error real
  /// (typo), exigiendo que TODAS casen en orden y con como mucho un
  /// error cada una: «por venser» contiene «por vencer» — v/s es una
  /// sustitución. Devuelve 0 si la clave completa no casa o si no hizo
  /// falta corregir nada: contar coincidencias sin error real haría que
  /// palabras comunes suelten funciones falsas (la pasada exacta ya
  /// puntuó lo que casaba tal cual).
  static int _typosDe(String normalizada, String clave) {
    final tokens = normalizada
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    var desde = 0;
    var typos = 0;
    for (final palabra in clave.split(' ')) {
      if (palabra.isEmpty) continue;
      var encontrado = -1;
      for (var i = desde; i < tokens.length; i++) {
        if (_cerca(palabra, tokens[i])) {
          encontrado = i;
          if (tokens[i] != palabra) typos++;
          break;
        }
      }
      if (encontrado < 0) return 0;
      desde = encontrado + 1;
    }
    return typos;
  }

  /// Dos palabras con como mucho un error de edición (sustitución,
  /// inserción o borramiento); palabras de menos de 4 letras, exactas.
  static bool _cerca(String a, String b) {
    if (a == b) return true;
    if (a.length < 4 || b.length < 4) return false;
    if ((a.length - b.length).abs() > 1) return false;
    if (a.length == b.length) {
      var diferencias = 0;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          diferencias++;
          if (diferencias > 1) return false;
        }
      }
      return diferencias == 1;
    }
    final corta = a.length < b.length ? a : b;
    final larga = a.length < b.length ? b : a;
    var i = 0;
    var j = 0;
    var saltos = 0;
    while (i < corta.length && j < larga.length) {
      if (corta[i] == larga[j]) {
        i++;
        j++;
      } else {
        saltos++;
        j++;
        if (saltos > 1) return false;
      }
    }
    return true;
  }

  /// Extrae de la pregunta los valores de los parámetros de [funcion].
  ///
  /// Un parámetro obligatorio sin valor queda como cadena vacía para que
  /// [_validar] lo traduzca en `falta_info` con su propia pregunta.
  Future<Map<String, String>> _parametrosDe(
    FuncionConsulta funcion,
    String normalizada,
  ) async {
    final salida = <String, String>{};
    for (final parametro in funcion.parametros) {
      String? valor;
      switch (parametro.nombre) {
        case 'periodo':
          valor = _periodoDe(normalizada);
        case 'criterio':
          valor = _criterioDe(normalizada, funcion.nombre);
        case 'tipo':
          valor = _tipoAlertaDe(normalizada);
        case 'entidad':
          valor = _entidadDe(normalizada);
        case 'limite':
          valor = _numeroDe(normalizada, r'(\d+)\s*(?:productos|articulos)?');
        case 'dias':
          valor = _diasDe(normalizada);
        case 'umbral':
          valor = _umbralDe(normalizada);
        case 'nombre':
          // Cada función busca en su tabla: un cliente no está en productos
          // ni un usuario en la de clientes.
          valor = switch (funcion.nombre) {
            'cliente_buscar' => await _personaMencionada(normalizada),
            'usuario_buscar' => await _usuarioMencionado(normalizada),
            _ => await _productoMencionado(normalizada),
          };
        case 'presentacion':
          valor = await _buscarPorPalabras(
            normalizada,
            'presentaciones',
            'nombre_presentacion',
          );
        case 'metodo':
          valor = _metodoDe(normalizada);
        case 'termino':
          valor = _terminoLibre(normalizada);
        case 'categoria':
          valor = await _categoriaMencionada(normalizada);
      }
      if (valor == null || valor.isEmpty) {
        valor = parametro.defecto ?? '';
      }
      salida[parametro.nombre] = valor;
    }
    return salida;
  }

  /// Traduce la ausencia de parámetros obligatorios en `falta_info` o
  /// `ninguna` según toque.
  Decision _validar(FuncionConsulta funcion, Map<String, String> parametros) {
    for (final parametro in funcion.parametros) {
      if (!parametro.obligatorio) continue;
      if ((parametros[parametro.nombre] ?? '').isEmpty) {
        return FaltaInfo(
          parametro.pregunta ?? 'Falta un dato para responder eso.',
        );
      }
    }
    return Ejecutar(funcion.nombre, Map.unmodifiable(parametros));
  }

  /// Periodo explícito en la frase; `null` si no lo hay (luego manda el
  /// defecto de la función).
  String? _periodoDe(String t) {
    if (t.contains('mes pasado') || t.contains('mes anterior')) {
      return 'mes_pasado';
    }
    if (t.contains('ano pasado') || t.contains('el ano anterior')) {
      return 'anio';
    }
    if (t.contains('semana pasada') || t.contains('semana anterior')) {
      return 'semana_pasada';
    }
    if (t.contains('semana')) return 'semana';
    if (t.contains('este ano') || t.contains('ano en curso')) return 'anio';
    if (t.contains('hoy')) return 'hoy';
    if (t.contains('ayer')) return 'ayer';
    if (t.contains('mes') || t.contains('este mes')) return 'mes';
    // Mes con nombre («vendido en octubre»): solo el actual y el anterior
    // tienen periodo cerrado; el resto, que mande el defecto.
    const meses = <String, int>{
      'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5,
      'junio': 6, 'julio': 7, 'agosto': 8, 'septiembre': 9,
      'setiembre': 9, 'octubre': 10, 'noviembre': 11, 'diciembre': 12,
    };
    for (final mes in meses.entries) {
      if (t.contains(mes.key)) {
        final actual = DateTime.now().month;
        if (mes.value == actual) return 'mes';
        if (mes.value == (actual == 1 ? 12 : actual - 1)) return 'mes_pasado';
        return null;
      }
    }
    return null;
  }

  /// Criterio de orden según la función y la frase: el mismo patrón
  /// «más / menos / (nada) = sin…» vale para ventas, categorías y
  /// clientes — la consulta SQL es la misma con otro ORDER BY o NOT EXISTS.
  String? _criterioDe(String t, String funcion) {
    // Negación: «no se vende», «sin compras» → lista lo que NO pasa.
    final negado = RegExp(
      r'\b(sin ventas|sin vender|sin compras|no se vende|no vende|'
      r'no lo vende|nunca se vende|no se ha vendido|no las vende|'
      r'no compra|no compran|no la compra|no han comprado)\b',
    ).hasMatch(t);
    // «menos» / «peor» → el último de la lista.
    final ultimos = RegExp(
      r'\b(menos|peor|menor)\b',
    ).hasMatch(t);

    switch (funcion) {
      case 'ventas_detalle':
      case 'vendedor_top':
        if (negado) return 'sin_vender';
        if (ultimos) return 'menos_vendido';
        return 'mas_vendido';
      case 'ventas_categoria':
        if (negado) return 'sin_vender';
        if (ultimos) return 'menos_vendido';
        return 'mas_vendido';
      case 'cliente_top':
        if (negado) return 'sin_compras';
        if (ultimos) return 'menos_compra';
        return 'mas_compra';
    }
    if (t.contains('menos stock') || t.contains('menor stock')) {
      return 'menos_stock';
    }
    if (t.contains('mas caro') ||
        t.contains('precio mas alto') ||
        t.contains('mas caro')) {
      return 'mas_caro';
    }
    if (t.contains('mas barato') || t.contains('precio mas bajo')) {
      return 'mas_barato';
    }
    return 'mas_stock';
  }

  /// Subtipo de alerta de stock según la frase.
  String? _tipoAlertaDe(String t) {
    if (t.contains('por vencer') ||
        t.contains('vencen') ||
        t.contains('vence') ||
        t.contains('vencimiento') ||
        t.contains('caduc')) {
      return 'por_vencer';
    }
    if (t.contains('agotad') ||
        t.contains('sin stock') ||
        t.contains('sin existencias') ||
        t.contains('agoto')) {
      return 'agotados';
    }
    return 'stock_bajo';
  }

  /// Entidad para `conteo` según la frase.
  String? _entidadDe(String t) {
    // «cuanta gente» / «trabajadores» / «personal» sin decir «empleados».
    if (t.contains('gente') ||
        t.contains('trabajador') ||
        t.contains('personal')) {
      return 'empleados';
    }
    for (final entidad in const [
      'clientes',
      'proveedores',
      'empleados',
      'usuarios',
      'categorias',
      'productos',
      'ordenes',
      'cotizaciones',
      'facturas',
      'roles',
      'presentaciones',
      'pagos',
    ]) {
      if (t.contains(entidad)) return entidad;
    }
    return null;
  }

  String? _numeroDe(String t, String patron) {
    final m = RegExp(patron).firstMatch(t);
    return m?.group(1);
  }

  /// «en 30 días» → 30; si no, `null` (luego manda el defecto 60).
  String? _diasDe(String t) {
    final m = RegExp(r'(\d+)\s*dias?').firstMatch(t);
    return m?.group(1);
  }

  /// «menos de 10 unidades» → 10; si no, `null` (luego manda 5).
  String? _umbralDe(String t) =>
      RegExp(r'(?:menos de|bajo de|menor que)\s+(\d+)').firstMatch(t)?.group(1);

  /// Palabras de la frase que pueden ser el nombre de un producto.
  List<String> _claves(String t) => t
      .split(RegExp(r'[^a-z0-9]+'))
      .where((p) => p.length >= 4 && !_muletillas.contains(p))
      .toSet()
      .toList(growable: false);

  /// Busca el producto mencionado en la BD y devuelve su nombre real.
  ///
  /// Las palabras se prueban de la más larga (más específica) a la más
  /// corta: si «ibuprofeno» y «este» casan en la BD, que gane el primero y
  /// no el «este» de «Gasas Esteriles».
  Future<String?> _productoMencionado(String t) =>
      _buscarPorPalabras(t, 'productos', 'nombre_producto');

  /// Categoría mencionada, validada contra la BD (su nombre real).
  Future<String?> _categoriaMencionada(String t) =>
      _buscarPorPalabras(t, 'categorias', 'nombre_categoria');

  /// Cliente mencionado (nombre o apellido), validado contra la BD.
  Future<String?> _personaMencionada(String t) async {
    final palabras = _claves(t)..sort((a, b) => b.length.compareTo(a.length));
    for (final palabra in palabras.take(4)) {
      final filas = await db.query(
        'SELECT nombre_cliente FROM clientes '
        "WHERE estado <> 'ELIMINADO' "
        'AND (${ilike('nombre_cliente', 1)} OR ${ilike('apellido', 1)}) '
        'ORDER BY nombre_cliente ASC LIMIT 1',
        ['%$palabra%'],
      );
      if (filas.isNotEmpty) return filas.first['nombre_cliente']?.toString();
    }
    return null;
  }

  /// Usuario mencionado (login, nombre del empleado o rol). Devuelve la
  /// palabra encontrada — la función vuelve a buscar con ella y lista todos
  /// los que coincidan (p. ej. «cajero» → todos los cajeros).
  Future<String?> _usuarioMencionado(String t) async {
    final palabras = _claves(t)..sort((a, b) => b.length.compareTo(a.length));
    for (final palabra in palabras.take(4)) {
      final filas = await db.query(
        'SELECT 1 FROM usuarios u '
        'LEFT JOIN roles r ON r.rol_id = u.rol_id '
        'LEFT JOIN empleados e ON e.empleado_id = u.empleado_id '
        "WHERE u.estado <> 'ELIMINADO' "
        'AND (${ilike('u.nombre_usuario', 1)} '
        'OR ${ilike('e.nombre_empleado', 1)} OR ${ilike('r.nombre', 1)}) '
        'LIMIT 1',
        ['%$palabra%'],
      );
      if (filas.isNotEmpty) return palabra;
    }
    return null;
  }

  /// Método de pago de la frase → valor del dominio de `pagos.metodo_pago`.
  String? _metodoDe(String t) {
    const mapa = <(List<String>, String)>[
      (['tarjeta de credito', 'tarjeta credito', 'credito'], 'TARJETA_CREDITO'),
      (['tarjeta de debito', 'tarjeta debito', 'debito'], 'TARJETA_DEBITO'),
      (['tarjeta'], 'TARJETA'),
      (['efectivo', 'efectiva'], 'EFECTIVO'),
      (['qr'], 'QR'),
      (['yape'], 'YAPE'),
    ];
    for (final (claves, valor) in mapa) {
      if (claves.any(t.contains)) return valor;
    }
    return null;
  }

  Future<String?> _buscarPorPalabras(
    String t,
    String tabla,
    String columna,
  ) async {
    final palabras = _claves(t)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final palabra in palabras.take(4)) {
      final filas = await db.query(
        'SELECT $columna FROM $tabla '
        "WHERE estado <> 'ELIMINADO' "
        'AND ${ilike(columna, 1)} '
        'ORDER BY $columna ASC LIMIT 1',
        ['%$palabra%'],
      );
      if (filas.isNotEmpty) return filas.first[columna]?.toString();
    }
    return null;
  }

  /// Nombre libre para `productos_buscar` (no exige coincidencia previa).
  /// El mínimo es 3 letras para aceptar términos cortos como «xyz».
  String? _terminoLibre(String t) {
    final palabras = t
        .split(RegExp(r'[^a-z0-9]+'))
        .where((p) => p.length >= 3 && !_muletillas.contains(p))
        .take(4)
        .toList(growable: false);
    return palabras.isEmpty ? null : palabras.join(' ');
  }

  /// Normaliza para comparar: minúsculas, sin acentos y con el espaciado
  /// colapsado (cualquier blanco, incluidos los no separables, cuenta como
  /// un espacio): «cuanto␣␣vendi» sigue casando con «cuanto vendi».
  static String normalizar(String texto) {
    const mapa = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n', 'ç': 'c',
    };
    final buffer = StringBuffer();
    for (final caracter in texto.toLowerCase().split('')) {
      if (caracter != ' ' && caracter.trim().isEmpty) {
        // NBSP y compañía: cuentan como espacio normal.
        buffer.write(' ');
      } else {
        buffer.write(mapa[caracter] ?? caracter);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
