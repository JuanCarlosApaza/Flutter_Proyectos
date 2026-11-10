import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/log_asistente.dart';
import '../../data/services/clasificador_ia.dart';
import '../../data/services/descargador_modelo.dart';
import '../../data/services/narrador.dart';
import '../../data/services/ollama_service.dart';
import '../../data/services/resolvedor_intencion.dart';
import '../../domain/usecases/ajuste_usecases.dart';
import '../http/api_request.dart';
import '../http/auth_middleware.dart';
import '../http/json_response.dart';

/// Rutas del asistente IA local (Ollama):
///
/// * `GET  /api/v1/chat/estado`            → ollama + modelo + descarga
/// * `POST /api/v1/chat`                   → una respuesta del modelo
/// * `POST /api/v1/chat/modelo/descargar`  → 202 y arranca en segundo plano
/// * `GET  /api/v1/chat/modelo/descarga`   → progreso (la UI sondea)
///
/// El pipeline de `POST /api/v1/chat` es: palabras clave → clasificador IA
/// (elige función + variables del catálogo) → SQL cerrado → la IA redacta.
/// Si nada encaja, la respuesta sale del back sin que la IA intervenga.
///
/// Ninguna es pública: al no estar en `rutasPublicas`, el middleware exige
/// sesión para todas. No se pide ningún permiso concreto — cualquier rol
/// autenticado puede chatear salvo que el ajuste `iaRoles` lo restrinja
/// (en cuyo caso `POST /chat` devuelve `403 ia_no_permitido`) —, pero
/// [sesionDe] se llama igualmente para que una petición directa a la ruta
/// (sin pasar por el middleware, como en los tests) también devuelva 401.
void addChatRoutes(
  Router router, {
  required ModeloConversacion ollama,
  required ResolvedorIntencion resolvedor,
  required ClasificadorIA clasificador,
  required Narrador narrador,
  required DescargadorModelo descargador,
  required Ajustes ajustes,
}) {
  router
    ..get('/api/v1/chat/estado', (Request request) async {
      final sesion = sesionDe(request);
      // `permitido` es lo que la burbuja del frontend pinta: si el ajuste
      // `iaRoles` excluye a este rol, la burbuja no aparece (y si acaso
      // llega a preguntar, POST /chat devuelve 403).
      final permitido = await ajustes.puedeUsarIa(sesion.usuario?.nivelUsuario);
      // `modelos()` propaga el 503 si Ollama está; `modeloListo()` no,
      // porque se traga la excepción. Para distinguir «caído» de «sin
      // modelo» hace falta la lista cruda.
      var ollamaActivo = false;
      var modeloListo = false;
      try {
        final nombres = await ollama.modelos();
        ollamaActivo = true;
        modeloListo = nombres.any(
          (n) => n == ollama.modelo || n.startsWith('${ollama.modelo}:'),
        );
      } on AppException catch (error) {
        if (error.code != 'ollama_no_disponible') rethrow;
      }

      return jsonResponse(200, {
        'ollamaActivo': ollamaActivo,
        'modeloListo': modeloListo,
        'modelo': ollama.modelo,
        'permitido': permitido,
        'descarga': descargador.estado.toJson(),
      });
    })
    ..post('/api/v1/chat', (Request request) async {
      final sesion = sesionDe(request);
      // El ajuste `iaRoles` decide quién pregunta a la IA: fuera de la
      // lista, ni siquiera se llega al modelo (403, sin gastar tokens).
      if (!await ajustes.puedeUsarIa(sesion.usuario?.nivelUsuario)) {
        throw const ForbiddenException(
          'Tu rol no está habilitado para usar el asistente IA. '
          'Pídele a un administrador que lo active en Ajustes › Asistente IA.',
          code: 'ia_no_permitido',
        );
      }

      final cuerpo = await readJsonObject(request);
      final mensajes = _leerMensajes(cuerpo);
      final pregunta = mensajes.last.contenido;

      // 1) Palabras clave: gratis y sin IA. Si no hay match claro, 2) la IA
      // decide; y si las palabras clave ya decidieron, la IA pasa igual por
      // la fase PENSO («entiendo que me preguntas…») para que se vea el
      // razonamiento. El historial solo para anáforas/correcciones.
      final norm = ResolvedorIntencion.normalizar(pregunta);
      final necesitaHistorial =
          norm.startsWith(RegExp(r'^[ye]\s')) ||
          RegExp(
            r'\b(no cual|no el|no la|digo|me refiero|en vez de|'
            r'mas bien|repito|otra cosa)\b',
          ).hasMatch(norm);
      final historial = <({String rol, String contenido})>[
        if (necesitaHistorial)
          for (final m in mensajes.take(mensajes.length - 1))
            if (m.rol == 'user') m,
      ];

      final Decision decision;
      var pensamiento = '';
      try {
        final resuelto = await resolvedor.resolver(pregunta);
        if (resuelto == null) {
          final r = await clasificador.clasificarConPensamiento(
            pregunta,
            historial: historial,
          );
          pensamiento = r.pensamiento;
          var elegida = r.decision;
          // Si el PENSO corrigió los typos («por venser» → «por vencer»),
          // se reintenta el resolvedor con esa frase: la corrección del
          // modelo se aprovecha sin depender de su elección.
          if ((elegida is FaltaInfo || elegida is Ninguna) &&
              pensamiento.isNotEmpty) {
            final corregido = await resolvedor.resolver(pensamiento);
            if (corregido is Ejecutar) elegida = corregido;
          }
          decision = elegida;
        } else {
          decision = resuelto;
          // Decoración: la IA interpreta en claro la frase (corrige typos,
          // aclara negaciones). Si Ollama falla o el modelo no coincide con
          // la decisión por palabras clave, se contesta sin PENSO.
          if (decision is Ejecutar) {
            try {
              final r = await clasificador.clasificarConPensamiento(
                pregunta,
                historial: historial,
              );
              if (_coincide(decision, r.decision)) pensamiento = r.pensamiento;
            } catch (error) {
              logAsistente('interpretación omitida: $error');
            }
          }
        }
      } catch (error) {
        logAsistenteError('no pude decidir qué función usar: $error');
        rethrow;
      }

      final respuesta = switch (decision) {
        // Saludos, faltas de datos y «no encontré»: texto del back, sin IA.
        Conversacional(:final respuesta) => respuesta,
        FaltaInfo(:final pregunta) => pregunta,
        Ninguna() => noEncontrada,
        Ejecutar() => await ejecutarYRedactar(
          decision,
          pregunta: pregunta,
          resolvedor: resolvedor,
          narrador: narrador,
          pensamiento: pensamiento,
        ),
      };
      return jsonResponse(200, {
        'respuesta': respuesta,
        // Lo que la IA entendió («PENSO: …»): el frontend lo muestra como
        // un mensaje previo para que se vea el razonamiento.
        if (pensamiento.isNotEmpty) 'pensamiento': pensamiento,
      });
    })
    ..post('/api/v1/chat/modelo/descargar', (Request request) async {
      sesionDe(request);
      if (descargador.estado.activo) {
        // Ya hay una descarga en marcha: idempotente, sin duplicar trabajo.
        return jsonResponse(202, {'descarga': descargador.estado.toJson()});
      }
      if (await ollama.modeloListo()) {
        descargador.marcarListo();
        return jsonResponse(200, {
          'descarga': descargador.estado.toJson(),
          'motivo': 'ya_instalado',
        });
      }
      // Sin el binario no hay forma de registrar el modelo: se avisa antes
      // de bajar un GB que solo podría fallar al llegar al 100 %.
      if (!await descargador.comandoDisponible()) {
        throw const InfrastructureException(
          'No encuentro el comando `ollama`. Instálalo desde ollama.com, '
          'arráncalo con «ollama serve» y vuelve a intentarlo.',
          code: 'ollama_no_instalado',
        );
      }
      await descargador.iniciar();
      return jsonResponse(202, {'descarga': descargador.estado.toJson()});
    })
    ..get('/api/v1/chat/modelo/descarga', (Request request) async {
      sesionDe(request);
      return jsonResponse(200, {'descarga': descargador.estado.toJson()});
    });
}

