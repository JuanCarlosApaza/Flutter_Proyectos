import 'dart:convert';

import '../../core/log_asistente.dart';
import '../database/database.dart';
import 'ollama_service.dart';
import 'consultas/catalogo.dart';
import 'resolvedor_intencion.dart';

/// Paso 2 del pipeline: cuando las palabras clave no casan, la IA elige
/// función + parámetros de las listas del catálogo y devuelve **solo JSON**.
///
/// El modelo nunca razona sobre datos ni escribe SQL: clasifica entre
/// `falta_info` (le falta una variable y pregunta), `ninguna` (no hay
/// función para eso) y las funciones del catálogo. Cualquier respuesta
/// ilegible o fuera del catálogo cae en [Ninguna], y los valores de texto
/// libre (nombres de producto…) se **validan contra la base de datos**:
/// un 1.5B inventa nombres con total naturalidad y no llegan a ejecutarse.
final class ClasificadorIA {
  ClasificadorIA({required this.ollama, required this.catalogo, this.db});

  /// Motor del lenguaje (Ollama en PC o llama.cpp local en la APK).
  final ModeloConversacion ollama;
  final CatalogoConsultas catalogo;

  /// BD opcional para validar nombres inventados; sin ella (tests simples)
  /// se confía en el texto plausible.
  final DatabaseConnection? db;

  /// [historial] son los mensajes anteriores (máx. los últimos4): si la
  /// pregunta depende de la anterior («¿y del mes pasado?»), el modelo los
  /// usa para elegir función y periodo. Sin historial, solo la pregunta.
  Future<Decision> clasificar(
    String pregunta, {
    List<({String rol, String contenido})> historial = const [],
  }) async =>
      (await clasificarConPensamiento(pregunta, historial: historial))
          .decision;

  /// Igual que [clasificar] pero devuelve además la línea **PENSO**: lo que
  /// el modelo entendió de la frase del usuario (con los typos corregidos y
  /// las negaciones aclaradas) antes de decidir. Es lo que se muestra al
  /// usuario para que se vea el razonamiento.
  Future<({Decision decision, String pensamiento})> clasificarConPensamiento(
    String pregunta, {
    List<({String rol, String contenido})> historial = const [],
  }) async {
    final previos = historial.length > 4
        ? historial.sublist(historial.length - 4)
        : historial;
    final mensajes = [...previos, (rol: 'user', contenido: pregunta)];
    final bruto = await ollama.chat(
      contexto: promptSistema(),
      mensajes: mensajes,
    );
    var decision = await interpretar(bruto);
    final pensamiento = pensamientoDe(bruto);
    // El 1.5B a veces se queda en la línea PENSO y olvida el JSON: si no
    // hay ni llaves, se le pide el JSON con su propia interpretación a la
    // vista (una sola llamada de repuesto, solo en ese caso).
    if (decision is Ninguna && pensamiento.isNotEmpty && !bruto.contains('{')) {
      logAsistente('PENSO sin JSON: pido el JSON de repuesto');
      final bruto2 = await ollama.chat(
        contexto: promptSistema(),
        mensajes: [
          ...mensajes,
          (rol: 'assistant', contenido: bruto),
          (
            rol: 'user',
            contenido:
                'Falta el JSON. Devuelve SOLO el JSON con la función que '
                'elegiste en tu PENSO.',
          ),
        ],
      );
      decision = await interpretar(bruto2);
    }
    return (decision: decision, pensamiento: pensamiento);
  }

  /// Extrae la línea «PENSO: …» de la respuesta del modelo (vacío si no la
  /// trae). Solo se toma la primera línea que empiece por «penso:».
  static String pensamientoDe(String bruto) {
    for (final linea in bruto.split('\n')) {
      final recortada = linea.trim();
      if (recortada.toLowerCase().startsWith('penso:')) {
        return recortada.substring(recortada.indexOf(':') + 1).trim();
      }
    }
    return '';
  }

