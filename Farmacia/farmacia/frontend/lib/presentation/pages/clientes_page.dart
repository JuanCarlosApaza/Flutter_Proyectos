import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/recurso_controller.dart';
import '../widgets/alta_persona.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Módulo de clientes (ejemplo modelo de la guía).
class ClientesPage extends StatelessWidget {
  const ClientesPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  Widget build(BuildContext context) {
    return RecursoPage(
      selectedNav: selectedNav,
      onNavSelect: onNavSelect,
      tituloBarra: 'Clientes',
      controller: context.read<ClientesController>(),
      tituloSeccion: 'Gestión de Clientes',
      etiquetaNuevo: 'Nuevo Cliente',
      entidad: 'cliente',
      textoVacio: 'No hay clientes registrados',
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('INACTIVO', 'Inactivos'),
        FiltroEstado('BLOQUEADO', 'Bloqueados'),
      ],
      columnas: const [
        ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre', flex: 3),
        ColumnaTabla(clave: 'apellido', etiqueta: 'Apellido', flex: 3),
        ColumnaTabla(clave: 'ci', etiqueta: 'CI', flex: 2),
        ColumnaTabla(clave: 'ciudad', etiqueta: 'Ciudad', flex: 2),
        ColumnaTabla(clave: 'telefono', etiqueta: 'Teléfono', flex: 2),
        ColumnaTabla(clave: 'estado', etiqueta: 'Estado', flex: 2, chip: true),
      ],
      // Misma ficha que el alta rápida desde la caja (ver `alta_persona.dart`).
      campos: camposCliente,
    );
  }
}
