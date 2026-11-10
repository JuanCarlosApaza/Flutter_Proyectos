import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/errors/failure.dart';
import '../../../core/permisos.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/alertas.dart';
import '../../../core/widgets/responsive_layout.dart' show PageHeader;
import '../../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import 'vistas_estado.dart';

/// Contenido de la pestaña «Roles» de Usuarios: listado de roles con sus
/// permisos y editor de la matriz `módulo × acción`.
///
/// Va dentro de un `ResponsiveLayout` (lo hace `UsuariosPage`); [cabecera]
/// es el selector de pestañas compartido con la lista de usuarios.
class RolesContenido extends StatefulWidget {
  const RolesContenido({super.key, required this.cabecera});

  final Widget cabecera;

  @override
  State<RolesContenido> createState() => _RolesContenidoState();
}

class _RolesContenidoState extends State<RolesContenido> {
  @override
  Widget build(BuildContext context) {
    final roles = context.watch<RolesController>();
    final sesion = SesionScope.de(context);
    // Sin sesión (pantalla aislada en un test) se muestra todo, como en el
    // resto de módulos: la API es quien acaba exigiendo el permiso.
    final puedeEditar =
        sesion?.puede(Modulos.usuarios, Acciones.editar) ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Roles y permisos',
          count: roles.items.length,
          buttonLabel: puedeEditar ? 'Nuevo rol' : null,
          onButtonPressed: puedeEditar ? () => _abrirEditor(null) : null,
        ),
        const SizedBox(height: 12),
        widget.cabecera,
        const SizedBox(height: 16),
        const Text(
          'Cada rol decide a qué módulos entra la cuenta y qué puede hacer '
          'en ellos: leer, crear, editar o eliminar.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (roles.cargando)
          const VistaCargando()
        else if (roles.state == LoadState.error)
          VistaError(
            mensaje: roles.errorMessage ?? 'No se pudieron cargar los roles',
            onReintentar: roles.recargar,
          )
        else if (roles.vacio)
          const VistaVacia(texto: 'No hay roles definidos')
        else
          for (final rol in roles.items)
            _TarjetaRol(
              rol: rol,
              permisos: permisosDeRol(rol),
              soloLectura: roles.esSoloLectura(rol),
              esSistema: roles.esSistema(rol),
              puedeEditar: puedeEditar,
              onEditar: () => _abrirEditor(rol),
              onEliminar: () => _eliminar(rol),
            ),
      ],
    );
  }

  Future<void> _abrirEditor(Recurso? existente) async {
    final roles = context.read<RolesController>();
    final soloLectura = existente != null && roles.esSoloLectura(existente);

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditorRol(
        existente: existente,
        permisosIniciales: existente == null
            ? const <String>{}
            : permisosDeRol(existente).toSet(),
        soloLectura: soloLectura,
      ),
    );

    if (guardado == true && mounted) {
      await alertaExito(
        context,
        titulo: 'Guardado',
        mensaje: existente == null ? 'Rol creado' : 'Rol actualizado',
      );
    }
  }

  Future<void> _eliminar(Recurso rol) async {
    final roles = context.read<RolesController>();
    final confirmado = await confirmarAccion(
      context,
      titulo: 'Eliminar rol',
      mensaje: '¿Ocultar el rol "${rol.texto('nombre')}"?',
      nota:
          'No se borra la fila: pasa a estado ELIMINADO. No puede haber '
          'usuarios activos usándolo (los roles de sistema no se eliminan).',
      textoConfirmar: 'Eliminar',
      colorConfirmar: AppColors.negativeRed,
    );
    if (!confirmado || !mounted) return;

    try {
      await roles.eliminar(rol.id);
      if (mounted) {
        await alertaExito(
          context,
          titulo: 'Eliminado',
          mensaje: 'Rol ocultado',
        );
      }
    } on Failure catch (failure) {
      if (mounted) await alertaError(context, mensaje: failure.message);
    }
  }
}

/// Fila-card de un rol: nombre, chips y acciones (ver/editar/eliminar).
class _TarjetaRol extends StatelessWidget {
  const _TarjetaRol({
    required this.rol,
    required this.permisos,
    required this.soloLectura,
    required this.esSistema,
    required this.puedeEditar,
    required this.onEditar,
    required this.onEliminar,
  });

