import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/alta_persona.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import '../widgets/restablecer_contrasena.dart';
import '../widgets/roles_contenido.dart';
import 'recurso_page.dart';
import 'utilidades_pagina.dart';

/// Módulo de usuarios de acceso al sistema.
///
/// Dos pestañas: la lista de usuarios (CRUD genérico) y la gestión de
/// **roles y permisos** (matriz `módulo × acción`), que es de donde sale el
/// rol que se asigna en la ficha de cada usuario.
class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  /// 0 = lista de usuarios, 1 = roles y permisos.
  int _pestana = 0;

  @override
  void initState() {
    super.initState();
    // Empleados (combo de la ficha) y roles (combo de rol + pestaña Roles)
    // se precargan tras el primer frame (la utilidad difiere la carga).
    precargarDespuesDelPrimerFrame(context, [
      context.read<EmpleadosController>(),
      context.read<RolesController>(),
    ]);
  }

  /// Selector de pestaña compartido por las dos vistas.
  Widget _selector() => SegmentedButton<int>(
    segments: const [
      ButtonSegment(
        value: 0,
        label: Text('Usuarios'),
        icon: Icon(Icons.manage_accounts_outlined, size: 18),
      ),
      ButtonSegment(
        value: 1,
        label: Text('Roles'),
        icon: Icon(Icons.security_outlined, size: 18),
      ),
    ],
    selected: {_pestana},
    onSelectionChanged: (seleccion) =>
        setState(() => _pestana = seleccion.first),
  );

  /// Abre el diálogo de restablecimiento y avisa al guardarse.
  Future<void> _restablecer(Recurso recurso) async {
    final usuarios = context.read<UsuariosController>();
    final guardado = await mostrarRestablecerContrasena(
      context,
      usuarios: usuarios,
      usuario: recurso,
    );
    if (guardado == true && mounted) {
      await alertaExito(
        context,
        titulo: 'Contraseña actualizada',
        mensaje:
            'La contraseña de ${recurso.texto('nombreUsuario')} ha sido '
            'reemplazada.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final empleados = context.read<EmpleadosController>();
    final roles = context.read<RolesController>();
    final puedeEditar =
        SesionScope.de(context)?.puede(Modulos.usuarios, Acciones.editar) ??
        true;

    if (_pestana == 1) {
      return ResponsiveLayout(
        selectedNav: widget.selectedNav,
        onNavSelect: widget.onNavSelect,
        title: 'Usuarios',
        // Gesto de actualizar: recarga la lista de roles.
        onRefresh: roles.recargar,
        contentBuilder: (context, constraints) =>
            RolesContenido(cabecera: _selector()),
      );
    }

    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Usuarios',
      controller: context.read<UsuariosController>(),
      tituloSeccion: 'Gestión de Usuarios',
      etiquetaNuevo: 'Nuevo Usuario',
      entidad: 'usuario',
      textoVacio: 'No hay usuarios del sistema',
      complementoCabecera: _selector(),
      // Icono de llave por fila: restablecer la contraseña exige la clave
      // del admin (lo verifica el backend); solo con permiso `usuarios.editar`.
      accionesExtras: puedeEditar
          ? (recurso) => [
              IconButton(
                tooltip: 'Restablecer contraseña',
                icon: const Icon(
                  Icons.key_rounded,
                  size: 20,
                  color: AppColors.brandGreen,
                ),
                onPressed: () => _restablecer(recurso),
              ),
            ]
          : null,
      anchoAcciones: 144,
      filtros: const [
        FiltroEstado('ACTIVO', 'Activos'),
        FiltroEstado('INACTIVO', 'Inactivos'),
        FiltroEstado('BLOQUEADO', 'Bloqueados'),
      ],
      columnas: [
        const ColumnaTabla(
          clave: 'nombreUsuario',
          etiqueta: 'Usuario',
          flex: 3,
        ),
        const ColumnaTabla(clave: 'nivelUsuario', etiqueta: 'Rol', flex: 2),
        ColumnaTabla(
          clave: 'empleadoId',
          etiqueta: 'Empleado',
          flex: 4,
          formato: (r) => nombreDe(empleados.items, r['empleadoId']),
        ),
        const ColumnaTabla(
          clave: 'estado',
          etiqueta: 'Estado',
          flex: 2,
          chip: true,
        ),
      ],
      campos: [
        const CampoFormulario(
          clave: 'nombreUsuario',
          etiqueta: 'Nombre de usuario *',
          obligatorio: true,
          minCaracteres: 4,
          maxCaracteres: 50,
          validador: usuarioValido,
          auxiliar: 'De 4 a 50 caracteres: letras, números, punto o guion bajo',
        ),
        const CampoFormulario(
          clave: 'contrasena',
          etiqueta: 'Contraseña',
          tipo: TipoCampo.clave,
          obligatorioSoloCreacion: true,
          // Solo en el alta: al editar la contraseña se cambia con el
          // botón de llave de la fila (pide la clave del admin).
          soloEnCreacion: true,
          minCaracteres: 8,
          maxCaracteres: 72,
          auxiliar: 'Mínimo 8 caracteres · se guarda como hash bcrypt',
        ),
        CampoFormulario(
          clave: 'rolId',
          etiqueta: 'Rol *',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          opcionesDinamicas: () => opcionesDe(roles.items),
          auxiliar:
              'Los roles y sus permisos se gestionan en la pestaña «Roles»',
        ),
        CampoFormulario(
          clave: 'empleadoId',
          etiqueta: 'Empleado vinculado',
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(empleados.items),
          // Crear el empleado con toda su ficha sin salir del formulario:
          // el alta trae su propio diálogo (ver `alta_persona.dart`).
          etiquetaCrear: 'Nuevo empleado',
          onAlta: () async {
            final creado = await altaEmpleado(context, empleados: empleados);
            return creado == null ? null : '${creado.id}';
          },
        ),
        const CampoFormulario(
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
