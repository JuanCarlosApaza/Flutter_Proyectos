import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/respaldo_usecases.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de los respaldos de la base de datos:
///
/// * `POST /api/v1/respaldos`                    -> genera un `.dump` ahora
/// * `GET  /api/v1/respaldos`                    -> listado (más reciente 1º)
/// * `GET  /api/v1/respaldos/{nombre}/descarga`  -> el fichero para guardar
///
/// Reutiliza el módulo de permisos `ajustes`: quien administra el sistema es
/// quien puede respaldarlo y bajárselo. La creación se audita sola (el
/// wrapper `auditarCambios` cubre todo `POST`).
void addRespaldoRoutes(
  Router router, {
  required Respaldos respaldos,
  Future<void> Function()? alCrear,
}) {
  router
    ..post('/api/v1/respaldos', (Request request) async {
      asegurarPermiso(request, 'ajustes', 'editar');
      final creado = await respaldos.respaldar();
      // Un respaldo a mano vuelve a poner en cero la cuenta del automático.
      await alCrear?.call();
      // `id: 0` como en los ajustes: el `Recurso.fromJson` del cliente
      // genérico exige un entero en toda respuesta, y el fichero no tiene
      // identificador propio (su clave natural es el nombre).
      return jsonResponse(201, {'id': 0, ...creado.toJson()});
    })
    ..get('/api/v1/respaldos', (Request request) async {
      asegurarPermiso(request, 'ajustes', 'ver');
      return listJsonResponse([
        for (final respaldo in respaldos.listar())
          {'id': 0, ...respaldo.toJson()},
      ]);
    })
    ..get('/api/v1/respaldos/<nombre>/descarga', (
      Request request,
      String nombre,
    ) async {
      asegurarPermiso(request, 'ajustes', 'editar');
      final bytes = await respaldos.leer(nombre);
      return Response(
        200,
        body: bytes,
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': '${bytes.length}',
          // El nombre ya viene validado por el repositorio (404 si no), así
          // que no hay cómo inyectar cabeceras desde la URL.
          'content-disposition': 'attachment; filename="$nombre"',
        },
      );
    });
}
