import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Una fila de un ranking: el rótulo de la izquierda y la longitud de su barra.
class DatoRanking {
  const DatoRanking({
    required this.etiqueta,
    required this.valor,
    required this.color,
    this.detalle,
    this.colorEtiqueta,
  });

  /// Texto que se muestra en la franja izquierda (se recorta si es largo).
  final String etiqueta;

  /// Longitud de la barra.
  final double valor;

  final Color color;

  /// Texto del tooltip; si no viene, se muestra el propio valor.
  final String? detalle;

  /// Color del rótulo (por defecto, el texto del tema). Útil para marcar una
  /// fila comprometida, p. ej. un producto ya vencido.
  final Color? colorEtiqueta;
}

/// Gráfico de barras **horizontal** con `fl_chart` para rankings.
///
/// `fl_chart` dibuja barras verticales, así que el gráfico se gira 90° con
/// `rotationQuarterTurns: 1`. Los rótulos se contrarrotan solos (lo hace
/// `SideTitleWidget`), de modo que en pantalla quedan en horizontal. En el
/// sistema girado:
///
/// * `bottomTitles` → franja **izquierda** (nombres);
/// * `rightTitles` → franja **inferior** (valores);
/// * la rejilla horizontal → verticales (perpendiculares a las barras);
/// * el primer dato (`x = 0`) cae arriba del todo, como en un ranking.
///
/// Detalles de layout: la tarjeta da el ancho y 200px de alto, y `fl_chart`
/// intercambia ambos al girar — por eso las barras crecen con el ancho de la
/// tarjeta y el número de filas vive en esos 200px.
class GraficoHorizontal extends StatelessWidget {
  const GraficoHorizontal({
    super.key,
    required this.datos,
    this.altura = 200,
    this.recorteEtiquetas = 22,
  });

  final List<DatoRanking> datos;

  /// Alto fijo del gráfico (mismo criterio que el resto de tarjetas).
  final double altura;

  /// Caracteres máximos de cada nombre antes de poner `…`: evita que un
  /// producto muy largo empuje su rótulo sobre las barras.
  final int recorteEtiquetas;

  /// Franja reservada a los nombres: se estrecha en tarjetas estrechas para
  /// que las barras no se queden sin sitio.
  static const double _anchoEtiquetasAncho = 104;
  static const double _anchoEtiquetasEstrecho = 78;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final reservaNombres =
            constraints.hasBoundedWidth && constraints.maxWidth < 340
            ? _anchoEtiquetasEstrecho
            : _anchoEtiquetasAncho;
        return SizedBox(
          height: altura,
          child: BarChart(
            _datos(reservaNombres),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          ),
        );
      },
    );
  }

  BarChartData _datos(double reservaNombres) {
    final maximo = datos.fold<double>(0, (m, d) => math.max(m, d.valor));
    // Holgura del 15% para que la barra más larga no toque el borde.
    final techo = maximo <= 0 ? 1.0 : maximo * 1.15;

    return BarChartData(
      rotationQuarterTurns: 1,
      minY: 0,
      maxY: techo,
      alignment: BarChartAlignment.spaceAround,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.brandGreenDark,
          tooltipBorderRadius: BorderRadius.circular(10),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (grupo, grupoIndex, barra, rodIndex) =>
              BarTooltipItem(
                datos[grupoIndex].detalle ?? barra.toY.toStringAsFixed(0),
                const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        // Valores de la escala: franja inferior en pantalla.
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
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
        // Nombres: franja izquierda en pantalla.
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: reservaNombres,
            getTitlesWidget: (valor, meta) {
              final indice = valor.toInt();
              if (indice < 0 || indice >= datos.length) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  _recortar(datos[indice].etiqueta),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: datos[indice].colorEtiqueta ?? AppColors.textPrimary,
                    fontWeight: datos[indice].colorEtiqueta == null
                        ? FontWeight.w400
                        : FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        // Las líneas verticales irían en paralelo a las barras: solo las
        // horizontales (que al girar se ven verticales) marcan la escala.
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.cardBorder, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      barGroups: [
        for (var i = 0; i < datos.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: datos[i].valor,
                width: 16,
                color: datos[i].color,
                // El extremo redondeado apunta al final de la barra: en el
                // sistema girado, arriba = derecha en pantalla.
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
                // Riel claro detrás de la barra: da contexto de escala y hace
                // visible una fila con valor 0 («nunca se ha vendido»).
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  color: AppColors.trackGrey,
                  fromY: 0,
                  toY: techo,
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _recortar(String texto) => texto.length <= recorteEtiquetas
      ? texto
      : '${texto.substring(0, recorteEtiquetas - 1)}…';
}
