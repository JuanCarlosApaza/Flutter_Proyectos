import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../controllers/auth_controller.dart';
import 'activacion_suscripcion.dart';

/// Pantalla de bloqueo por suscripción: la API ha devuelto
/// `403 suscripcion_vencida` (venció el plazo o el guardián de fecha detectó
/// un reloj retrocedido) y toda la app queda congelada en esta pantalla.
///
/// Los datos nunca se tocan: al activar una clave válida, el controlador
/// baja la bandera y la app vuelve sola a donde estaba.
class SuscripcionBloqueada extends StatelessWidget {
  const SuscripcionBloqueada({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_clock,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sistema bloqueado',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  auth.motivoSuscripcion.isEmpty
                      ? 'La suscripción de este sistema ha vencido.'
                      : auth.motivoSuscripcion,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tus datos siguen guardados: introduce la clave de '
                  'suscripción para continuar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ActivacionSuscripcion(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
