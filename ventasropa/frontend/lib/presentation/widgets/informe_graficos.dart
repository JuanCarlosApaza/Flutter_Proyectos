import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/entities/reporte.dart';

/// Gráfico de barras verticales de la serie del informe (día, mes o año).
///
/// Diferencias con las barras giradas de `GraficoHorizontal`:
///
/// * aquí el eje horizontal es el **tiempo**, así que se giran de lado y las
///   etiquetas (fecha corta: `01/10`, `10/26` o `2026`) van debajo;
/// * el gráfico **llena el ancho de la tarjeta**: cada grupo ocupa como
///   mínimo 40 px y con un rango largo crece por encima, desplazándose
///   horizontalmente en vez de apretar las barras hasta volverlas
///   ilegibles;
/// * los periodos sin ventas llegan rellenados con ceros (ver
///   `InformeVentas.serieCompleta`): se ven como un hueco en la línea, que
///   es justo lo que hay que poder distinguir.
class GraficoSerie extends StatelessWidget {
  const GraficoSerie({super.key, required this.serie, this.altura = 240});

  /// Serie completa del rango (ya rellenada con los ceros).
  final List<VentaPeriodo> serie;

  final double altura;

  /// Ancho de cada barra + su aire.
  static const double anchoGrupo = 40;

  /// Con menos barras que esto el gráfico no estira: se centra en su sitio.
  static const double anchoMinimo = 360;

  @override
  Widget build(BuildContext context) {
    if (serie.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Sin ventas en el rango seleccionado',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, restricciones) {
        // Llena la tarjeta; con un rango largo (más de 40 px por grupo)
        // crece por encima y se desplaza en horizontal.
        final disponible = restricciones.hasBoundedWidth
            ? restricciones.maxWidth
            : 0.0;
        final ancho = math.max(
          math.max(anchoMinimo, serie.length * anchoGrupo),
          disponible,
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: ancho,
            height: altura,
            child: BarChart(
              _datos(ancho),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            ),
          ),
        );
      },
    );
  }

  BarChartData _datos(double ancho) {
    final maximo = serie.fold<double>(0, (m, f) => math.max(m, f.total));
    // Escala con techo y marcas redondeados: si el techo queda «suelto»
    // (p. ej. 707.08), la escala pinta dos etiquetas pegadas arriba y se
    // leen una encima de otra.
    final escala = _escala(maximo);

    // Barra proporcional al hueco de cada grupo (entre 22 y 56 px): con
    // pocos periodos el hueco es enorme y las barras se estrechan solas.
    final hueco = ancho / math.max(serie.length, 1);
    final barra = math.min(56.0, math.max(22.0, hueco * 0.45));

    return BarChartData(
      minY: 0,
      maxY: escala.techo,
      alignment: BarChartAlignment.spaceAround,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.brandGreenDark,
          tooltipBorderRadius: BorderRadius.circular(10),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (grupo, grupoIndex, barra, rodIndex) {
            final periodo = serie[grupoIndex];
            return BarTooltipItem(
              '${periodo.etiqueta}\n'
              'Bs ${periodo.total.toStringAsFixed(2)} · '
              '${periodo.ordenes} ${periodo.ordenes == 1 ? 'orden' : 'órdenes'}',
              const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        // Importes de la escala: franja izquierda.
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            // Paso fijo de la escala: marcas en números redondos.
            interval: escala.paso,
            getTitlesWidget: (valor, meta) => SideTitleWidget(
              meta: meta,
              child: Text(
                meta.formattedValue, // acorta: 500, 1.2k, 3M...
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        // Fechas: franja inferior. El ancho de cada grupo es fijo, así que
        // todas caben con la etiqueta corta.
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (valor, meta) {
              final indice = valor.toInt();
              if (indice < 0 || indice >= serie.length) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  _fechaCorta(serie[indice].etiqueta),
                  maxLines: 1,
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
                width: barra,
                color: serie[i].total == 0
                    ? AppColors.trackGrey
                    : AppColors.brandGreen,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Techo y paso «bonitos» de la escala Y: múltiplos de 1, 2 o 5 × 10ⁿ.
  ///
  /// Con el techo en crudo (máximo × 1,15) salían marcas como 707.08
  /// pegadas a la de 700 y se leían encima; redondeando, todas las
  /// etiquetas quedan en números redondos y una debajo de otra.
  ({double techo, double paso}) _escala(double maximo) {
    if (maximo <= 0) return (techo: 1, paso: 1);
    // ~6 marcas en el eje, redondeadas al paso bueno de arriba.
    final bruto = maximo * 1.15 / 6;
    final base = math
        .pow(10, (math.log(bruto) / math.ln10).floorToDouble())
        .toDouble();
    final fraccion = bruto / base;
    final paso =
        (fraccion <= 1
            ? 1.0
            : fraccion <= 2
            ? 2.0
            : fraccion <= 5
            ? 5.0
            : 10.0) *
        base;
    return (techo: (maximo * 1.15 / paso).ceil() * paso, paso: paso);
  }

  /// `2026-10-01` → `01/10`, `2026-10` → `10/26`, `2026` → `2026`.
  static String _fechaCorta(String etiqueta) => switch (etiqueta.length) {
    10 => '${etiqueta.substring(8)}/${etiqueta.substring(5, 7)}',
    7 => '${etiqueta.substring(5)}/${etiqueta.substring(2, 4)}',
    _ => etiqueta,
  };
}
