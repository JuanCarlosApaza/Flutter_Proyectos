import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo de catálogo: pestañas de `Categorías`, `Tallas`, `Colores` y
/// `Marcas` (mismo patrón de chips de filtros de la guía).
///
/// Tallas y colores son los catálogos de los que cuelgan las variantes de
/// cada prenda (talla + color = stock real); las marcas son el catálogo
/// opcional del que depende `productos.marcaId`.
class CategoriasPage extends StatefulWidget {
  const CategoriasPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<CategoriasPage> createState() => _CategoriasPageState();
}

/// Sección activa del módulo de catálogo.
enum _Seccion { categorias, tallas, colores, marcas }

class _CategoriasPageState extends State<CategoriasPage> {
  _Seccion _seccion = _Seccion.categorias;

  static const _camposComunes = [
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
    final categorias = context.read<CategoriasController>();
    final tallas = context.read<TallasController>();
    final colores = context.read<ColoresController>();
    final marcas = context.read<MarcasController>();

    final (
      controlador,
      titulo,
      etiqueta,
      entidad,
      campos,
      mensajes,
    ) = switch (_seccion) {
      _Seccion.categorias => (
        categorias,
        'Gestión de Categorías',
        'Nueva Categoría',
        'categoría',
        _camposComunes,
        ('Categoría creada', 'Categoría actualizada', 'Categoría ocultada'),
      ),
      _Seccion.tallas => (
        tallas,
        'Gestión de Tallas',
        'Nueva Talla',
        'talla',
        [
          const CampoFormulario(
            clave: 'nombre',
            etiqueta: 'Nombre *',
            tipo: TipoCampo.talla,
            obligatorio: true,
            minCaracteres: 1,
            maxCaracteres: 30,
            validador: tallaValida,
          ),
          const CampoFormulario(
            clave: 'orden',
            etiqueta: 'Orden de exhibición',
            tipo: TipoCampo.numero,
            min: 0,
            max: 9999,
            auxiliar: 'Menor = primero · vacío = 0',
          ),
          ..._camposComunes,
        ],
        ('Talla creada', 'Talla actualizada', 'Talla ocultada'),
      ),
      _Seccion.colores => (
        colores,
        'Gestión de Colores',
        'Nuevo Color',
        'color',
        [
          const CampoFormulario(
            clave: 'nombre',
            etiqueta: 'Nombre *',
            obligatorio: true,
            minCaracteres: 2,
            maxCaracteres: 50,
          ),
          const CampoFormulario(
            clave: 'codigoHex',
            etiqueta: 'Color',
            tipo: TipoCampo.color,
            maxCaracteres: 7,
            auxiliar: 'Escoge el tono en la paleta · vacío = sin color',
          ),
          ..._camposComunes,
        ],
        ('Color creado', 'Color actualizado', 'Color ocultado'),
      ),
      _Seccion.marcas => (
        marcas,
        'Gestión de Marcas',
        'Nueva Marca',
        'marca',
        [
          const CampoFormulario(
            clave: 'nombre',
            etiqueta: 'Nombre *',
            obligatorio: true,
            minCaracteres: 2,
            maxCaracteres: 100,
          ),
          ..._camposComunes,
        ],
        ('Marca creada', 'Marca actualizada', 'Marca ocultada'),
      ),
    };

    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Catálogo',
      controller: controlador,
      tituloSeccion: titulo,
      etiquetaNuevo: etiqueta,
      entidad: entidad,
      tituloFormulario: etiqueta,
      textoVacio: 'No hay registros',
      mensajeCreado: mensajes.$1,
      mensajeActualizado: mensajes.$2,
      mensajeEliminado: mensajes.$3,
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('INACTIVO', 'Inactivos'),
      ],
      complementoCabecera: _pestanas(),
      columnas: _columnasComunes,
      campos: campos,
    );
  }

  Widget _pestanas() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _pestana('Categorías', _Seccion.categorias),
        _pestana('Tallas', _Seccion.tallas),
        _pestana('Colores', _Seccion.colores),
        _pestana('Marcas', _Seccion.marcas),
      ],
    );
  }

  Widget _pestana(String etiqueta, _Seccion valor) {
    final seleccionada = _seccion == valor;
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
      onSelected: (_) {
        if (_seccion != valor) setState(() => _seccion = valor);
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
