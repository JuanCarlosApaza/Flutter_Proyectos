import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/reporte_usecases.dart';
import '../http/api_request.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de reportes agregados del dashboard:
///
/// * `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc`
///
/// Devuelven **cifras agregadas** (unidades y monto por producto), no filas de
/// un CRUD: por eso viven en su propio módulo y no dentro de `venta_routes`.
///
/// Parámetros:
///
/// * `limite` (por defecto 6, 1..50) — cuántos productos se devuelven;
/// * `orden` — `desc` = más vendidos, `asc` = menos vendidos.
///
/// La respuesta usa la forma estándar de listado `{"total", "items"}` donde
/// `total` es el número de filas devueltas.
void addReporteRoutes(Router router, {required Reportes reportes}) {
  Future<Response> productosVendidos(Request request) async {
    // El ranking se muestra en el Dashboard: exige su permiso de lectura.
    asegurarPermiso(request, 'dashboard', 'ver');
    final items = await reportes.productosVendidos(
      limite: int.tryParse(request.url.queryParameters['limite'] ?? '') ?? 6,
      orden: queryOrNull(request, 'orden') ?? 'desc',
    );
    return listJsonResponse(items.map((e) => e.toJson()).toList());
  }

  router.get('/api/v1/reportes/productos-vendidos', productosVendidos);
}
