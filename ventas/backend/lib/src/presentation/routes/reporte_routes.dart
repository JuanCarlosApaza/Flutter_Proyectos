import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/usecases/reporte_usecases.dart';
import '../http/api_request.dart';
import '../http/json_response.dart';
import '../http/permisos.dart';

/// Rutas de los reportes agregados: rankings del dashboard e informe de
/// ventas por rango (pantalla «Reportes»).
///
/// * `GET /api/v1/reportes/ventas?desde=&hasta=&agrupacion=`
/// * `GET /api/v1/reportes/ventas-productos?desde=&hasta=`
/// * `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc`
///
/// Devuelven **cifras agregadas** (periodos, productos y categorías ya
/// sumados con `GROUP BY`), no filas de un CRUD: por eso viven en su propio
/// módulo y no dentro de `venta_routes`.
///
/// Los tres están bajo el permiso propio **`reportes.ver`**. La migración
/// `019_permiso_reportes` se lo da a los roles que ya tenían `dashboard.ver`
/// (quien puede ver los gráficos del dashboard puede ver este informe), así
/// que el dashboard no pierde su ranking.
///
/// Parámetros del informe:
///
/// * `desde` y `hasta` — fechas `yyyy-MM-dd` **ambas incluidas**;
/// * `agrupacion` — `dia` (por defecto) | `mes` | `anio`;
/// * `limite` (por defecto 6, 1..50) y `orden` — solo el ranking rápido.
///
/// Solo se agregan órdenes **PAGADAS** y no anuladas. La respuesta del
/// informe trae `resumen` + `serie` (o `productos` + `categorias`); el
/// ticket medio y los porcentajes los calcula el cliente.
void addReporteRoutes(Router router, {required Reportes reportes}) {
  Future<Response> ventas(Request request) async {
    asegurarPermiso(request, 'reportes', 'ver');
    final informe = await reportes.ventasPorRango(
      desde: queryOrNull(request, 'desde') ?? '',
      hasta: queryOrNull(request, 'hasta') ?? '',
      agrupacion: queryOrNull(request, 'agrupacion') ?? 'dia',
    );
    return jsonResponse(200, informe.toJson());
  }

  Future<Response> ventasProductos(Request request) async {
    asegurarPermiso(request, 'reportes', 'ver');
    final informe = await reportes.productosPorRango(
      desde: queryOrNull(request, 'desde') ?? '',
      hasta: queryOrNull(request, 'hasta') ?? '',
    );
    return jsonResponse(200, informe.toJson());
  }

  Future<Response> productosVendidos(Request request) async {
    // El ranking se muestra en el Dashboard: mismo permiso que el informe.
    asegurarPermiso(request, 'reportes', 'ver');
    final items = await reportes.productosVendidos(
      limite: int.tryParse(request.url.queryParameters['limite'] ?? '') ?? 6,
      orden: queryOrNull(request, 'orden') ?? 'desc',
    );
    return listJsonResponse(items.map((e) => e.toJson()).toList());
  }

  router.get('/api/v1/reportes/ventas', ventas);
  router.get('/api/v1/reportes/ventas-productos', ventasProductos);
  router.get('/api/v1/reportes/productos-vendidos', productosVendidos);
}