  /// Convierte la respuesta del modelo en una [Decision] validándola contra
  /// el catálogo: si se sale del catálogo, la decisión es `ninguna`.
  Future<Decision> interpretar(String bruto) async {
    final inicio = bruto.indexOf('{');
    final fin = bruto.lastIndexOf('}');
    if (inicio < 0 || fin < inicio) return const Ninguna();

    Map<String, Object?> cuerpo;
    try {
      final decodificado = jsonDecode(bruto.substring(inicio, fin + 1));
      if (decodificado is! Map<String, Object?>) return const Ninguna();
      cuerpo = decodificado;
    } on FormatException catch (error) {
      logAsistenteError('clasificador devolvió JSON ilegible: $error');
      return const Ninguna();
    }

    final funcion = cuerpo['funcion']?.toString().trim() ?? '';
    if (funcion == 'ninguna' || funcion.isEmpty) return const Ninguna();
    if (funcion == 'falta_info') {
      final pregunta = cuerpo['pregunta']?.toString().trim() ?? '';
      if (pregunta.isEmpty) {
        return const FaltaInfo('¿Puedes darme algún dato más para eso?');
      }
      return FaltaInfo(pregunta);
    }

    final definicion = catalogo.porNombre(funcion);
    if (definicion == null) return const Ninguna();

    final brutoParametros = cuerpo['parametros'];
    final parametros = brutoParametros is Map
        ? brutoParametros
              .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
        : <String, String>{};

    return _validarParametros(definicion, parametros);
  }

  /// Aplica dominios, defectos y obligatorios a lo que dijo el modelo.
  Future<Decision> _validarParametros(
    FuncionConsulta definicion,
    Map<String, String> parametros,
  ) async {
    final salida = <String, String>{};
    for (final parametro in definicion.parametros) {
      var valor = (parametros[parametro.nombre] ?? '').trim();

      if (valor.isNotEmpty) {
        if (parametro.valores != null && !parametro.valores!.contains(valor)) {
          // Valor fuera del dominio: no se ejecuta con algo inventado.
          valor = parametro.defecto ?? '';
        } else if (parametro.esNumero && int.tryParse(valor) == null) {
          valor = parametro.defecto ?? '';
        } else if (parametro.valores == null && !_esTextoPlausible(valor)) {
          // Texto libre sucio («falta_info», JSON roto…): se descarta y si
          // era obligatorio, se pregunta al usuario.
          valor = parametro.defecto ?? '';
        } else if (parametro.valores == null &&
            parametro.nombre != 'termino' &&
            db != null &&
            !await _existe(definicion, parametro.nombre, valor)) {
          // El modelo se inventó un nombre: mejor preguntar al usuario que
          // ejecutar una consulta contra algo que no está en la BD.
          return FaltaInfo(
            parametro.pregunta ?? 'Falta un dato para responder eso.',
          );
        }
      } else {
        valor = parametro.defecto ?? '';
      }

      if (valor.isEmpty && parametro.obligatorio) {
        return FaltaInfo(
          parametro.pregunta ?? 'Falta un dato para responder eso.',
        );
      }
      salida[parametro.nombre] = valor;
    }
    return Ejecutar(definicion.nombre, Map.unmodifiable(salida));
  }

