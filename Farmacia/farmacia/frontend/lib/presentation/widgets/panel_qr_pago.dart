import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/ajustes_scope.dart';
import 'imagen_recurso.dart';

/// Imagen del QR de pago para el cobro con QR (catálogo y Nueva orden).
///
/// Muestra la **imagen** que se sube desde Ajustes› Ventas por defecto›
/// Imagen del QR de pago (el QR real de la billetera del negocio, que él
/// mismo cambia cuando quiere). Si todavía no hay imagen, se avisa dónde
/// subirla en lugar de pintar un QR inventado.
Widget panelQrPago(BuildContext context, {double tamano = 176}) {
  final ruta = AjustesScope.de(context).valor(Ajustes.qrPago).trim();

  if (ruta.isEmpty) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.qr_code_2_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sin QR de pago: sube la imagen en Ajustes › Ventas por '
              'defecto › Imagen del QR de pago.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  final url = ImagenRecurso.absoluta(ruta);
  return Column(
    children: [
      Container(
        width: tamano,
        height: tamano,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: url == null
            ? const ContenedorPlaceholder(
                tamano: double.infinity,
                radio: 8,
                icono: Icons.qr_code_2_rounded,
              )
            : Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    const ContenedorPlaceholder(
                      tamano: double.infinity,
                      radio: 8,
                      icono: Icons.qr_code_2_rounded,
                    ),
              ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Escanea para pagar',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}
