import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'qr_acceso.dart';

/// Barra superior de la zona de contenido: hamburguesa (solo tablet/mobile)
/// + título de la pantalla. En desktop el botón de menú no aparece porque
/// el sidebar ya está visible.
class DashboardTopBar extends StatelessWidget {
  const DashboardTopBar({
    super.key,
    required this.title,
    required this.showMenuButton,
    required this.onMenuTap,
    this.showAccessQr = false,
  });

  final String title;
  final bool showMenuButton;
  final VoidCallback onMenuTap;

  /// Muestra el QR de acceso móvil en la esquina superior derecha
  /// (solo en web: `ResponsiveLayout` lo decide según plataforma y ancho).
  final bool showAccessQr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showMenuButton) ...[
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (showAccessQr) ...[const SizedBox(width: 8), const QrAccesoButton()],
      ],
    );
  }
}
