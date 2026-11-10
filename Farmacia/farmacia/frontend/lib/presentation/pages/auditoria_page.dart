import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/nav_scope.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';

/// Entidades que registra la auditoría (desplegable «Entidad»).
const List<String> _entidades = [
  'productos',
  'categorias',
  'presentaciones',
  'clientes',
  'proveedores',
  'empleados',
  'usuarios',
  'roles',
  'ordenes',
  'facturas',
  'cotizaciones',
  'ajustes',
  'archivos',
  'auth',
  'auditoria',
];

/// Acciones del desplegable «Acción» (el mismo catálogo que usa la API).
const List<String> _acciones = [
  'LOGIN',
  'LOGIN_FALLIDO',
  'LOGOUT',
  'CREAR',
  'ACTUALIZAR',
  'ELIMINAR',
  'RESTABLECER_CONTRASENA',
];

/// Módulo de Auditoría (índice 10 del menú).
///
/// Consulta de los eventos registrados por el backend: quién hizo qué,
/// cuándo, desde dónde y con qué resultado. Es de **solo lectura** (la tabla
/// no se edita ni se borra fila a fila); la limpieza masiva va por el menú
/// «Limpiar registros» con su propio permiso (`auditoria.eliminar`).
///
/// La búsqueda por **usuario** y **fecha (desde/hasta)** se hace en la BD:
/// el toolbar del `complementoCabecera` monta los filtros del controller.
class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  final _usuarioCtrl = TextEditingController();
  DateTime? _desde;
  DateTime? _hasta;

  /// `''` = todas (el valor viaja al `buscar` como query param).
  String _entidad = '';
  String _accion = '';

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `indiceDe` suscribe la página al NavScope: el IndexedStack mantiene
    // este módulo vivo sin reconstruirlo, así que sin esta recarga la lista
    // se quedaría con los eventos antiguos tras modificar otra parte del
    // sistema (productos, clientes...).
    final indice = NavScope.indiceDe(context);
    if (indice != widget.selectedNav) return;

    // Se refuerza en el siguiente frame para no notificar dentro del build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AuditoriaController>();
      // Solo al "volver": en el primer montaje la carga RecursoContenido.
      if (controller.state == LoadState.loaded ||
          controller.state == LoadState.error) {
        controller.recargar();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AuditoriaController>();

    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Auditoría',
      controller: controller,
      tituloSeccion: 'Auditoría de cambios',
      entidad: 'auditoría',
      textoVacio: 'Sin registros de auditoría',
      soloLectura: true,
      complementoCabecera: _toolbar(controller),
      columnas: [
        ColumnaTabla(
          clave: 'fecha',
          etiqueta: 'Fecha',
          flex: 3,
          formato: _fechaCorta,
        ),
        const ColumnaTabla(
          clave: 'nombreUsuario',
          etiqueta: 'Usuario',
          flex: 3,
        ),
        const ColumnaTabla(clave: 'rol', etiqueta: 'Rol', flex: 2),
        ColumnaTabla(
          clave: 'accion',
          etiqueta: 'Acción',
          flex: 2,
          formato: (r) => r['exitoso'] == false
              ? '${r['accion']} ✗'
              : r['accion'].toString(),
        ),
        ColumnaTabla(
          clave: 'entidad',
          etiqueta: 'Entidad',
          flex: 2,
          formato: _entidadConId,
        ),
        const ColumnaTabla(clave: 'resumen', etiqueta: 'Operación', flex: 5),
      ],
      campos: const [
        CampoFormulario(clave: 'fecha', etiqueta: 'Fecha'),
        CampoFormulario(clave: 'nombreUsuario', etiqueta: 'Usuario'),
        CampoFormulario(clave: 'rol', etiqueta: 'Rol'),
        CampoFormulario(clave: 'accion', etiqueta: 'Acción'),
        CampoFormulario(clave: 'entidad', etiqueta: 'Entidad'),
        CampoFormulario(
          clave: 'resumen',
          etiqueta: 'Operación',
          maximasLineas: 2,
        ),
        CampoFormulario(
          clave: 'codigoError',
          etiqueta: 'Código del error',
          auxiliar: 'Solo aparece si la operación fue rechazada',
        ),
        CampoFormulario(clave: 'ip', etiqueta: 'IP de origen'),
        CampoFormulario(
          clave: 'detalles',
          etiqueta: 'Detalles',
          maximasLineas: 12,
          auxiliar: 'Detalle explícito que aporta cada operación',
        ),
      ],
    );
  }

  // --- Toolbar de búsqueda y limpieza ---------------------------------------

  Widget _toolbar(AuditoriaController controller) {
    final sesion = SesionScope.de(context);
    final puedePurgar =
        sesion?.puede(Modulos.auditoria, Acciones.eliminar) ?? true;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _usuarioCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Usuario',
              prefixIcon: Icon(Icons.person_search_rounded, size: 18),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _buscar(controller),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(
            _desde == null ? 'Desde' : 'Desde ${_fechaTexto(_desde!)}',
            style: const TextStyle(fontSize: 13),
          ),
          onPressed: () => _elegirFecha(esDesde: true),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(
            _hasta == null ? 'Hasta' : 'Hasta ${_fechaTexto(_hasta!)}',
            style: const TextStyle(fontSize: 13),
          ),
          onPressed: () => _elegirFecha(esDesde: false),
        ),
        SizedBox(
          width: 175,
          child: DropdownButtonFormField<String>(
            key: ValueKey('entidad$_entidad'),
            initialValue: _entidad,
            isDense: true,
            // El ítem seleccionado se estira: sin esto, textos largos
            // («presentaciones») desbordan el RenderFlex del campo.
            isExpanded: true,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Entidad',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todas')),
              for (final entidad in _entidades)
                DropdownMenuItem(
                  value: entidad,
                  child: Text(entidad, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (valor) => setState(() => _entidad = valor ?? ''),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            key: ValueKey('accion$_accion'),
            initialValue: _accion,
            isDense: true,
            // El ítem seleccionado se estira: «RESTABLECER_CONTRASENA» es
            // largo y si no, desborda el RenderFlex del campo.
            isExpanded: true,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Acción',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todas')),
              for (final accion in _acciones)
                DropdownMenuItem(
                  value: accion,
                  child: Text(accion, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (valor) => setState(() => _accion = valor ?? ''),
          ),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.search_rounded, size: 17),
          label: const Text('Buscar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => _buscar(controller),
        ),
        TextButton(
          onPressed: () {
            _usuarioCtrl.clear();
            setState(() {
              _desde = null;
              _hasta = null;
              _entidad = '';
              _accion = '';
            });
            controller.limpiarFiltros();
          },
          child: const Text('Limpiar filtros'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh_rounded, size: 15),
          label: const Text('Actualizar', style: TextStyle(fontSize: 13)),
          onPressed: () => controller.recargar(),
        ),
        if (puedePurgar)
          PopupMenuButton<String>(
            tooltip: 'Limpiar registros',
            icon: const Icon(Icons.delete_sweep_outlined),
            onSelected: (valor) => _purgar(controller, valor),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: '90',
                child: Text('Eliminar anteriores a 90 días'),
              ),
              PopupMenuItem(
                value: '365',
                child: Text('Eliminar anteriores a 1 año'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'todo',
                child: Text(
                  'Vaciar TODA la auditoría',
                  style: TextStyle(color: AppColors.negativeRed),
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _buscar(AuditoriaController controller) {
    controller.buscar(
      usuario: _usuarioCtrl.text,
      desde: _desde,
      hasta: _hasta,
      entidad: _entidad,
      accion: _accion,
    );
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final actual = esDesde ? _desde : _hasta;
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
      } else {
        _hasta = elegida;
      }
    });
  }

  Future<void> _purgar(AuditoriaController controller, String valor) async {
    final fecha = valor == 'todo'
        ? null
        : DateTime.now().subtract(Duration(days: int.parse(valor)));

    final confirmado = await confirmarAccion(
      context,
      titulo: 'Limpiar auditoría',
      mensaje: fecha == null
          ? 'Se eliminarán TODOS los registros de auditoría.'
          : 'Se eliminarán los registros anteriores a ${_fechaTexto(fecha)}.',
      nota:
          'No se puede deshacer y la propia limpieza quedará registrada en '
          'la auditoría (con tu cuenta y tu IP).',
      textoConfirmar: 'Eliminar',
      colorConfirmar: AppColors.negativeRed,
    );
    if (!confirmado || !mounted) return;

    try {
      if (fecha == null) {
        await controller.vaciar();
      } else {
        await controller.limpiarAntesDe(fecha);
      }
      if (mounted) {
        await alertaExito(
          context,
          titulo: 'Auditoría limpiada',
          mensaje: 'Los registros seleccionados ya no existen.',
        );
      }
    } on Failure catch (failure) {
      if (mounted) await alertaError(context, mensaje: failure.message);
    }
  }

  // --- Formateo --------------------------------------------------------------

  /// `yyyy-MM-ddTHH:mm:ssZ` → `dd/MM HH:mm` en hora local.
  static String _fechaCorta(Recurso recurso) {
    final fecha = DateTime.tryParse(recurso.texto('fecha', vacio: ''));
    if (fecha == null) return '—';
    final local = fecha.toLocal();
    return '${_fechaTexto(local)} ${_dos(local.hour)}:${_dos(local.minute)}';
  }

  static String _fechaTexto(DateTime fecha) =>
      '${_dos(fecha.day)}/${_dos(fecha.month)}/${fecha.year}';

  static String _dos(int valor) => valor.toString().padLeft(2, '0');

  /// `usuarios` → `usuarios #27` cuando hay id.
  static String _entidadConId(Recurso recurso) {
    final entidad = recurso.texto('entidad', vacio: '—');
    final id = recurso['entidadId'];
    if (id == null) return entidad;
    return '$entidad #$id';
  }
}
