import 'package:flutter/material.dart';
import 'package:quickalert/quickalert.dart';

import '../theme/app_colors.dart';

/// Alertas de la app basadas en [QuickAlert] (paquete `quickalert`).
///
/// Toda la confirmación y el resultado de una acción pasan por estas
/// funciones para que el aspecto sea único en todo el sistema: icono
/// animado, paleta de [AppColors] y un solo botón de confirmación (verde de
/// marca, o rojo cuando la acción oculta registros).
///
/// Regla de la casa: los `SnackBar` quedan fuera; se usan estas alertas.
/// La única excepción son los diálogos con campos de datos (selector de
/// estado, QR), que necesitan `showDialog`.

/// Aviso de operación exitosa (palomita verde).
Future<void> alertaExito(
  BuildContext context, {
  String titulo = '¡Listo!',
  String? mensaje,
  String textoBoton = 'Aceptar',
}) {
  return _alerta(
    context,
    type: QuickAlertType.success,
    titulo: titulo,
    mensaje: mensaje,
    textoBoton: textoBoton,
    colorBoton: AppColors.brandGreen,
  );
}

/// Aviso de operación fallida (cruz roja).
Future<void> alertaError(
  BuildContext context, {
  String titulo = 'Error',
  required String mensaje,
  String textoBoton = 'Entendido',
}) {
  return _alerta(
    context,
    type: QuickAlertType.error,
    titulo: titulo,
    mensaje: mensaje,
    textoBoton: textoBoton,
    colorBoton: AppColors.negativeRed,
  );
}

/// Aviso informativo (i azul).
Future<void> alertaInfo(
  BuildContext context, {
  String titulo = 'Información',
  required String mensaje,
  String textoBoton = 'Aceptar',
}) {
  return _alerta(
    context,
    type: QuickAlertType.info,
    titulo: titulo,
    mensaje: mensaje,
    textoBoton: textoBoton,
    colorBoton: AppColors.infoBlue,
  );
}

/// Aviso de atención (signo de exclamación naranja).
Future<void> alertaAdvertencia(
  BuildContext context, {
  String titulo = 'Atención',
  required String mensaje,
  String textoBoton = 'Entendido',
}) {
  return _alerta(
    context,
    type: QuickAlertType.warning,
    titulo: titulo,
    mensaje: mensaje,
    textoBoton: textoBoton,
    colorBoton: AppColors.warningOrange,
  );
}

/// Diálogo de confirmación **Cancelar / Confirmar**.
///
/// Devuelve `true` solo cuando el usuario pulsa el botón de confirmar;
/// `false` si cancela, pulsa fuera del diálogo o usa el botón atrás.
///
/// [nota] es un párrafo secundario opcional bajo [mensaje] (para explicar,
/// por ejemplo, que el borrado es lógico y no se pierde información).
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String? nota,
  String textoConfirmar = 'Aceptar',
  String textoCancelar = 'Cancelar',
  Color colorConfirmar = AppColors.brandGreen,
}) async {
  final resultado = await QuickAlert.show(
    context: context,
    type: QuickAlertType.confirm,
    title: titulo,
    text: mensaje,
    widget: nota == null
        ? null
        : Text(
            nota,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
    confirmBtnText: textoConfirmar,
    cancelBtnText: textoCancelar,
    confirmBtnColor: colorConfirmar,
    titleColor: AppColors.textPrimary,
    textColor: AppColors.textPrimary,
    backgroundColor: AppColors.cardBg,
    headerBackgroundColor: AppColors.pageBg,
    onConfirmBtnTap: () => Navigator.pop(context, true),
    onCancelBtnTap: () => Navigator.pop(context, false),
  );
  return resultado == true;
}

/// Implementación común de [alertaExito], [alertaError], [alertaInfo] y
/// [alertaAdvertencia]: un solo botón que cierra el diálogo.
Future<void> _alerta(
  BuildContext context, {
  required QuickAlertType type,
  required String titulo,
  String? mensaje,
  required String textoBoton,
  required Color colorBoton,
}) {
  return QuickAlert.show(
    context: context,
    type: type,
    title: titulo,
    text: mensaje,
    confirmBtnText: textoBoton,
    confirmBtnColor: colorBoton,
    confirmBtnTextStyle: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      fontSize: 15,
    ),
    titleColor: AppColors.textPrimary,
    textColor: AppColors.textSecondary,
    backgroundColor: AppColors.cardBg,
    headerBackgroundColor: AppColors.pageBg,
    barrierDismissible: true,
  );
}
