import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'alertas.dart';

/// Diálogo de confirmación de **ocultamiento** (patrón de toda la app).
///
/// La operación es un borrado lógico: el registro pasa a `estado = ELIMINADO`
/// y deja de aparecer en los listados, pero **no se borra de la base de
/// datos**. Por eso el diálogo lo dice explícitamente: el usuario no debe
/// creer que la información se pierde.
///
/// Se muestra con [confirmarAccion] (QuickAlert) para mantener el mismo
/// aspecto que el resto de las alertas del sistema.
Future<void> confirmarEliminacion({
  required BuildContext context,
  required String titulo,
  required String descripcion,
  required Future<void> Function() onConfirmar,
}) async {
  final confirmado = await confirmarAccion(
    context,
    titulo: 'Ocultar $titulo',
    mensaje: descripcion,
    nota:
        'El registro no se elimina de la base de datos: solo deja de '
        'aparecer en las listas.',
    textoConfirmar: 'Ocultar',
    textoCancelar: 'Cancelar',
    colorConfirmar: AppColors.negativeRed,
  );

  if (confirmado) await onConfirmar();
}
