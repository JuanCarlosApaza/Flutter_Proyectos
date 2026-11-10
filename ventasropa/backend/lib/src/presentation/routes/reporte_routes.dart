import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/reporte_usecases.dart';
import '../http/api_request.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de reportes agregados:
///
/// * `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc`
///   → rankings del **dashboard** (permiso `dashboard.ver`).
/// * `GET /api/v1/reportes/ventas?desde=&hasta=&agrupacion=`
///   → resumen y serie de **ventas por día / mes / año** (permiso
///   `reportes.ver`).
/// * `GET /api/v1/reportes/ventas-productos?desde=&hasta=`
///   → **ventas por producto y por categoría** del rango (mismo permiso).
///
/// Devuelven **cifras agregadas** (unidades y monto por producto o periodo),
/// no filas de un CRUD: por eso viven en su propio módulo y no dentro de
/// `venta_routes`.
///
/// Parámetros del ranking del dashboard:
///
/// * `limite` (por defecto 6, 1..50) — cuántos productos se devuelven;
/// * `orden` — `desc` = más vendidos, `asc` = menos vendidos.
///
/// Parámetros de los informes (`yyyy-MM-dd`, el día `hasta` está incluido;
/// si faltan, el último mes hasta hoy):
///
/// * `desde` / `hasta` — rango de fechas;
/// * `agrupacion` — `dia` (por defecto), `mes` o `anio`.
void addReporteRoutes(Router router, {required Reportes reportes}) {
  Future<Response> productosVendidos(Request request) async {
    // El ranking se muestra en el Dashboard: exige su permiso de lectura.
    asegurarPermiso(request, 'dashboard', 'ver');
    final items = await reportes.productosVendidos(
      limite: int.tryParse(request.url.queryParameters['limite'] ?? '') ?? 6,
      orden: queryOrNull(request, 'orden') ?? 'desc',
      porVariante: request.url.queryParameters['porVariante'] == 'true',
    );
    return listJsonResponse(items.map((e) => e.toJson()).toList());
  }

  // Informe «ventas por periodo»: el permiso es el del módulo Reportes, no
  // el del dashboard (otro rol puede ver el panel sin ver las cifras).
  Future<Response> ventas(Request request) async {
    asegurarPermiso(request, 'reportes', 'ver');
    final informe = await reportes.ventas(
      desde: queryOrNull(request, 'desde'),
      hasta: queryOrNull(request, 'hasta'),
      agrupacion: queryOrNull(request, 'agrupacion') ?? 'dia',
    );
    return jsonResponse(200, informe.toJson());
  }

  Future<Response> ventasProductos(Request request) async {
    asegurarPermiso(request, 'reportes', 'ver');
    final informe = await reportes.productosDelRango(
      desde: queryOrNull(request, 'desde'),
      hasta: queryOrNull(request, 'hasta'),
    );
    return jsonResponse(200, informe.toJson());
  }

  router
    ..get('/api/v1/reportes/productos-vendidos', productosVendidos)
    ..get('/api/v1/reportes/ventas', ventas)
    ..get('/api/v1/reportes/ventas-productos', ventasProductos);
}
