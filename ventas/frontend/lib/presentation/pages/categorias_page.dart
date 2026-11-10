import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo de catálogos: pestañas de `Categorías`, `Presentaciones`,
/// `Colores` y `Marcas` (mismo patrón de chips de filtros de la guía).
///
/// Los colores son el catálogo de variantes de los productos (migración
/// 022): la tabla es genérica (Nombre / Estado / ID) y el formulario añade
/// la muestra `#RRGGBB` opcional, que solo pinta el chip en la UI — nunca se
/// imprime en recibos. Las marcas (023) son texto puro: el producto puede
/// llevarla o no, y solo se imprime en el Recibo 1 de la orden.
class CategoriasPage extends StatefulWidget {
  const CategoriasPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<CategoriasPage> createState() => _CategoriasPageState();
}

/// Pestaña activa de la página.
enum _Vista { categorias, presentaciones, colores, marcas }

class _CategoriasPageState extends State<CategoriasPage> {
  _Vista _vista = _Vista.categorias;

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

  /// Nombre hasta 50 (como `colores.nombre`) y la muestra opcional, que se
  /// elige de una paleta (nunca se teclea el hexadecimal). Vacío = sin
  /// muestra: el formulario envía `codigoHex: null` explícito para poder
  /// **quitarla** en una edición.
  static final _camposColores = [
    CampoFormulario(
      clave: 'nombre',
      etiqueta: 'Nombre *',
      obligatorio: true,
      minCaracteres: 2,
      maxCaracteres: 50,
    ),
    CampoFormulario(
      clave: 'codigoHex',
      etiqueta: 'Muestra del color',
      tipo: TipoCampo.color,
      auxiliar:
          'Color del chip en pantalla (se elige de la paleta). Solo es '
          'color de UI: no se imprime en el recibo. Vacío = sin muestra.',
    ),
    CampoFormulario(
      clave: 'estado',
      etiqueta: 'Estado *',
      tipo: TipoCampo.opcion,
      obligatorio: true,
      opciones: estadosGenerales,
    ),
  ];

  /// Nombre hasta 50 (como `marcas.nombre`): catálogo de texto puro, sin
  /// muestra hexadecimal.
  static const _camposMarcas = [
    CampoFormulario(
      clave: 'nombre',
      etiqueta: 'Nombre *',
      obligatorio: true,
      minCaracteres: 2,
      maxCaracteres: 50,
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

  RecursoController _controlador() => switch (_vista) {
    _Vista.categorias => context.read<CategoriasController>(),
    _Vista.presentaciones => context.read<PresentacionesController>(),
    _Vista.colores => context.read<ColoresController>(),
    _Vista.marcas => context.read<MarcasController>(),
  };

  @override
  Widget build(BuildContext context) {
    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Categorías',
      controller: _controlador(),
      tituloSeccion: switch (_vista) {
        _Vista.categorias => 'Gestión de Categorías',
        _Vista.presentaciones => 'Gestión de Presentaciones',
        _Vista.colores => 'Gestión de Colores',
        _Vista.marcas => 'Gestión de Marcas',
      },
      etiquetaNuevo: switch (_vista) {
        _Vista.categorias => 'Nueva Categoría',
        _Vista.presentaciones => 'Nueva Presentación',
        _Vista.colores => 'Nuevo Color',
        _Vista.marcas => 'Nueva Marca',
      },
      entidad: switch (_vista) {
        _Vista.categorias => 'categoría',
        _Vista.presentaciones => 'presentación',
        _Vista.colores => 'color',
        _Vista.marcas => 'marca',
      },
      tituloFormulario: switch (_vista) {
        _Vista.categorias => 'Nueva Categoría',
        _Vista.presentaciones => 'Nueva Presentación',
        _Vista.colores => 'Nuevo Color',
        _Vista.marcas => 'Nueva Marca',
      },
      textoVacio: switch (_vista) {
        _Vista.categorias => 'No hay categorías',
        _Vista.presentaciones => 'No hay presentaciones',
        _Vista.colores => 'No hay colores',
        _Vista.marcas => 'No hay marcas',
      },
      mensajeCreado: switch (_vista) {
        _Vista.categorias => 'Categoría creada',
        _Vista.presentaciones => 'Presentación creada',
        _Vista.colores => 'Color creado',
        _Vista.marcas => 'Marca creada',
      },
      mensajeActualizado: switch (_vista) {
        _Vista.categorias => 'Categoría actualizada',
        _Vista.presentaciones => 'Presentación actualizada',
        _Vista.colores => 'Color actualizado',
        _Vista.marcas => 'Marca actualizada',
      },
      mensajeEliminado: switch (_vista) {
        _Vista.categorias => 'Categoría ocultada',
        _Vista.presentaciones => 'Presentación ocultada',
        _Vista.colores => 'Color ocultado',
        _Vista.marcas => 'Marca ocultada',
      },
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('INACTIVO', 'Inactivos'),
      ],
      complementoCabecera: _pestanas(),
      columnas: _columnasComunes,
      campos: switch (_vista) {
        _Vista.colores => _camposColores,
        _Vista.marcas => _camposMarcas,
        _ => _camposComunes,
      },
    );
  }

  Widget _pestanas() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _pestana(_Vista.categorias, 'Categorías', icono: Icons.folder_outlined),
        _pestana(
          _Vista.presentaciones,
          'Presentaciones',
          icono: Icons.inventory_2_outlined,
        ),
        _pestana(_Vista.colores, 'Colores', icono: Icons.palette_outlined),
        _pestana(_Vista.marcas, 'Marcas', icono: Icons.storefront_outlined),
      ],
    );
  }

  Widget _pestana(_Vista destino, String etiqueta, {required IconData icono}) {
    final seleccionada = _vista == destino;
    return FilterChip(
      avatar: seleccionada
          ? null
          : Icon(icono, size: 16, color: AppColors.textSecondary),
      label: Text(etiqueta),
      selected: seleccionada,
      onSelected: (_) {
        if (!seleccionada) setState(() => _vista = destino);
      },
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
