import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/ajustes_scope.dart';
import '../../core/widgets/nav_scope.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../core/widgets/sidebar.dart';
import '../controllers/health_controller.dart';
import '../controllers/recurso_controller.dart';
import '../controllers/reporte_controller.dart';
import '../controllers/respaldos_controller.dart';
import 'ajustes_page.dart';
import 'auditoria_page.dart';
import 'categorias_page.dart';
import 'catalogo_page.dart';
import 'clientes_page.dart';
import 'cotizaciones_page.dart';
import 'dashboard_page.dart';
import 'empleados_page.dart';
import 'productos_page.dart';
import 'proveedores_page.dart';
import 'reportes_page.dart';
import 'unidades_page.dart';
import 'usuarios_page.dart';
import 'ventas_page.dart';

/// Contenedor de la navegación: mantiene el índice seleccionado y construye
/// la pantalla correspondiente (patrón `MainScreen` de la guía).
///
/// Las pantallas visitadas se conservan en un [IndexedStack] para no perder
/// filtros y paginación al cambiar de módulo; las no visitadas todavía no se
/// construyen, así que no disparan peticiones a la API.
///
/// **Rendimiento**: las páginas se construyen como widgets `const` (sin
/// `selectedNav`/`onNavSelect`, que ahora van por el [NavScope]). Al hacer
/// clic en el sidebar, los elementos existentes comparan igual por identidad
/// y **no se redibujan**: solo cambia el `index` del `IndexedStack` y se
/// repintan los widgets de navegación. Antes, cada módulo visitado se
/// reconstruía entero (con su grid de tarjetas o su tabla) en cada cambio.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Índice observable: lo escuchan el `IndexedStack` y la navegación.
  final ValueNotifier<int> _seleccionado = ValueNotifier<int>(0);

  /// Módulos ya construidos (para no recrear los que faltan).
  final Set<int> _visitadas = {0};

  /// La página inicial solo se lee una vez (al montar): si el usuario
  /// navega, un cambio posterior del ajuste no lo mueve de módulo.
  bool _paginaInicialLeida = false;

  /// Módulos con permiso `ver` para la sesión actual (se recalcula en cada
  /// [didChangeDependencies]; vacío = sin sesión → todo visible).
  List<int> _visibles = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibles = indicesVisibles(SesionScope.de(context));

    // Nunca se monta (ni se queda seleccionada) una página que el rol del
    // usuario no puede ver: si el módulo actual no está permitido, se salta
    // al primero que lo esté.
    _visitadas.retainAll(_visibles);
    if (!_visibles.contains(_seleccionado.value)) {
      _seleccionado.value = _visibles.first;
      _visitadas.add(_visibles.first);
    }

    // La raíz garantiza que los ajustes ya se pidieron antes de construir
    // esta pantalla, así que aquí llegan con su valor (o los de fábrica).
    if (_paginaInicialLeida) return;
    _paginaInicialLeida = true;

    final indice = AjustesScope.de(context).numero(Ajustes.paginaInicial);
    if (indice <= 0 || indice >= navItems.length) return;
    if (!_visibles.contains(indice)) return;
    _seleccionado.value = indice;
    _visitadas.add(indice);
  }

  @override
  void dispose() {
    _seleccionado.dispose();
    super.dispose();
  }

  void _seleccionar(int indice) {
    if (!_visibles.contains(indice)) return;
    if (indice == _seleccionado.value) return;
    // Primera visita: hay que montar la página (redibuja el stack, que
    // solo añade un hijo nuevo; los demás son `const` y no se tocan).
    final nueva = _visitadas.add(indice);
    if (nueva) setState(() {});
    // Cambio de selección: notifica al IndexedStack y a sidebar/drawer/nav.
    _seleccionado.value = indice;
    // Al **volver** a un módulo ya visitado se recargan sus datos: lo que
    // se creó o editó en otro módulo debe aparecer al regresar, sin
    // recargar la página. En la primera visita no, porque la propia página
    // acaba de cargar.
    if (!nueva) _refrescar(indice);
  }

  /// Recarga los listados del módulo [indice] al volver a él (los combos
  /// maestros —clientes, empleados…— los refresca cada página).
  void _refrescar(int indice) {
    switch (indice) {
      case 0: // Dashboard: KPIs, gráficos y alertas.
        context.read<ProductosController>().recargar();
        context.read<ClientesController>().recargar();
        context.read<OrdenesController>().recargar();
        context.read<FacturasController>().recargar();
        context.read<ReportesController>().cargar();
        context.read<HealthController>().load();
      case 1:
        context.read<ProductosController>().recargar();
      case 2: // Catálogo: vitrina e índice de categorías.
        context.read<ProductosController>().recargar();
        context.read<CategoriasController>().recargar();
      case 3:
        context.read<ClientesController>().recargar();
      case 4: // Ventas: pestañas de órdenes y facturas.
        context.read<OrdenesController>().recargar();
        context.read<FacturasController>().recargar();
      case 5:
        context.read<CotizacionesController>().recargar();
      case 6:
        context.read<CategoriasController>().recargar();
        context.read<PresentacionesController>().recargar();
      case 7:
        context.read<ProveedoresController>().recargar();
      case 8:
        context.read<EmpleadosController>().recargar();
      case 9: // Usuarios y su pestaña de roles.
        context.read<UsuariosController>().recargar();
        context.read<RolesController>().recargar();
      case 10:
        context.read<AuditoriaController>().recargar();
      case 11: // Unidades de medida (catálogo maestro del producto).
        context.read<UnidadesController>().recargar();
      case 12: // Ajustes (incluye la carpeta de respaldos).
        context.read<AjustesController>().recargar();
        context.read<RespaldosController>().recargar();
      case 13: // Reportes: no se recarga al volver.
        // Los filtros (rango, agrupación) y el informe ya cargado viven en
        // `InformesController`: la pantalla repinta con lo que hay y quien
        // decide si volver a preguntar al servidor es su «actualizar»
        // (pull-to-refresh o cambio de filtro).
        break;
    }
  }

  Widget _pagina(int indice) => switch (indice) {
    0 => const DashboardPage(),
    1 => const ProductosPage(),
    2 => const CatalogoPage(),
    3 => const ClientesPage(),
    4 => const VentasPage(),
    5 => const CotizacionesPage(),
    6 => const CategoriasPage(),
    7 => const ProveedoresPage(),
    8 => const EmpleadosPage(),
    10 => const AuditoriaPage(),
    11 => const UnidadesPage(),
    12 => const AjustesPage(),
    13 => const ReportesPage(),
    _ => const UsuariosPage(),
  };

  @override
  Widget build(BuildContext context) {
    return NavScope(
      seleccionado: _seleccionado,
      onSeleccionar: _seleccionar,
      child: ValueListenableBuilder<int>(
        valueListenable: _seleccionado,
        builder: (context, indice, _) => IndexedStack(
          index: indice,
          children: [
            for (var i = 0; i < navItems.length; i++)
              if (_visitadas.contains(i))
                _pagina(i)
              else
                const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
