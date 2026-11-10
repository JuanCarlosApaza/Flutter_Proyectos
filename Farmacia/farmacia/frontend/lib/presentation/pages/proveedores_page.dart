import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/validation/reglas.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo de proveedores.
class ProveedoresPage extends StatelessWidget {
  const ProveedoresPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  Widget build(BuildContext context) {
    return RecursoPage(
      selectedNav: selectedNav,
      onNavSelect: onNavSelect,
      tituloBarra: 'Proveedores',
      controller: context.read<ProveedoresController>(),
      tituloSeccion: 'Gestión de Proveedores',
      etiquetaNuevo: 'Nuevo Proveedor',
      entidad: 'proveedor',
      textoVacio: 'No hay proveedores registrados',
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('INACTIVO', 'Inactivos'),
      ],
      columnas: const [
        ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre', flex: 4),
        ColumnaTabla(clave: 'ciudad', etiqueta: 'Ciudad', flex: 3),
        ColumnaTabla(clave: 'telefono', etiqueta: 'Teléfono', flex: 3),
        ColumnaTabla(clave: 'estado', etiqueta: 'Estado', flex: 2, chip: true),
      ],
      campos: const [
        CampoFormulario(
          clave: 'nombre',
          etiqueta: 'Nombre *',
          obligatorio: true,
          minCaracteres: 2,
          maxCaracteres: 150,
        ),
        CampoFormulario(
          clave: 'direccion',
          etiqueta: 'Dirección',
          maxCaracteres: 200,
        ),
        CampoFormulario(
          clave: 'ciudad',
          etiqueta: 'Ciudad',
          maxCaracteres: 100,
        ),
        CampoFormulario(
          clave: 'telefono',
          etiqueta: 'Teléfono',
          maxCaracteres: 20,
          validador: telefonoValido,
        ),
        CampoFormulario(
          clave: 'estado',
          etiqueta: 'Estado *',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          opciones: estadosGenerales,
        ),
      ],
    );
  }
}
