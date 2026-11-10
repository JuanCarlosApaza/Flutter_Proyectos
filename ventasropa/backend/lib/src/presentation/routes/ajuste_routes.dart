import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/rules/suscripcion.dart';
import '../../domain/usecases/ajuste_usecases.dart';
import '../http/api_request.dart';
import '../http/auditoria.dart';
import '../http/auth_middleware.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de los ajustes globales de la aplicación:
///
/// * `GET /api/v1/ajustes`        -> todos los ajustes guardados
/// * `PUT /api/v1/ajustes`        -> guarda un lote `{"valores": {clave: valor}}`
/// * `PUT /api/v1/ajustes/suscripcion` -> activa una suscripción con la clave
///   maestra (sin sesión: la clave es la autorización)
/// * `GET /api/v1/ajustes/suscripcion` -> estado de la suscripción
///
/// La lectura está abierta a cualquier sesión (todos los formularios los
/// necesitan para arrancar con sus valores por defecto); la escritura exige
/// el permiso `ajustes.editar`, que solo el rol ADMIN tiene por defecto
/// (quien puede cambiar el comportamiento del sistema).
///
/// [alGuardar] se invoca después de escribir: lo usa el programador de
/// respaldos para recalcular cuándo toca el próximo automático.
void addAjusteRoutes(
  Router router, {
  required Ajustes ajustes,
  Future<void> Function()? alGuardar,
}) {
  router
    ..get('/api/v1/ajustes', (Request request) async {
      final page = paginationOf(request);
      final items = await ajustes.listar(
        limit: page.limit,
        offset: page.offset,
      );
      return listJsonResponse([for (final item in items) item.toJson()]);
    })
    ..put('/api/v1/ajustes', (Request request) async {
      asegurarPermiso(request, 'ajustes', 'editar');
      final body = await readJsonObject(request);
      final valores = _leerValores(body);
      // El estado ANTES se lee antes de escribir (si no, el diff saldría vacío).
      final previos = {
        for (final ajuste in await ajustes.listar()) ajuste.clave: ajuste.valor,
      };
      final guardados = await ajustes.guardar(valores);
      // Diff antes→después de las claves que cambian, para la auditoría.
      detalleAuditoria(request, {
        'cambios': {
          for (final entrada in valores.entries)
            if (previos[entrada.key] != entrada.value)
              entrada.key: {
                'antes': previos[entrada.key] ?? '(sin guardar)',
                'despues': entrada.value,
              },
        },
      });
      // Acuse de escritura: un lote no es un registro, y el cliente genérico
      // del frontend exige un `id` entero en toda respuesta (`Recurso.fromJson`).
      final respuesta = jsonResponse(200, {
        'id': 0,
        'actualizados': guardados,
      });
      await alGuardar?.call();
      return respuesta;
    })
    ..put('/api/v1/ajustes/suscripcion', (Request request) async {
      // Sin sesión a propósito: la clave maestra es la autorización (el
      // middleware deja pasar esta ruta incluso con la suscripción
      // bloqueada, que es justo desde donde se reactiva).
      final body = await readJsonObject(request);
      final clave = requireText(body, 'clave', maxLength: 100);
      final duracion = requireText(body, 'duracion', maxLength: 20);
      if (!suscripcionClaveValida(clave)) {
        throw const ForbiddenException(
          'Clave de suscripción incorrecta.',
          code: 'clave_suscripcion_invalida',
        );
      }
      final hoy = DateTime.now();
      final vence = suscripcionVence(duracion, hoy);
      await ajustes.guardar({
        ajusteSuscripcionVence: vence,
        ajusteSuscripcionVista: suscripcionFecha(hoy),
      });
      // Auditoría con la duración y la fecha: la clave jamás se registra.
      detalleAuditoria(request, {'duracion': duracion, 'vence': vence});
      return jsonResponse(200, {'vence': vence, 'duracion': duracion});
    })
    ..get('/api/v1/ajustes/suscripcion', (Request request) async {
      sesionDe(request);
      final valores = {
        for (final ajuste in await ajustes.listar()) ajuste.clave: ajuste.valor,
      };
      final vence = valores[ajusteSuscripcionVence] ?? '';
      final evaluacion = comprobarSuscripcion(
        vence: vence,
        vista: valores[ajusteSuscripcionVista] ?? '',
        hoy: DateTime.now(),
      );
      return jsonResponse(200, {
        'vence': vence,
        'estado': vence.isEmpty
            ? 'libre'
            : (evaluacion.permitir ? 'activa' : 'bloqueada'),
        if (evaluacion.motivo != null) 'motivo': evaluacion.motivo,
      });
    });
}

/// Lee el objeto `{"valores": {...}}` y lo devuelve como `clave` → `valor`.
///
/// Solo se aceptan cadenas: los tipos los traduce el cliente (todo el ajuste
/// viaja como texto, igual que en la BD).
Map<String, String> _leerValores(Map<String, Object?> body) {
  final valores = body['valores'];
  if (valores is! Map) {
    throw const BadRequestException(
      'Se espera un objeto "valores" con los ajustes a guardar, '
      'p. ej. {"valores": {"porPagina": "10"}}.',
      code: 'valores_invalidos',
    );
  }

  final salida = <String, String>{};
  for (final entry in valores.entries) {
    final clave = entry.key;
    if (clave is! String) {
      throw const BadRequestException(
        'La clave de cada ajuste debe ser texto.',
        code: 'clave_invalida',
      );
    }
    final valor = entry.value;
    if (valor is! String) {
      throw BadRequestException(
        'El valor del ajuste "$clave" debe ser una cadena.',
        code: 'valor_invalido',
      );
    }
    salida[clave] = valor;
  }
  return salida;
}
