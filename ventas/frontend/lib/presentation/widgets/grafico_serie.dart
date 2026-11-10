import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formatos.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/reporte.dart';

/// Gráfico de **área** de la serie de ventas del informe.
///
/// Cada punto es un periodo (`2026-10-01`, `2026-10` o `2026`) y su altura,
/// la facturación de ese periodo. La serie ya llega rellena (los huecos del
/// rango están en ceros), así que un día sin ventas se ve como la línea
/// tocando el eje.
///
/// El eje X muestra como máximo ~8 etiquetas (`paso`), que con un rango
/// mensual serían 31 rotulos encima de otros 31.
class GraficoSerie extends StatelessWidget {
  const GraficoSerie({
    super.key,
    required this.datos,
    required this.agrupacion,
    this.altura = 240,
  });

  /// Serie completa del rango (con huecos rellenos).
  final List<PeriodoVenta> datos;

  /// `'dia'`, `'mes'` o `'anio'`: decide el formato del rótulo X.
  final String agrupacion;

  final double altura;

  @override
  Widget build(BuildContext context) {
    final maximo = datos.fold<double>(0, (m, d) => math.max(m, d.total));
    final techo = maximo <= 0 ? 1.0 : maximo * 1.15;
    final paso = datos.length <= 9 ? 1 : (datos.length / 8).ceil();
    final conPuntos = datos.length <= 15;

    return SizedBox(
      height: altura,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: techo,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.brandGreenDark,
              tooltipBorderRadius: BorderRadius.circular(10),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (puntos) => [
                for (final punto in puntos)
                  LineTooltipItem(
                    '${datos[punto.x.toInt()].etiqueta}\n'
                    '${bs(datos[punto.x.toInt()].total)}\n'
                    '${unidadesTexto(datos[punto.x.toInt()].unidades)} uds',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            // Facturación: franja izquierda.
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                getTitlesWidget: (valor, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    meta.formattedValue, // 500, 1.2k, 3M...
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            // Periodos: franja inferior, muestreada.
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: paso.toDouble(),
                getTitlesWidget: (valor, meta) {
                  final indice = valor.toInt();
                  if (indice < 0 || indice >= datos.length) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      _rotulo(indice),
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
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < datos.length; i++)
                  FlSpot(i.toDouble(), datos[i].total),
              ],
              isCurved: false,
              barWidth: 2.5,
              color: AppColors.brandGreen,
              dotData: FlDotData(show: conPuntos),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.brandGreen.withValues(alpha: 0.14),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// Rótulo corto del periodo: `01/10`, `10` o `2026`.
  String _rotulo(int indice) {
    final partes = datos[indice].etiqueta.split('-');
    if (partes.length == 3) return '${partes[2]}/${partes[1]}';
    if (partes.length == 2) return partes[1];
    return partes.first;
  }
}