  final Recurso rol;
  final List<String> permisos;
  final bool soloLectura;
  final bool esSistema;
  final bool puedeEditar;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final nombre = rol.texto('nombre');
    final descripcion = rol.texto('descripcion', vacio: '');
    final estado = rol.texto('estado', vacio: 'ACTIVO');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.security_rounded,
                size: 20,
                color: AppColors.brandGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (soloLectura)
                const _Chip(texto: 'Acceso total', color: AppColors.brandGreen),
              if (esSistema && !soloLectura)
                const _Chip(texto: 'Sistema', color: AppColors.textSecondary),
              if (estado != 'ACTIVO')
                _Chip(texto: estado, color: AppColors.negativeRed),
              if (puedeEditar) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: soloLectura ? 'ADMIN no se puede editar' : 'Editar',
                  onPressed: soloLectura ? null : onEditar,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                if (!esSistema)
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onEliminar,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: AppColors.negativeRed,
                    ),
                  ),
              ],
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              descripcion,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${permisos.length} permiso(s): ${_resumen(permisos)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Módulos agrupados (`Productos: ver, crear` o `sin permisos`).
  static String _resumen(List<String> permisos) {
    if (permisos.isEmpty) return 'sin permisos';
    final porModulo = <String, List<String>>{};
    for (final permiso in permisos) {
      final partes = permiso.split('.');
      if (partes.length != 2) continue;
      porModulo.putIfAbsent(partes[0], () => []).add(partes[1]);
    }
    final nombres = [
      for (final modulo in Modulos.todos)
        if (porModulo[modulo] != null)
          '${_nombreModulo(modulo)}: ${porModulo[modulo]!.join(', ')}',
    ];
    return nombres.join(' · ');
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Editor de un rol (alta o edición): nombre, descripción y la matriz de
/// permisos `módulo × acción`.
class _EditorRol extends StatefulWidget {
  const _EditorRol({
    this.existente,
    required this.permisosIniciales,
    required this.soloLectura,
  });

  final Recurso? existente;
  final Set<String> permisosIniciales;

  /// `true` para el rol ADMIN: la API no lo deja modificar.
  final bool soloLectura;

  @override
  State<_EditorRol> createState() => _EditorRolState();
}

class _EditorRolState extends State<_EditorRol> {
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late final Set<String> _permisos;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(
      text: widget.existente?.texto('nombre', vacio: '') ?? '',
    );
    _descripcion = TextEditingController(
      text: widget.existente?.texto('descripcion', vacio: '') ?? '',
    );
    _permisos = {...widget.permisosIniciales};
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  void _alternar(String permiso, bool? valor) {
    setState(() {
      if (valor == true) {
        _permisos.add(permiso);
      } else {
        _permisos.remove(permiso);
      }
    });
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.length < 3) {
      setState(() => _error = 'El nombre debe tener al menos 3 caracteres.');
      return;
    }
    setState(() {
      _error = null;
      _guardando = true;
    });

    final body = <String, Object?>{
      'nombre': nombre,
      'descripcion': _descripcion.text.trim(),
      'permisos': [..._permisos]..sort(),
    };

    try {
      final roles = context.read<RolesController>();
      if (widget.existente == null) {
        await roles.crear(body);
      } else {
        await roles.actualizar(widget.existente!.id, body);
      }
      if (mounted) Navigator.pop(context, true);
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _error = failure.message;
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final soloLectura = widget.soloLectura;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.existente == null
                        ? 'Nuevo rol'
                        : 'Editar ${widget.existente!.texto('nombre')}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombre,
              enabled: !soloLectura && !_guardando,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: 'Nombre *',
                counterText: '',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descripcion,
              enabled: !soloLectura && !_guardando,
              maxLength: 255,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Permisos por módulo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (!soloLectura) ...[
                  TextButton(
                    onPressed: !_guardando
                        ? () => setState(() => _permisos.addAll(todosPermisos))
                        : null,
                    child: const Text('Todo'),
                  ),
                  TextButton(
                    onPressed: !_guardando
                        ? () => setState(_permisos.clear)
                        : null,
                    child: const Text('Nada'),
                  ),
                ],
              ],
            ),
            if (soloLectura)
              const Text(
                'El rol ADMIN tiene acceso total y no se puede modificar.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 8),
            _MatrizPermisos(
              permisos: _permisos,
              habilitada: !soloLectura && !_guardando,
              onAlternar: _alternar,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _guardando ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                if (!soloLectura) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _guardando ? null : _guardar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(widget.existente == null ? 'Crear' : 'Guardar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabla `módulo × acción` de checkboxes.
class _MatrizPermisos extends StatelessWidget {
  const _MatrizPermisos({
    required this.permisos,
    required this.habilitada,
    required this.onAlternar,
  });

  final Set<String> permisos;
  final bool habilitada;
  final void Function(String permiso, bool? valor) onAlternar;

  @override
  Widget build(BuildContext context) {
    const anchoAccion = 52.0;

    return Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Módulo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            for (final accion in Acciones.todas)
              SizedBox(
                width: anchoAccion,
                child: Text(
                  Acciones.etiqueta(accion),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const Divider(height: 16),
        for (final modulo in Modulos.todos)
          Row(
            children: [
              Expanded(
                child: Text(
                  _nombreModulo(modulo),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final accion in Acciones.todas)
                SizedBox(
                  width: anchoAccion,
                  child: Checkbox(
                    value: permisos.contains('$modulo.$accion'),
                    onChanged: habilitada
                        ? (valor) => onAlternar('$modulo.$accion', valor)
                        : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Nombre visible de un módulo (`catalogo` → `Catálogo`).
String _nombreModulo(String modulo) => switch (modulo) {
  Modulos.dashboard => 'Dashboard',
  Modulos.productos => 'Productos',
  Modulos.catalogo => 'Catálogo',
  Modulos.clientes => 'Clientes',
  Modulos.ventas => 'Ventas',
  Modulos.cotizaciones => 'Cotizaciones',
  Modulos.categorias => 'Categorías',
  Modulos.proveedores => 'Proveedores',
  Modulos.empleados => 'Empleados',
  Modulos.usuarios => 'Usuarios',
  Modulos.auditoria => 'Auditoría',
  Modulos.ajustes => 'Ajustes',
  _ => modulo,
};
