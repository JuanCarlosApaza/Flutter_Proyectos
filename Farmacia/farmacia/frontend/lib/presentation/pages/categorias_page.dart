import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo de categorías: pestañas de `Categorías` y `Presentaciones`
/// (mismo patrón de chips de filtros de la guía).
class CategoriasPage extends StatefulWidget {
  const CategoriasPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<CategoriasPage> createState() => _CategoriasPageState();
}

class _CategoriasPageState extends State<CategoriasPage> {
  bool _enCategorias = true;

  static const _camposComunes = [
    CampoFormulario(
      clave: 'nombre',
      etiqueta: 'Nombre *',
      obligatorio: true,
      minCaracteres: 2,
      maxCaracteres: 150,
    ),
    CampoFormulario(
      clave: 'estado',
      etiqueta: 'Estado *',
      tipo: TipoCampo.opcion,
      obligatorio: true,
      opciones: estadosGenerales,
    ),
  ];

  static const _columnasComunes = [
    ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre', flex: 5),
    ColumnaTabla(clave: 'estado', etiqueta: 'Estado', flex: 3, chip: true),
    ColumnaTabla(clave: 'id', etiqueta: 'ID', flex: 1),
  ];

  @override
  Widget build(BuildContext context) {
    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Categorías',
      controller: _enCategorias
          ? context.read<CategoriasController>()
          : context.read<PresentacionesController>(),
      tituloSeccion: _enCategorias
          ? 'Gestión de Categorías'
          : 'Gestión de Presentaciones',
      etiquetaNuevo: _enCategorias ? 'Nueva Categoría' : 'Nueva Presentación',
      entidad: _enCategorias ? 'categoría' : 'presentación',
      tituloFormulario: _enCategorias
          ? 'Nueva Categoría'
          : 'Nueva Presentación',
      textoVacio: _enCategorias ? 'No hay categorías' : 'No hay presentaciones',
      mensajeCreado: _enCategorias ? 'Categoría creada' : 'Presentación creada',
      mensajeActualizado: _enCategorias
          ? 'Categoría actualizada'
          : 'Presentación actualizada',
      mensajeEliminado: _enCategorias
          ? 'Categoría ocultada'
          : 'Presentación ocultada',
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('INACTIVO', 'Inactivos'),
      ],
      complementoCabecera: _pestanas(),
      columnas: _columnasComunes,
      campos: _camposComunes,
    );
  }

  Widget _pestanas() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _pestana(
          'Categorías',
          seleccionada: _enCategorias,
          onTap: () {
            if (!_enCategorias) setState(() => _enCategorias = true);
          },
        ),
        _pestana(
          'Presentaciones',
          seleccionada: !_enCategorias,
          onTap: () {
            if (_enCategorias) setState(() => _enCategorias = false);
          },
        ),
      ],
    );
  }

  Widget _pestana(
    String etiqueta, {
    required bool seleccionada,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      avatar: seleccionada
          ? null
          : const Icon(
              Icons.folder_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
      label: Text(etiqueta),
      selected: seleccionada,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.brandGreen,
      checkmarkColor: Colors.white,
      backgroundColor: AppColors.cardBg,
      side: const BorderSide(color: AppColors.cardBorder),
      labelStyle: TextStyle(
        color: seleccionada ? Colors.white : AppColors.textSecondary,
        fontWeight: seleccionada ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
      ),
    );
  }
}
