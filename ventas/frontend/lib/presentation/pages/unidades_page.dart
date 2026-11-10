import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/recurso_controller.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo «Unidades»: el catálogo de unidades de medida
/// (`GET/POST/PUT/DELETE /unidades`), 13º módulo de la app (migración
/// `017_unidades_medida`).
///
/// Es la única fuente del desplegable «Unidad de venta» del producto y del
/// campo de cantidad del carrito: cada unidad dice qué símbolo viaja en
/// `productos.unidad`, de qué tipo es (peso, volumen o unidad) y con cuántos
/// decimales admite la cantidad (KG → 3, CAJA → 0).
///
/// El `codigo` es la clave natural del catálogo: se elige al crear y no se
/// puede cambiar después (viaja en cada producto, y la API responde
/// `400 codigo_inmutable`), de ahí `soloEnCreacion`.
class UnidadesPage extends StatelessWidget {
  const UnidadesPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  /// Campos de la ficha (`static final` porque `patron` necesita un [RegExp],
  /// que no es constante).
  static final List<CampoFormulario> _campos = [
    CampoFormulario(
      clave: 'codigo',
      etiqueta: 'Código *',
      obligatorio: true,
      maxCaracteres: 10,
      // Inmutable: viaja en `productos.unidad`, así que solo se elige al
      // crear (la ficha de edición ni lo muestra).
      soloEnCreacion: true,
      patron: RegExp(r'^[A-Za-z0-9]+$'),
      mensajePatron: 'Solo letras y números, sin espacios (p. ej. KG, ONZA)',
      auxiliar:
          'Símbolo corto que se guarda en el producto (≤ 10). '
          'No se puede cambiar después.',
    ),
    CampoFormulario(
      clave: 'nombre',
      etiqueta: 'Nombre *',
      obligatorio: true,
      minCaracteres: 2,
      maxCaracteres: 50,
      auxiliar: 'Nombre completo que ve el usuario (p. ej. Kilogramo).',
    ),
    CampoFormulario(
      clave: 'tipo',
      etiqueta: 'Tipo *',
      tipo: TipoCampo.opcion,
      obligatorio: true,
      opciones: tiposUnidad,
      auxiliar: 'Peso y volumen se fraccionan; lo demás se cuenta por envase.',
    ),
    CampoFormulario(
      clave: 'decimales',
      etiqueta: 'Decimales *',
      tipo: TipoCampo.numero,
      obligatorio: true,
      min: 0,
      max: 3,
      soloDigitos: true,
      auxiliar: 'Máximo de decimales de la cantidad (KG → 3, CAJA → 0).',
    ),
    CampoFormulario(
      clave: 'estado',
      etiqueta: 'Estado *',
      tipo: TipoCampo.opcion,
      obligatorio: true,
      opciones: estadosGenerales,
    ),
  ];

  static const List<ColumnaTabla> _columnas = [
    ColumnaTabla(clave: 'codigo', etiqueta: 'Código', flex: 2),
    ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre', flex: 4),
    ColumnaTabla(clave: 'tipo', etiqueta: 'Tipo', flex: 2, chip: true),
    ColumnaTabla(clave: 'decimales', etiqueta: 'Decimales', flex: 2),
    ColumnaTabla(clave: 'estado', etiqueta: 'Estado', flex: 2, chip: true),
    ColumnaTabla(clave: 'id', etiqueta: 'ID', flex: 1),
  ];

  @override
  Widget build(BuildContext context) {
    return RecursoPage(
      selectedNav: selectedNav,
      onNavSelect: onNavSelect,
      tituloBarra: 'Unidades',
      controller: context.read<UnidadesController>(),
      tituloSeccion: 'Gestión de Unidades de Medida',
      etiquetaNuevo: 'Nueva Unidad',
      entidad: 'unidad',
      tituloFormulario: 'Nueva Unidad',
      textoVacio: 'No hay unidades de medida',
      mensajeCreado: 'Unidad creada',
      mensajeActualizado: 'Unidad actualizada',
      mensajeEliminado: 'Unidad ocultada',
      filtros: const [
        FiltroEstado('ACTIVO', 'Activas'),
        FiltroEstado('INACTIVO', 'Inactivas'),
      ],
      columnas: _columnas,
      campos: _campos,
    );
  }
}
