import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/fechas.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/recurso.dart';
import '../../domain/entities/reporte.dart';
import '../controllers/load_state.dart';
import 'graficos_ranking.dart';

/// Gráficos del dashboard principal, en seis tarjetas:
///
/// 1. ventas de los últimos días (barras verticales);
/// 2. órdenes por estado (donut);
/// 3. productos más vendidos (barras horizontales);
/// 4. productos menos vendidos, incluidos los que nunca se vendieron;
/// 5. productos por vencer, según `fechaVencimiento`;
/// 6. clientes con más compras.
///
/// Vive fuera de `dashboard_page.dart` para que la página no crezca y para
/// poder cachear los datos derivados **por identidad** de las listas que
/// recibe: el controlador asigna una lista nueva en cada recarga, así que los
/// grupos solo se recalculan cuando llegan datos, no en cada reconstrucción
/// (checklist de fluidez §4 de la guía del proyecto).
class GraficosDashboard extends StatefulWidget {
  const GraficosDashboard({
    super.key,
    required this.ordenes,
    required this.productos,
    required this.masVendidos,
    required this.menosVendidos,
    required this.estadoReportes,
    this.diasUmbral = 90,
  });

  /// Listas vivas de los controladores; cambian de identidad en cada
  /// recarga, lo que sirve de invalidación de la caché interna.
  final List<Recurso> ordenes;
  final List<Recurso> productos;

  /// Rankings que calcula el backend (`ReportesController`).
  final List<VentaProducto> masVendidos;
  final List<VentaProducto> menosVendidos;
  final LoadState estadoReportes;

  /// Días de margen que se consideran «por vencer».
  ///
  /// Viene del ajuste «Días de aviso de vencimiento» (vista «Ajustes»);
  /// 90 es el valor de fábrica, el que tenía antes de existir los ajustes.
  final int diasUmbral;

  /// Filas de cada ranking (los 6 primeros de la lista).
  static const int filasRanking = 6;

  @override
  State<GraficosDashboard> createState() => _GraficosDashboardState();
}

class _GraficosDashboardState extends State<GraficosDashboard> {
  /// Días con ventas, de menor a mayor fecha (`yyyy-MM-dd`).
  List<_VentaDia> _ventas = const [];

  /// Conteo de órdenes por estado, del más frecuente al menos.
  List<_EstadoTotal> _estados = const [];

  /// Clientes con más órdenes (no anuladas), del primero al sexto.
  List<_ClienteTotal> _clientes = const [];

  /// Productos con `fechaVencimiento` dentro del umbral, del más urgente.
  List<_PorVencer> _porVencer = const [];

  /// Listas con las que se calculó cada caché (comparación por identidad).
  List<Recurso>? _origenOrdenes;
  List<Recurso>? _origenProductos;

  /// Umbral de días con el que se calculó la caché de vencimientos: si el
  /// usuario cambia el ajuste, la tarjeta se recalcula aunque los productos
  /// no hayan cambiado de identidad.
  int? _umbralPorVencer;

  /// Máximo de filas de leyenda: evita que la tarjeta desborde su altura
  /// fija si algún día aparecen más estados de los previstos.
  static const _maxLeyendas = 5;

  /// Colores de los estados conocidos de una orden (`ventas_page.dart`).
  static const _coloresEstado = <String, Color>{
    'PAGADO': AppColors.brandGreen,
    'PENDIENTE': AppColors.warningOrange,
    'CANCELADO': AppColors.negativeRed,
    'DEVUELTO': AppColors.infoBlue,
  };

  /// Reserva para estados no contemplados (o datos de prueba).
  static const _paletaSecundaria = <Color>[
    AppColors.infoBlue,
    AppColors.brandGreenDark,
    AppColors.warningOrange,
    AppColors.negativeRed,
    AppColors.brandGreen,
  ];

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  @override
  void didUpdateWidget(covariant GraficosDashboard viejo) {
    super.didUpdateWidget(viejo);
    _calcular();
  }

  void _calcular() {
    _calcularOrdenes();
    _calcularProductos();
  }

