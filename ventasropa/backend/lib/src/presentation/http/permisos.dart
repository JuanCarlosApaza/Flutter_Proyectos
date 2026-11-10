import 'package:shelf/shelf.dart';

import '../../core/errors/app_exception.dart';
import 'auth_middleware.dart';

/// Comprobación de permisos (`módulo.accion`) dentro de una ruta.
///
/// La sesión ya la ha validado el middleware [autenticar]; aquí se comprueba
/// que su rol tiene el permiso que la operación exige. Sin permiso → `403`
/// con `code = 'permiso_denegado'`.
///
/// ```dart
/// ..get('/api/v1/products', (Request request) async {
///   asegurarPermiso(request, 'productos', 'ver');
///   ...
/// })
/// ```
void asegurarPermiso(Request request, String modulo, String accion) {
  final usuario = sesionDe(request).usuario;
  if (usuario == null || !usuario.tienePermiso(modulo, accion)) {
    throw ForbiddenException(
      'La cuenta no tiene permiso para "$modulo.$accion".',
      code: 'permiso_denegado',
    );
  }
}
