import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/recurso_controller.dart';
import '../widgets/alta_persona.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo de empleados.
class EmpleadosPage extends StatelessWidget {
  const EmpleadosPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  Widget build(BuildContext context) {
    return RecursoPage(
      selectedNav: selectedNav,
      onNavSelect: onNavSelect,
      tituloBarra: 'Empleados',
      controller: context.read<EmpleadosController>(),
      tituloSeccion: 'Gestión de Empleados',
      etiquetaNuevo: 'Nuevo Empleado',
      entidad: 'empleado',
      textoVacio: 'No hay empleados registrados',
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('VACACIONES', 'Vacaciones'),
        FiltroEstado('LICENCIA', 'Licencia'),
        FiltroEstado('INACTIVO', 'Inactivos'),
      ],
      columnas: const [
        ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre', flex: 3),
        ColumnaTabla(clave: 'apellido', etiqueta: 'Apellido', flex: 3),
        ColumnaTabla(clave: 'rol', etiqueta: 'Rol', flex: 3),
        ColumnaTabla(clave: 'ciudad', etiqueta: 'Ciudad', flex: 3),
        ColumnaTabla(clave: 'estado', etiqueta: 'Estado', flex: 2, chip: true),
      ],
      // Misma ficha que el alta rápida desde Usuarios (ver `alta_persona.dart`).
      campos: camposEmpleado,
    );
  }
}
