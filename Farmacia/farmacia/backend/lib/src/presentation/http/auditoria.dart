import 'package:shelf/shelf.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/auditoria.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/usecases/auditoria_usecases.dart';
import 'middlewares.dart';

/// Clave del `Map` de detalle que el wrapper inyecta en el context de la
/// request y que las rutas sensibles rellenan con [detalleAuditoria].
const String claveDetalleAuditoria = 'detalle_auditoria';

/// Clave interna para que una ruta sobrescriba la acción derivada
/// (p. ej. `RESTABLECER_CONTRASENA`).
const String _claveAccionPropia = '__accion';

/// Claves que **jamás** se guardan en `detalles` (defensa en profundidad:
/// aunque una ruta se despiste, ninguna contraseña/token llega a la BD).
const Set<String> _clavesProhibidas = {
  'contrasena',
  'claveadmin',
  'password',
  'token',
};

const Set<String> _mutaciones = {'POST', 'PUT', 'PATCH', 'DELETE'};

/// Envuelve las rutas para auditar **todas** las mutaciones.
///
/// Va dentro del middleware `autenticar` (en `app.dart`): el request ya
/// lleva la sesión inyectada y aquí se ve el resultado final —incluidas las
/// excepciones 403/400, que se registran como `exitoso = false` y se
/// relanzan para que `errorHandler` responda igual.
///
/// Lo que NO cubre: peticiones rechazadas **por el propio `autenticar`**
/// (token inválido/caducado), porque ese middleware es externo y no puede
/// verse a sí mismo; ahí no hay sesión que auditar de todos modos.
Handler auditarCambios(Handler inner, {required Auditorias auditorias}) =>
    (Request request) async {
      final metodo = request.method.toUpperCase();
      if (!_mutaciones.contains(metodo)) return inner(request);

      final detalle = <String, Object?>{};
      // Copia del context preservando la sesión que inyectó `autenticar`.
      final peticion = request.change(
        context: {...request.context, claveDetalleAuditoria: detalle},
      );

      try {
        final respuesta = await inner(peticion);
        await _registrar(
          auditorias: auditorias,
          request: peticion,
          detalle: detalle,
          metodo: metodo,
          status: respuesta.statusCode,
          // Los códigos de error vienen de las excepciones (rutas lanzan
          // AppException); si la ruta devolvió el error sin lanzar, el
          // `resumen` conserva el estado HTTP y `exitoso` marca el fallo.
          codigo: null,
        );
        return respuesta;
      } on AppException catch (error) {
        await _registrar(
          auditorias: auditorias,
          request: peticion,
          detalle: detalle,
          metodo: metodo,
          status: error.statusCode,
          codigo: error.code,
        );
        rethrow;
      } catch (_) {
        await _registrar(
          auditorias: auditorias,
          request: peticion,
          detalle: detalle,
          metodo: metodo,
          status: 500,
          codigo: 'internal_error',
        );
        rethrow;
      }
    };

/// Añade contexto al evento que se está registrando para la request actual.
///
/// Solo funciona dentro de [auditarCambios] (si no hay mapa inyectado, no
/// hace nada). [accion] sobrescribe la derivada del método HTTP.
void detalleAuditoria(
  Request request,
  Map<String, Object?> campos, {
  String? accion,
}) {
  final detalle = request.context[claveDetalleAuditoria];
  if (detalle is! Map<String, Object?>) return;
  detalle.addAll(campos);
  if (accion != null) detalle[_claveAccionPropia] = accion;
}

