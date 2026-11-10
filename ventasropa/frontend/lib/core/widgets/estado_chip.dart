import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Chip de estado con el color asociado al valor (`ACTIVO`, `PAGADO`...).
///
/// El fondo siempre va al 10% de opacidad para que la fila de la tabla
/// mantenga el ritmo visual sin saturar de color.
class EstadoChip extends StatelessWidget {
  const EstadoChip({super.key, required this.valor});

  final String valor;

  @override
  Widget build(BuildContext context) {
    final color = colorDeEstado(valor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        valor,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Color de acento para un valor de estado de negocio.
Color colorDeEstado(String valor) => switch (valor) {
  'ACTIVO' ||
  'DISPONIBLE' ||
  'PAGADO' ||
  'EMITIDA' ||
  'ACEPTADA' => AppColors.positiveGreen,
  'INACTIVO' ||
  'BLOQUEADO' ||
  'AGOTADO' ||
  'DESCONTINUADO' ||
  'CANCELADO' ||
  'ANULADA' ||
  'RECHAZADA' => AppColors.negativeRed,
  'PENDIENTE' || 'VACACIONES' => AppColors.warningOrange,
  'LICENCIA' || 'DEVUELTO' || 'VIGENTE' => AppColors.infoBlue,
  _ => AppColors.textSecondary,
};