  void _calcularOrdenes() {
    final ordenes = widget.ordenes;
    if (identical(_origenOrdenes, ordenes)) return;
    _origenOrdenes = ordenes;

    // Ventas por día. Se suman las órdenes pagadas cuando las hay (es lo que
    // refleja el KPI «Ventas pagadas»); si todavía no hay ninguna se muestran
    // todas, para no dejar el gráfico vacío en una tienda recién montada.
    final pagadas = [
      for (final orden in ordenes)
        if (orden.texto('estado') == 'PAGADO') orden,
    ];
    final base = pagadas.isEmpty ? ordenes : pagadas;
    final porDia = <String, double>{};
    for (final orden in base) {
      final fecha = orden.texto('fechaOrden', vacio: '');
      if (fecha.isEmpty) continue;
      // Día en hora local (la API guarda UTC): agrupa como el usuario ve.
      final dia = fechaCortaLocal(fecha);
      porDia[dia] =
          (porDia[dia] ?? 0) +
          (orden.numero('totalPagar') ?? orden.numero('total') ?? 0);
    }
    final dias = porDia.keys.toList()
      ..sort(); // orden lexicográfico = cronológico
    _ventas = [for (final dia in dias) _VentaDia(dia, porDia[dia]!)];

    // Órdenes por estado, de la más frecuente a la menos.
    final cuenta = <String, int>{};
    for (final orden in ordenes) {
      final estado = orden.texto('estado', vacio: 'SIN ESTADO');
      cuenta[estado] = (cuenta[estado] ?? 0) + 1;
    }
    _estados = [
      for (final entrada in cuenta.entries)
        _EstadoTotal(entrada.key, entrada.value),
    ]..sort((a, b) => b.total.compareTo(a.total));

    _clientes = _agruparClientes(ordenes);
  }

  /// Compras por cliente: agrupa las órdenes **no anuladas** (el mismo
  /// criterio que el ranking de ventas del backend) por `clienteId`, o por el
  /// nombre cuando la orden no lleva cliente asignado.
  static List<_ClienteTotal> _agruparClientes(List<Recurso> ordenes) {
    final ordenesPorCliente = <String, int>{};
    final gastoPorCliente = <String, double>{};
    final nombrePorCliente = <String, String>{};

    for (final orden in ordenes) {
      final estado = orden.texto('estado', vacio: '');
      if (estado == 'CANCELADO' || estado == 'DEVUELTO') continue;
      final id = orden.numero('clienteId');
      final clave = id != null
          ? 'c$id'
          : orden.texto('nombreCliente', vacio: '—');
      ordenesPorCliente[clave] = (ordenesPorCliente[clave] ?? 0) + 1;
      gastoPorCliente[clave] =
          (gastoPorCliente[clave] ?? 0) +
          (orden.numero('totalPagar') ?? orden.numero('total') ?? 0);
      nombrePorCliente[clave] = id != null
          ? orden.texto('nombreCliente', vacio: 'Cliente no registrado')
          : clave;
    }

    final clientes = [
      for (final clave in ordenesPorCliente.keys)
        _ClienteTotal(
          nombrePorCliente[clave] ?? clave,
          ordenesPorCliente[clave] ?? 0,
          gastoPorCliente[clave] ?? 0,
        ),
    ];
    clientes.sort(
      (a, b) => b.ordenes != a.ordenes
          ? b.ordenes.compareTo(a.ordenes)
          : b.gasto.compareTo(a.gasto),
    );
    return clientes.take(GraficosDashboard.filasRanking).toList();
  }

  void _calcularProductos() {
    final productos = widget.productos;
    if (identical(_origenProductos, productos) &&
        _umbralPorVencer == widget.diasUmbral) {
      return;
    }
    _origenProductos = productos;
    _umbralPorVencer = widget.diasUmbral;

    // Vencimiento calculado desde la fecha, no desde el estado: el estado
    // `POR_VENCER` se asigna a mano y se olvida; la fecha, no.
    final hoy = DateTime.now();
    final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);
    final porVencer = <_PorVencer>[];