/// Nombre del registro + diff de los campos enviados: detalle genérico para
/// todo el CRUD (productos, clientes, categorías, cotizaciones...).
///
/// * [antes] → `toJson()` del registro **ANTES** de escribir.
/// * [despues] → el body de la petición.
/// * [campos] → `camposEnviados(...)` de la ruta.
///
/// Omite los campos cuyo valor **no cambió** — las fechas se comparan por
/// día, así un `2026-06-30` del body contra el `DateTime` de la BD cuenta
/// como igual — y nunca escribe credenciales (`contrasena`, `claveAdmin`...).
void detalleRegistro(
  Request request, {
  String? nombre,
  Map<String, Object?>? antes,
  Map<String, Object?>? despues,
  Set<String>? campos,
}) {
  final detalle = <String, Object?>{};
  if (nombre != null && nombre.isNotEmpty) detalle['nombre'] = nombre;

  final enviados = campos ?? despues?.keys.toSet() ?? const <String>{};
  if (enviados.isNotEmpty) detalle['campos'] = [...enviados]..sort();

  if (antes != null && despues != null) {
    final cambios = <String, Object?>{};
    for (final campo in enviados) {
      if (_clavesProhibidas.contains(campo.toLowerCase())) continue;
      if (!despues.containsKey(campo)) continue;
      final anterior = antes[campo];
      final nuevo = despues[campo];
      if (_valorNormalizado(anterior) == _valorNormalizado(nuevo)) continue;
      cambios[campo] = {'antes': anterior, 'despues': nuevo};
    }
    if (cambios.isNotEmpty) detalle['cambios'] = cambios;
  }

  if (detalle.isNotEmpty) detalleAuditoria(request, detalle);
}

/// Valor comparable: las fechas (`DateTime` o ISO) se reducen al día; el
/// resto, a texto. Así un campo reenviado igual por el formulario no
/// aparece como "cambio".
String _valorNormalizado(Object? valor) {
  if (valor is DateTime) return valor.toIso8601String().split('T').first;
  final texto = valor?.toString() ?? '';
  final fecha = DateTime.tryParse(texto);
  if (fecha != null && texto.length >= 10) return texto.substring(0, 10);
  return texto;
}

Future<void> _registrar({
  required Auditorias auditorias,
  required Request request,
  required Map<String, Object?> detalle,
  required String metodo,
  required int status,
  required String? codigo,
}) async {
  final sesion = request.context['sesion'];
  final cuenta = sesion is Sesion ? sesion.usuario : null;

  final ruta = request.requestedUri.path;
  final accionPropia = detalle.remove(_claveAccionPropia);
  final accion = accionPropia is String
      ? accionPropia
      : _accion(metodo, ruta, status);

  final (entidad, entidadId) = _entidad(ruta);

  await auditorias.registrar(
    AuditoriaEvento(
      fecha: DateTime.now(),
      usuarioId: cuenta?.id,
      nombreUsuario: cuenta?.nombreUsuario,
      rol: cuenta?.nivelUsuario,
      accion: accion,
      exitoso: status < 400,
      codigoError: status < 400 ? null : codigo,
      entidad: entidad,
      entidadId: entidadId,
      resumen: '$metodo $ruta -> $status',
      detalles: detalle.isEmpty ? null : _sanear(detalle),
      ip: ipCliente(request),
    ),
  );
}

/// LOGIN/LOGOUT según la ruta; para el resto, derivada del método.
String _accion(String metodo, String ruta, int status) {
  if (ruta.endsWith('/auth/login')) {
    return status < 400 ? 'LOGIN' : 'LOGIN_FALLIDO';
  }
  if (ruta.endsWith('/auth/logout')) return 'LOGOUT';
  return switch (metodo) {
    'POST' => 'CREAR',
    'DELETE' => 'ELIMINAR',
    _ => 'ACTUALIZAR',
  };
}

/// Segmento `api/v1/{entidad}/{id}` de la ruta (alias de la API incluidos).
(String, int?) _entidad(String ruta) {
  final segmentos = ruta
      .replaceFirst('/api/v1/', '')
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList();
  if (segmentos.isEmpty) return ('desconocida', null);
  final crudo = segmentos.first;
  final entidad = switch (crudo) {
    'products' => 'productos',
    'archivos' => 'archivos',
    _ => crudo,
  };
  final id = segmentos.length > 1 ? int.tryParse(segmentos[1]) : null;
  return (entidad, id);
}

/// Copia del detalle sin claves prohibidas (recursiva: también dentro de
/// mapas y listas anidados).
Map<String, Object?> _sanear(Map<String, Object?> origen) {
  final salida = <String, Object?>{};
  origen.forEach((clave, valor) {
    if (_clavesProhibidas.contains(clave.toLowerCase())) return;
    if (valor is Map) {
      salida[clave] = _sanear(Map<String, Object?>.from(valor));
    } else if (valor is List) {
      salida[clave] = [
        for (final elemento in valor)
          if (elemento is Map)
            _sanear(Map<String, Object?>.from(elemento))
          else
            elemento,
      ];
    } else {
      salida[clave] = valor;
    }
  });
  return salida;
}