  /// ¿Existe ese nombre en la BD? (ILIKE, como haría la consulta final).
  Future<bool> _existe(
    FuncionConsulta definicion,
    String parametro,
    String valor,
  ) async {
    // Usuarios: login, nombre del empleado o rol (toca tres tablas).
    if (definicion.nombre == 'usuario_buscar' && parametro == 'nombre') {
      final filas = await db!.query(
        'SELECT 1 FROM usuarios u '
        'LEFT JOIN roles r ON r.rol_id = u.rol_id '
        'LEFT JOIN empleados e ON e.empleado_id = u.empleado_id '
        "WHERE u.estado <> 'ELIMINADO' "
        'AND (${ilike('u.nombre_usuario', 1)} '
        'OR ${ilike('e.nombre_empleado', 1)} OR ${ilike('r.nombre', 1)}) '
        'LIMIT 1',
        ['%$valor%'],
      );
      return filas.isNotEmpty;
    }
    final (tabla, columnas) = switch ((definicion.nombre, parametro)) {
      ('cliente_buscar', 'nombre') => (
        'clientes',
        const ['nombre_cliente', 'apellido', 'ci'],
      ),
      (_, 'categoria') => ('categorias', const ['nombre_categoria']),
      (_, 'presentacion') => (
        'presentaciones',
        const ['nombre_presentacion'],
      ),
      (_, 'nombre') => ('productos', const ['nombre_producto']),
      _ => (null, const <String>[]),
    };
    if (tabla == null) return true;

    final base = tabla == 'clientes' ? 'p' : 't';
    final condiciones = [
      for (final columna in columnas) ilike('$base.$columna', 1),
    ];
    final filas = await db!.query(
      'SELECT 1 FROM $tabla $base '
      "WHERE $base.estado <> 'ELIMINADO' "
      'AND (${condiciones.join(' OR ')}) LIMIT 1',
      ['%$valor%'],
    );
    return filas.isNotEmpty;
  }

  /// Un texto plausible para parámetros libres: letras (con acentos),
  /// números, espacios, guiones bajos (logins como `carlos_admin`) y
  /// puntuación básica. Lo que sea basura («falta_info» con espacios
  /// raros, JSON…) lo pilla la validación contra la BD posterior.
  static bool _esTextoPlausible(String valor) =>
      valor.length >= 3 &&
      !valor.contains('__') &&
      RegExp(r"^[a-záéíóúüñ0-9_][a-záéíóúüñ0-9 _.,'()-]*$")
          .hasMatch(valor.toLowerCase());