    for (final producto in productos) {
      final texto = producto.texto('fechaVencimiento', vacio: '');
      final fecha = DateTime.tryParse(texto);
      if (fecha == null) continue;
      final dias = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
      ).difference(hoySinHora).inDays;
      if (dias > widget.diasUmbral) continue;
      porVencer.add(_PorVencer(producto.texto('nombre'), dias));
    }

    porVencer.sort(
      (a, b) => a.dias.compareTo(b.dias),
    ); // el más urgente primero
    _porVencer = porVencer.take(GraficosDashboard.filasRanking).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = <Widget>[
      _tarjeta('Ventas por día (Bs)', _cuerpoVentas()),
      _tarjeta('Órdenes por estado', _cuerpoEstados()),
      _tarjeta('Productos más vendidos', _cuerpoRanking(mas: true)),
      _tarjeta('Productos menos vendidos', _cuerpoRanking(mas: false)),
      _tarjeta('Productos por vencer', _cuerpoPorVencer()),
      _tarjeta('Clientes con más compras', _cuerpoClientes()),
    ];

    // Mismo corte que el resto del dashboard: una columna por debajo de 800px
    // y dos tarjetas en paralelo por encima.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth < 800 ? 1 : 2;
        final filas = <Widget>[];
        for (var i = 0; i < tarjetas.length; i += columnas) {
          if (i > 0) filas.add(const SizedBox(height: 16));
          if (columnas == 2 && i + 1 < tarjetas.length) {
            filas.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tarjetas[i]),
                  const SizedBox(width: 16),
                  Expanded(child: tarjetas[i + 1]),
                ],
              ),
            );
          } else {
            filas.add(tarjetas[i]);
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: filas,
        );
      },
    );
  }

  // --- Tarjeta de ventas (barras) -----------------------------------------

  Widget _cuerpoVentas() {
    if (_ventas.isEmpty) {
      return _sinDatos('Todavía no hay ventas registradas');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // En tarjetas estrechas se recortan días: cada barra lleva su etiqueta
        // en el eje X y con muchas etiquetas se pisarían.
        final dias = constraints.maxWidth >= 420 ? 7 : 5;
        final serie = _ventas.length > dias
            ? _ventas.sublist(_ventas.length - dias)
            : _ventas;
        final maximo = serie.fold<double>(0, (m, v) => math.max(m, v.total));
        return SizedBox(
          height: 200,
          child: BarChart(
            _datosBarras(serie, maximo),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      },
    );
  }

  BarChartData _datosBarras(List<_VentaDia> serie, double maximo) {
    return BarChartData(
      // Holgura del 20% para que la barra más alta no toque el techo.
      maxY: maximo <= 0 ? 1 : maximo * 1.2,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.brandGreenDark,
          tooltipBorderRadius: BorderRadius.circular(10),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (grupo, grupoIndex, barra, rodIndex) =>
              BarTooltipItem(
                'Bs ${barra.toY.toStringAsFixed(2)}',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            getTitlesWidget: (valor, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                meta.formattedValue, // acorta solo: 500, 1.2k, 3M...
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        rightTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (valor, meta) {
              final indice = valor.toInt();
              if (indice < 0 || indice >= serie.length) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  _etiquetaDia(serie[indice].fecha),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.cardBorder, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barGroups: [
        for (var i = 0; i < serie.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: serie[i].total,
                width: 18,
                // Degradado de la base oscura al verde de marca arriba.
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppColors.brandGreenDark, AppColors.brandGreen],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static String _etiquetaDia(String fecha) {
    final partes = fecha.split('-');
    if (partes.length != 3) return fecha;
    return '${partes[2]}/${partes[1]}'; // 2026-09-25 -> 25/09
  }

  // --- Tarjeta de estados (donut) -----------------------------------------

  Widget _cuerpoEstados() {
    if (_estados.isEmpty) {
      return _sinDatos('Todavía no hay órdenes registradas');
    }
    final total = _estados.fold<int>(0, (suma, e) => suma + e.total);
    final visibles = _estados.take(_maxLeyendas).toList();
    final resto = _estados.length - visibles.length;

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(_datosDonut(total)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'órdenes',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < visibles.length; i++)
                  _leyenda(visibles[i], i),
                if (resto > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '+$resto más',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PieChartData _datosDonut(int total) {
    return PieChartData(
      centerSpaceRadius: 40,
      sectionsSpace: 3,
      sections: [
        for (var i = 0; i < _estados.length; i++)
          PieChartSectionData(
            value: _estados[i].total.toDouble(),
            color: _colorDe(_estados[i].estado, i),
            radius: 22,
            // El porcentaje solo en porciones grandes: en las finas se pisa.
            showTitle: total > 0 && _estados[i].total / total >= 0.12,
            title: '${(_estados[i].total / total * 100).round()}%',
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
      ],
    );
  }

  Color _colorDe(String estado, int indice) =>
      _coloresEstado[estado] ??
      _paletaSecundaria[indice % _paletaSecundaria.length];

  Widget _leyenda(_EstadoTotal dato, int indice) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _colorDe(dato.estado, indice),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dato.estado,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${dato.total}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // --- Tarjetas de ranking (barras horizontales) --------------------------

  /// Más o menos vendidos, según lo que devuelve el backend.
  Widget _cuerpoRanking({required bool mas}) {
    final estado = widget.estadoReportes;
    if (estado == LoadState.initial || estado == LoadState.loading) {
      return _sinDatos('Cargando ranking…');
    }
    if (estado == LoadState.error) {
      return _sinDatos('No se pudo cargar el ranking de ventas');
    }

    final items = mas ? widget.masVendidos : widget.menosVendidos;
    if (items.isEmpty) {
      return _sinDatos('Todavía no hay ventas registradas');
    }

    return GraficoHorizontal(
      datos: [
        for (final producto in items)
          DatoRanking(
            etiqueta: producto.nombre,
            valor: producto.unidades.toDouble(),
            color: mas ? AppColors.brandGreen : AppColors.warningOrange,
            detalle:
                '${producto.unidades} uds · Bs ${producto.monto.toStringAsFixed(2)}',
          ),
      ],
    );
  }

  /// Productos con `fechaVencimiento` a menos de `diasUmbral` días.
  ///
  /// En el eje van los días que quedan (los ya vencidos, 0, con el nombre en
  /// rojo); el valor exacto está en el tooltip.
  Widget _cuerpoPorVencer() {
    if (_porVencer.isEmpty) {
      return _sinDatos(
        'Ningún producto vence en los próximos ${widget.diasUmbral} días',
      );
    }

    return GraficoHorizontal(
      datos: [
        for (final producto in _porVencer)
          DatoRanking(
            etiqueta: producto.nombre,
            // Un vencido no puede tener días «negativos» en el eje: se queda
            // en 0 y lo avisa el color y el tooltip.
            valor: producto.dias > 0 ? producto.dias.toDouble() : 0,
            color: _colorVencimiento(producto.dias),
            colorEtiqueta: producto.dias < 0 ? AppColors.negativeRed : null,
            detalle: producto.dias < 0
                ? 'Vencido hace ${-producto.dias} días'
                : producto.dias == 0
                ? 'Vence hoy'
                : 'Vence en ${producto.dias} días',
          ),
      ],
    );
  }

  static Color _colorVencimiento(int dias) {
    if (dias < 0) return AppColors.negativeRed;
    if (dias <= 30) return AppColors.warningOrange;
    return AppColors.infoBlue;
  }

  /// Órdenes no anuladas por cliente, de la que más tiene a la que menos.
  Widget _cuerpoClientes() {
    if (_clientes.isEmpty) {
      return _sinDatos('Todavía no hay órdenes registradas');
    }

    return GraficoHorizontal(
      datos: [
        for (final cliente in _clientes)
          DatoRanking(
            etiqueta: cliente.nombre,
            valor: cliente.ordenes.toDouble(),
            color: AppColors.infoBlue,
            detalle:
                '${cliente.ordenes} órdenes · Bs ${cliente.gasto.toStringAsFixed(2)}',
          ),
      ],
    );
  }

  // --- Piezas comunes ------------------------------------------------------

  Widget _sinDatos(String texto) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(String titulo, Widget cuerpo) {
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
          const SizedBox(height: 16),
          cuerpo,
        ],
      ),
    );
  }
}

/// Ventas agregadas de un día (`yyyy-MM-dd`).
class _VentaDia {
  const _VentaDia(this.fecha, this.total);

  final String fecha;
  final double total;
}

/// Nº de órdenes en un estado concreto.
class _EstadoTotal {
  const _EstadoTotal(this.estado, this.total);

  final String estado;
  final int total;
}

/// Nº de órdenes y gasto total de un cliente.
class _ClienteTotal {
  const _ClienteTotal(this.nombre, this.ordenes, this.gasto);

  final String nombre;
  final int ordenes;
  final double gasto;
}

/// Producto por vencer y días que quedan (`negativo` = ya vencido).
class _PorVencer {
  const _PorVencer(this.nombre, this.dias);

  final String nombre;
  final int dias;
}
