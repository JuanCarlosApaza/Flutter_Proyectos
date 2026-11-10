import 'package:flutter/material.dart';

import '../../core/widgets/responsive_layout.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';

/// Plantilla estándar de pantalla: `ResponsiveLayout` + contenido genérico.
///
/// Cada módulo crea una pantalla de este tipo pasando su controller, sus
/// columnas y sus campos (ver §8 de la guía de diseño).
class RecursoPage extends StatelessWidget {
  const RecursoPage({
    super.key,
    this.selectedNav,
    this.onNavSelect,
    required this.tituloBarra,
    required this.controller,
    required this.tituloSeccion,
    this.etiquetaNuevo,
    this.accionesCabecera,
    required this.entidad,
    required this.columnas,
    required this.campos,
    this.pestanas,
    this.filtros,
    this.herramientasExtra,
    this.textoVacio,
    this.tituloFormulario,
    this.complementoCabecera,
    this.mensajeCreado,
    this.mensajeActualizado,
    this.mensajeEliminado,
    this.validar,
    this.accionesExtras,
    this.anchoAcciones,
    this.soloLectura = false,
  });

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  /// Título de la top bar.
  final String tituloBarra;

  final RecursoController controller;

  /// Título del `PageHeader` ("Gestión de Clientes").
  final String tituloSeccion;

  /// Etiqueta del botón de alta; `null` (o [soloLectura]) = sin botón.
  final String? etiquetaNuevo;

  /// Acciones extra en el cabezal, a la izquierda del botón de alta (p. ej.
  /// «Importar Excel» al lado de «Nuevo»). Se ocultan sin permiso de creación.
  final List<Widget>? accionesCabecera;
  final String entidad;
  final List<ColumnaTabla> columnas;
  final List<CampoFormulario> campos;
  final List<FiltroEstado>? filtros;

  /// Widgets extra junto al buscador y a los chips de estado (p. ej. el
  /// desplegable «Marca» de la tabla de productos, que filtra en el
  /// servidor con `?marcaId=`).
  final List<Widget>? herramientasExtra;

  /// Pestañas del formulario (ver `RecursoForm.pestanas`).
  final List<PestanaFormulario>? pestanas;
  final String? textoVacio;
  final String? tituloFormulario;
  final Widget? complementoCabecera;
  final String? mensajeCreado;
  final String? mensajeActualizado;
  final String? mensajeEliminado;

  /// Página de solo consulta (p. ej. Auditoría): sin altas, ediciones ni
  /// borrados; la ficha de detalle (👁) sigue disponible.
  final bool soloLectura;

  /// Validación entre campos del formulario (ver `RecursoForm.validar`).
  final String? Function(Map<String, Object?> valores)? validar;

  /// Botones extra por fila y ancho de la columna de acciones.
  final List<Widget> Function(Recurso)? accionesExtras;
  final double? anchoAcciones;

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedNav: selectedNav,
      onNavSelect: onNavSelect,
      title: tituloBarra,
      // Gesto de actualizar: recarga el listado de este módulo.
      onRefresh: controller.recargar,
      contentBuilder: (context, constraints) => RecursoContenido(
        controller: controller,
        tituloSeccion: tituloSeccion,
        etiquetaNuevo: etiquetaNuevo,
        accionesCabecera: accionesCabecera,
        entidad: entidad,
        columnas: columnas,
        campos: campos,
        pestanas: pestanas,
        filtros: filtros,
        herramientasExtra: herramientasExtra,
        textoVacio: textoVacio,
        tituloFormulario: tituloFormulario,
        complementoCabecera: complementoCabecera,
        mensajeCreado: mensajeCreado,
        mensajeActualizado: mensajeActualizado,
        mensajeEliminado: mensajeEliminado,
        validar: validar,
        accionesExtras: accionesExtras,
        anchoAcciones: anchoAcciones,
        soloLectura: soloLectura,
      ),
    );
  }
}