  /// Prompt del clasificador: instrucciones + ejemplos + catálogo generado
  /// en código. Es público para que las herramientas de diagnóstico lo vean.
  String promptSistema() => '''
Eres el selector de funciones de un asistente interno de farmacia.
Tu única tarea es entender qué pregunta el usuario, elegir UNA función del
catálogo y rellenar sus parámetros. NO respondas a la pregunta, NO inventes
datos: primero razonas en claro y luego devuelves el JSON.

ANTES del JSON escribe EXCLUSIVAMENTE una línea que empiece por «PENSO:»
en la que reformules lo que el usuario quiere saber:
- CORRIGIENDO sus errores ortográficos y gramaticales (typos),
- diciendo lo que SÍ pide si niega algo,
- y si depende de la pregunta anterior, mencionándolo.
Una sola línea, sin ejemplos de JSON dentro.

Ejemplo:
P: que prodycto tengo ma no cual vendido mas
PENSO: Quiere saber qué producto tiene con más STOCK, no el más vendido.
{"funcion": "productos_extremo", "parametros": {"criterio": "mas_stock"}}

Reglas:
- El JSON es OBLIGATORIO: después de tu línea «PENSO:» SIEMPRE va el
  objeto JSON (sin más texto). El PENSO NO es una respuesta al usuario ni
  sustituye al JSON: si solo escribes PENSO, has fallado.
- Si la pregunta necesita una función y falta un parámetro obligatorio que
  no se deduce de la frase, devuelve:
  {"funcion": "falta_info", "pregunta": "<una pregunta corta en español
  para que el usuario complete el dato>"}
- Si ninguna función encaja (algo que no es del negocio: clima, chistes,
  recetas, cálculos que no están en el catálogo), devuelve:
  {"funcion": "ninguna"}
- Nunca inventes nombres de funciones ni valores fuera de los dominios.
- En "nombre" pon el producto tal como lo menciona el usuario; si la frase
  no menciona ningún producto, usa falta_info. NUNCA inventes nombres.
- EXCEPCIÓN: un superlativo de ventas («qué/vendi más/menos vendido»,
  «de todos cuál vendí más») NO necesita producto concreto: es
  `ventas_detalle` con su periodo. No respondas falta_info ahí.
- Si la frase no deja claro el periodo (hoy, ayer, semana, mes…), NO
  incluyas "periodo" en parametros: se usará el valor por defecto.
- Si la frase menciona un número de días («en 30 días», «próximos 7»),
  ponlo en "dias" como número.
- Acciones sobre la BD (crear, borrar, modificar, reponer, registrar)
  y predicciones («cuánto venderé») → `ninguna`.
- Si preguntan un precio o dato de otro día («¿costaba ayer?») y ninguna
  función lo da → `ninguna`.
- `falta_info` es SOLO para un parámetro que falta de una función que ya
  has elegido; para preguntas que no son del negocio (salud, recetas,
  opiniones, vida personal) responde `ninguna`, nunca falta_info.
- Puede haber historial de la conversación (solo las preguntas previas):
  es CONTEXTO, no la pregunta a decidir. Decide SIEMPRE sobre la ÚLTIMA
  pregunta y elige la función que mejor la cubra — «ninguna» es el último
  recurso, no la respuesta por ver historial.
- Si la frase niega algo («no el vendido», «no la de ayer») o corrige la
  pregunta anterior, haz caso a lo que SÍ pide, no a las palabras negadas.

Ejemplos:
P: ¿cuánto vendí ayer?
{"funcion": "ventas_totales", "parametros": {"periodo": "ayer"}}
P: ¿qué vendiste más el mes pasado?
{"funcion": "ventas_detalle", "parametros": {"periodo": "mes_pasado"}}
P: de todos cual producto vendi mas
{"funcion": "ventas_detalle", "parametros": {"periodo": "mes"}}
P: ¿qué procto he vendido más?
{"funcion": "ventas_detalle", "parametros": {"periodo": "mes"}}
P: ¿y la paracetamol? (la anterior preguntaba «cuanto tengo de ibuprofeno»)
{"funcion": "producto_stock", "parametros": {"nombre": "paracetamol"}}
P: ¿cómo van las categorías?
{"funcion": "ventas_categoria", "parametros": {}}
P: ¿cuánto tengo de ibuprofeno?
{"funcion": "producto_stock", "parametros": {"nombre": "ibuprofeno"}}
P: busca cliente garcia
{"funcion": "cliente_buscar", "parametros": {"nombre": "garcia"}}
P: ¿cuántos clientes tengo?
{"funcion": "conteo", "parametros": {"entidad": "clientes"}}
P: ¿qué cliente compra más?
{"funcion": "cliente_top", "parametros": {}}
P: ¿qué rol tiene carlos_admin?
{"funcion": "usuario_buscar", "parametros": {"nombre": "carlos_admin"}}
P: ¿cuánto cobré en QR hoy?
{"funcion": "pagos_resumen", "parametros": {"periodo": "hoy", "metodo": "QR"}}
P: productos en blister
{"funcion": "productos_presentacion", "parametros": {"presentacion": "blister"}}
P: ¿qué vendedor vende más?
{"funcion": "vendedor_top", "parametros": {"criterio": "mas_vendido"}}
P: ¿qué vendedor es el que menos vende?
{"funcion": "vendedor_top", "parametros": {"criterio": "menos_vendido"}}
P: ¿qué está por vencer?
{"funcion": "alertas_stock", "parametros": {"tipo": "por_vencer"}}
P: ¿cómo me fue con eso?
{"funcion": "falta_info", "pregunta": "¿Sobre qué producto o venta?"}
P: recétame algo para la gripe
{"funcion": "ninguna"}
P: dime un secreto
{"funcion": "ninguna"}
P: ¿quién eres tú?
{"funcion": "ninguna"}

Formato de éxito:
{"funcion": "<nombre>", "parametros": {"<parametro>": "<valor>"}}

Catálogo (nombre, parámetros, dominios y valores por defecto):
${catalogo.describir()}
''';
}