/// Respuesta fija cuando nada del catálogo encaja: sin invitar a inventar.
const String noEncontrada =
    'No encontré una respuesta para eso. Puedo ayudarte con stock, ventas, '
    'clientes, pedidos y cotizaciones.';

/// ¿Coinciden las dos decisiones? El pensamiento de la IA solo se muestra
/// cuando el modelo y las palabras clave han elegido lo mismo: si se
/// contradicen, mejor no enseñar un razonamiento que no se siguió.
bool _coincide(Decision a, Decision b) {
  if (a is Ejecutar && b is Ejecutar) return a.funcion == b.funcion;
  return a is FaltaInfo && b is FaltaInfo;
}

/// Ejecuta la función elegida y, si devuelve datos, la IA los redacta.
///
/// Los resultados vacíos o de **varias líneas** (listas) se devuelven tal
/// cual: con un 1.5B narrar una lista acaba mal (eligió filas al azar e
/// inventó «8 productos» donde decía 8 unidades). Solo se narra un dato
/// escalar de una línea, que es donde el modelo es fiable.
Future<String> ejecutarYRedactar(
  Ejecutar decision, {
  required String pregunta,
  required ResolvedorIntencion resolvedor,
  required Narrador narrador,
  String pensamiento = '',
}) async {
  final datos = await resolvedor.ejecutar(decision);
  // Vacíos («No hay…», «Sin ventas…») y listas: respuesta directa, sin IA.
  if (datos.startsWith('Sin ') || datos.startsWith('No ')) return datos;
  final lineas = datos
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList(growable: false);
  if (lineas.length != 1) return datos;
  final redactado = await narrador.redactar(
    pregunta: pregunta,
    datos: datos,
    interpretacion: pensamiento,
  );
  return normalizaProsa(redactado);
}

