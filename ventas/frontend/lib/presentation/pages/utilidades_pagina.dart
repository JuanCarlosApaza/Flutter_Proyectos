import 'package:flutter/material.dart';

import '../controllers/recurso_controller.dart';

/// Precarga los controladores de apoyo (combos de los formularios) después
/// del primer frame, para no notificar a los listeners durante el build.
///
/// Solo pide el **lote completo** que falte: aunque el controlador tenga ya
/// una página de tabla cargada (`state == loaded`), los combos necesitan el
/// conjunto en cliente.
void precargarDespuesDelPrimerFrame(
  BuildContext context,
  List<RecursoController> controladores,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    for (final controlador in controladores) {
      if (!controlador.completoCargado) controlador.cargar();
    }
  });
}
