import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/fechas.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../core/widgets/estado_chip.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/health_controller.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import '../controllers/reporte_controller.dart';
import '../widgets/graficos_dashboard.dart';
import '../widgets/vistas_estado.dart';

/// Pantalla principal: KPIs, gráficos (ventas, estados, rankings de ventas,
/// vencimientos y clientes), estado del backend, alertas y últimas órdenes.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late HealthController _health;
  late ProductosController _productos;
  late ClientesController _clientes;
  late OrdenesController _ordenes;
  late FacturasController _facturas;
  late ReportesController _reportes;

  @override
  void initState() {
    super.initState();
    // Se carga después del primer frame para poder usar `context.read`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recargar();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se resuelven aquí para que el primer build ya tenga controladores.
    _health = context.read<HealthController>();
    _productos = context.read<ProductosController>();
    _clientes = context.read<ClientesController>();
    _ordenes = context.read<OrdenesController>();
    _facturas = context.read<FacturasController>();
    _reportes = context.read<ReportesController>();
  }

  Future<void> _recargar() async {
    // El dashboard necesita el lote COMPLETO (KPIs y gráficos): se pide solo
    // si no se ha cargado aún o si el último intento falló, aunque el
    // controlador ya tenga una página de tabla cargada (`state == loaded`).
    await Future.wait([
      if (_health.state == LoadState.initial) _health.load(),
      if (!_productos.completoCargado || _productos.state == LoadState.error)
        _productos.cargar(),
      if (!_clientes.completoCargado || _clientes.state == LoadState.error)
        _clientes.cargar(),
      if (!_ordenes.completoCargado || _ordenes.state == LoadState.error)
        _ordenes.cargar(),
      if (!_facturas.completoCargado || _facturas.state == LoadState.error)
        _facturas.cargar(),
      // Los rankings del dashboard. Si falla, el error queda confinado en sus
      // dos tarjetas: el resto del dashboard se pinta igualmente.
      if (_reportes.state != LoadState.loaded) _reportes.cargar(),
    ]);
    if (mounted) setState(() {});
  }

  static bool _enCarga(LoadState state) =>
      state == LoadState.initial || state == LoadState.loading;

  bool get _cargando =>
      _enCarga(_health.state) ||
      _enCarga(_productos.state) ||
      _enCarga(_clientes.state) ||
      _enCarga(_ordenes.state);

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      title: 'Dashboard',
      // Gesto de actualizar: recarga KPIs, gráficos y estado del backend.
      onRefresh: _recargar,
      contentBuilder: (context, constraints) => ListenableBuilder(
        // Escucha los controladores: el refresco que dispara MainScreen al
        // volver a esta pestaña repinta solo, sin un setState manual.
        listenable: Listenable.merge([
          _health,
          _productos,
          _clientes,
          _ordenes,
          _facturas,
          _reportes,
        ]),
        builder: (context, _) => _contenido(constraints.maxWidth),
      ),
    );
  }

  Widget _contenido(double ancho) {
    if (_cargando) return const VistaCargando();

    if (_health.state == LoadState.error &&
        _productos.state == LoadState.error) {
      return VistaError(
        mensaje: _productos.errorMessage ?? _health.errorMessage ?? 'Error',
        onReintentar: _recargar,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Resumen general'),
        const SizedBox(height: 20),
        _kpiGrid(ancho),
        const SizedBox(height: 16),
        GraficosDashboard(
          ordenes: _ordenes.items,
          productos: _productos.items,
          masVendidos: _reportes.masVendidos,
          menosVendidos: _reportes.menosVendidos,
          estadoReportes: _reportes.state,
          // Ventana de vencimientos elegida en «Ajustes» (90 = fábrica).
          diasUmbral: AjustesScope.de(context).numero(Ajustes.diasVencimiento),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final estado = _tarjetaEstado();
            final alertas = _tarjetaAlertas();
            if (constraints.maxWidth < 800) {
              return Column(
                children: [estado, const SizedBox(height: 16), alertas],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: estado),
                const SizedBox(width: 16),
                Expanded(child: alertas),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _tarjetaUltimasOrdenes(),
      ],
    );
  }

  // --- KPIs ---------------------------------------------------------------

  Widget _kpiGrid(double ancho) {
    final int columnas;
    if (ancho >= 1100) {
      columnas = 4;
    } else if (ancho >= 700) {
      columnas = 3;
    } else {
      columnas = 2;
    }

    // Lo realmente cobrado: total con rebaja e IVA ya aplicados.
    final pagadas = _ordenes.items
        .where((o) => o.texto('estado') == 'PAGADO')
        .fold<double>(
          0,
          (suma, o) =>
              suma + (o.numero('totalPagar') ?? o.numero('total') ?? 0),
        );

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columnas,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: ancho >= 700 ? 1.4 : 1.2,
      children: [
        _kpi(
          icono: Icons.inventory_2_rounded,
          color: AppColors.brandGreen,
          valor: '${_productos.items.length}',
          etiqueta: 'Productos',
          ancho: ancho,
        ),
        _kpi(
          icono: Icons.people_rounded,
          color: AppColors.infoBlue,
          valor: '${_clientes.items.length}',
          etiqueta: 'Clientes',
          ancho: ancho,
        ),
        _kpi(
          icono: Icons.shopping_cart_rounded,
          color: AppColors.warningOrange,
          valor: '${_ordenes.items.length}',
          etiqueta: 'Órdenes',
          ancho: ancho,
        ),
        _kpi(
          icono: Icons.payments_rounded,
          color: AppColors.brandGreenDark,
          valor: 'Bs ${pagadas.toStringAsFixed(2)}',
          etiqueta: 'Ventas pagadas',
          ancho: ancho,
        ),
      ],
    );
  }

  Widget _kpi({
    required IconData icono,
    required Color color,
    required String valor,
    required String etiqueta,
    required double ancho,
  }) {
    return Container(
      padding: EdgeInsets.all(ancho >= 700 ? 20 : 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, color: color, size: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                etiqueta,
                style: const TextStyle(color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Tarjeta de estado del backend ---------------------------------------

  Widget _tarjetaEstado() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: switch (_health.state) {
        LoadState.initial || LoadState.loading => const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          ),
        ),
        LoadState.error => _filaEstado(
          icono: Icons.error_outline,
          color: AppColors.negativeRed,
          titulo: 'No se pudo conectar',
          texto: _health.errorMessage ?? 'Error desconocido',
        ),
        LoadState.loaded => _filaEstado(
          icono: _health.status?.databaseConnected ?? false
              ? Icons.check_circle_outline
              : Icons.warning_amber_rounded,
          color: _health.status?.databaseConnected ?? false
              ? AppColors.positiveGreen
              : AppColors.warningOrange,
          titulo: _health.status?.service ?? 'API',
          texto:
              'v${_health.status?.version ?? '—'} · Base de datos: '
              '${_health.status?.databaseConnected ?? false ? 'conectada' : 'no disponible'}',
        ),
      },
    );
  }

  Widget _filaEstado({
    required IconData icono,
    required Color color,
    required String titulo,
    required String texto,
  }) {
    return Row(
      children: [
        Icon(icono, color: color, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                texto,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Alertas -------------------------------------------------------------

  Widget _tarjetaAlertas() {
    // Los dos umbrales vienen de «Ajustes»: el resto de conteos son
    // estados guardados en la BD y no se pueden parametrizar desde aquí.
    final ajustes = AjustesScope.de(context);
    final stockMinimo = ajustes.numero(Ajustes.stockMinimo);
    final diasAviso = ajustes.numero(Ajustes.diasVencimiento);

    final agotados = _productos.items
        .where(
          (p) =>
              p.texto('estado') == 'AGOTADO' || (p.numero('stock') ?? 0) <= 0,
        )
        .length;
    // Sin agotar pero por debajo del mínimo: se vende menos de lo esperado.
    final stockBajo = _productos.items.where((p) {
      final stock = p.numero('stock') ?? 0;
      return stock > 0 && stock <= stockMinimo;
    }).length;
    final porVencer = _productos.items.where((p) {
      if (p.texto('estado') == 'POR_VENCER') return true;
      // Los ya vencidos también cuentan (días negativos <= umbral).
      final dias = _diasDeVencimiento(p);
      return dias != null && dias <= diasAviso;
    }).length;
    final pendientes = _ordenes.items
        .where((o) => o.texto('estado') == 'PENDIENTE')
        .length;
    final anuladas = _facturas.items
        .where((b) => b.texto('estado') == 'ANULADA')
        .length;

    return _tarjeta(
      titulo: 'Alertas',
      hijos: [
        _alerta('Productos agotados', agotados, AppColors.negativeRed),
        _alerta('Stock bajo', stockBajo, AppColors.mapHigh),
        _alerta('Productos por vencer', porVencer, AppColors.warningOrange),
        _alerta('Órdenes pendientes', pendientes, AppColors.infoBlue),
        _alerta('Facturas anuladas', anuladas, AppColors.textSecondary),
      ],
    );
  }

  /// Días que faltan para el vencimiento de un producto (`< 0` = ya vencido);
  /// `null` si no tiene fecha o no es legible.
  int? _diasDeVencimiento(Recurso producto) {
    final texto = producto.texto('fechaVencimiento', vacio: '');
    if (texto.isEmpty) return null;
    final fecha = DateTime.tryParse(texto);
    if (fecha == null) return null;
    final hoy = DateTime.now();
    return DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    ).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  }

  Widget _alerta(String texto, int valor, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '$valor',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // --- Últimas órdenes -----------------------------------------------------

  Widget _tarjetaUltimasOrdenes() {
    final ultimas = _ordenes.items.take(5).toList();

    return _tarjeta(
      titulo: 'Últimas órdenes',
      hijos: ultimas.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Todavía no hay órdenes',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ]
          : [
              for (final orden in ultimas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              orden.texto(
                                'nombreCliente',
                                vacio: 'Cliente no registrado',
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '#${orden.id} · ${_fechaCorta(orden)} · '
                              '${orden.texto('tipoPago')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Bs ${(orden.numero('total') ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      EstadoChip(valor: orden.texto('estado')),
                    ],
                  ),
                ),
            ],
    );
  }

  /// Fecha de la orden en hora local (`—` si no viene).
  static String _fechaCorta(Recurso orden) =>
      fechaCortaLocal(orden.texto('fechaOrden', vacio: ''));

  Widget _tarjeta({required String titulo, required List<Widget> hijos}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...hijos,
        ],
      ),
    );
  }
}