/// Convierte en párrafo la lista con la que el modelo se cuela a veces.
///
/// Un 1.5B incumple el «sin viñetas» cuando los datos que recibe son una
/// lista: si TODAS las líneas menos la primera empiezan por «-» o por
/// «1.», se unen en una sola frase. También se descartan cabeceras tipo
/// «## DATOS» que a veces se filtran. Si no hay lista, devuelve el texto
/// tal cual.
String normalizaProsa(String texto) {
  final limpio = <String>[];
  for (final linea in texto.split('\n')) {
    final recortada = linea.trim();
    if (recortada.isEmpty) continue;
    if (recortada.startsWith('##')) continue; // cabeceras filtradas
    limpio.add(recortada);
  }
  if (limpio.length <= 1) return limpio.join('\n');

  final esVina = RegExp(r'^(-|\d+[.)])\s');
  final todasVina = limpio.skip(1).every((l) => esVina.hasMatch(l));
  if (!todasVina) return limpio.join('\n\n');

  final cuerpo = limpio
      .skip(1)
      .map((l) => l.replaceFirst(esVina, ''))
      .join(', ');
  final cabeza = limpio.first.replaceFirst(RegExp(r':\s*$'), '');
  return '$cabeza: $cuerpo';
}

/// Mensajes de la conversación: lista de `{role, content}`.
///
/// Validación de forma: no vacía, máximo 40 entradas y se recorta a las 20
/// últimas (el historial que el modelo ve de verdad; más entradas solo
/// alargarían el prompt y el 1.5B tiene 8K de ventana).
List<({String rol, String contenido})> _leerMensajes(
  Map<String, Object?> cuerpo,
) {
  final bruto = cuerpo['mensajes'];
  if (bruto is! List || bruto.isEmpty) {
    throw const BadRequestException(
      'El campo "mensajes" debe ser una lista no vacía de '
      '{role, content}.',
      code: 'mensajes_invalidos',
    );
  }
  if (bruto.length > 40) {
    throw const BadRequestException(
      'Máximo 40 mensajes por petición.',
      code: 'demasiados_mensajes',
    );
  }

  const rolesValidos = {'user', 'assistant'};
  final salida = <({String rol, String contenido})>[];
  for (final elemento in bruto) {
    if (elemento is! Map) {
      throw const BadRequestException(
        'Cada mensaje debe ser un objeto {role, content}.',
        code: 'mensaje_invalido',
      );
    }
    final mapa = elemento.cast<String, Object?>();
    final rol = mapa['role']?.toString().trim() ?? '';
    final contenido = mapa['content']?.toString().trim() ?? '';
    if (!rolesValidos.contains(rol)) {
      throw const BadRequestException(
        'El campo "role" debe ser "user" o "assistant".',
        code: 'role_invalido',
      );
    }
    if (contenido.isEmpty) {
      throw const BadRequestException(
        'Cada mensaje necesita "content" con texto.',
        code: 'content_vacio',
      );
    }
    if (contenido.length > 4000) {
      throw const BadRequestException(
        'Un mensaje no puede superar 4000 caracteres.',
        code: 'content_largo',
      );
    }
    salida.add((rol: rol, contenido: contenido));
  }

  return salida.length > 20 ? salida.sublist(salida.length - 20) : salida;
}
