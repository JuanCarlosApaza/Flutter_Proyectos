import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/confirmar_eliminacion.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import 'buscador_tabla.dart';
import 'opciones_formulario.dart';
import 'recurso_form.dart';
import 'recurso_tabla.dart';
import 'vistas_estado.dart';

/// Filtro de estado mostrado como chip bajo el `PageHeader`.
final class FiltroEstado {
  const FiltroEstado(this.valor, this.etiqueta);

  /// `null` equivale al chip "Todos".
  final String? valor;
  final String etiqueta;
}

/// Contenido estándar de un módulo: los 4 estados + `PageHeader` + filtros
/// + tabla/tarjetas + paginación + formularios en bottom sheet.
///
/// Es el corazón del patrón de pantalla de la guía; cada módulo solo aporta
/// sus columnas, sus campos y su controller.
class RecursoContenido extends StatefulWidget {
  const RecursoContenido({
    super.key,
    required this.controller,
    required this.tituloSeccion,
    this.etiquetaNuevo,
    this.accionesCabecera,
    required this.entidad,
    required this.columnas,
    required this.campos,
    this.pestanas,
    this.filtros,
    this.herramientasExtra,
    this.textoVacio,
    this.tituloFormulario,
    this.complementoCabecera,
    this.mensajeCreado,
    this.mensajeActualizado,
    this.mensajeEliminado,
    this.validar,
    this.accionesExtras,
    this.anchoAcciones,
    this.soloLectura = false,
  });

  final RecursoController controller;
  final String tituloSeccion;

  /// Etiqueta del botón de alta; `null` (o [soloLectura]) = sin botón.
  final String? etiquetaNuevo;

  /// Acciones extra en el cabezal, a la izquierda del botón de alta (p. ej.
  /// «Importar Excel»). Se pintan con el MISMO criterio que ese botón: si el
  /// rol no puede crear, no aparecen.
  final List<Widget>? accionesCabecera;

  /// Página de solo consulta (p. ej. Auditoría): sin altas, ediciones ni
  /// borrados; la ficha de detalle (👁) sigue disponible.
  final bool soloLectura;

  final String entidad;

  final List<ColumnaTabla> columnas;
  final List<CampoFormulario> campos;
  final List<FiltroEstado>? filtros;

  /// Widgets extra al final de la barra de herramientas, junto al buscador
  /// y a los chips de estado (p. ej. el desplegable «Marca» que filtra en
  /// el servidor con `?marcaId=`).
  final List<Widget>? herramientasExtra;

  /// Pestañas del formulario (ver `RecursoForm.pestanas`): `null` = un
  /// único bloque de campos, como siempre.
  final List<PestanaFormulario>? pestanas;

  /// Texto del estado vacío (por defecto `No hay {entidad}s`).
  final String? textoVacio;

  /// Título del bottom sheet (por defecto `Nuevo {entidad}`).
  final String? tituloFormulario;

  /// Widget extra justo debajo del `PageHeader` (p. ej. pestañas).
  final Widget? complementoCabecera;

  /// Mensajes de los SnackBar (por defecto se derivan de [entidad]).
  final String? mensajeCreado;
  final String? mensajeActualizado;
  final String? mensajeEliminado;

  /// Validación entre campos del formulario (ver `RecursoForm.validar`).
  final String? Function(Map<String, Object?> valores)? validar;

  /// Botones extra por fila (p. ej. «Restablecer contraseña»), tal como los
  /// usa `RecursoTabla`.
  final List<Widget> Function(Recurso)? accionesExtras;

  /// Ancho de la columna de acciones (suma los [accionesExtras]).
  final double? anchoAcciones;

  @override
  State<RecursoContenido> createState() => _RecursoContenidoState();
}

class _RecursoContenidoState extends State<RecursoContenido>
    with PaginationMixin<RecursoContenido> {
  /// Texto del buscador de la tabla (se manda al servidor con debounce).
  String _busqueda = '';

  /// Controlador del campo de búsqueda: permite limpiarlo desde los
  /// estados vacíos (el `TextField` no se entera solo).
  final TextEditingController _campoBusqueda = TextEditingController();

  /// Peticiones de búsqueda pendientes: solo se lanza la última.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _cargarSiHaceFalta();
  }

  @override
  void didUpdateWidget(covariant RecursoContenido viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.controller != widget.controller) {
      pagina = 0;
      _busqueda = '';
      _campoBusqueda.clear();
      _cargarSiHaceFalta();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _campoBusqueda.dispose();
    super.dispose();
  }

  void _cargarSiHaceFalta() {
    if (widget.controller.paginaCargada) return;
    // Se carga tras el primer frame para no notificar durante el build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.cargarPagina(porPagina: porPagina);
    });
  }

  Future<void> _recargar() async {
    setState(resetPage);
    await widget.controller.recargar();
  }

  Future<void> _cambiarFiltro(String? valor) async {
    setState(resetPage);
    widget.controller.filtroEstado = valor;
    await widget.controller.cargarPagina(numero: 0, porPagina: porPagina);
  }

  /// Manda la búsqueda al servidor (con ~300 ms de debounce) y vuelve a la
  /// página 1: el filtrado ocurre en la API sobre TODOS los registros.
  void _buscar(String valor) {
    setState(() {
      _busqueda = valor;
      resetPage();
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      widget.controller.busqueda = valor.trim().isEmpty ? null : valor.trim();
      await widget.controller.cargarPagina(numero: 0, porPagina: porPagina);
    });
  }

  /// Borra el texto del campo y la búsqueda en el servidor.
  void _limpiarBusqueda() {
    _campoBusqueda.clear();
    _buscar('');
  }

  // --- Formularios ---------------------------------------------------------

  Future<void> _abrirFormulario({Recurso? existente}) async {
    // Doble red de seguridad: el botón ya sale oculto sin permiso.
    if (existente == null ? !_puede('crear') : !_puede('editar')) return;
    final esEdicion = existente != null;
    // Los campos `soloEnCreacion` (p. ej. la contraseña) no aparecen al
    // editar: los cambios de credenciales tienen su diálogo dedicado.
    final campos = [
      for (final campo in widget.campos)
        if (!esEdicion || !campo.soloEnCreacion) campo,
    ];
    // Al crear, cada campo opción arranca con su ajuste `defecto.<ent>.<campo>`
    // (vacío = sin valor por defecto). Al editar manda lo del registro.
    final valoresIniciales =
        existente?.datos ??
        defectosDeAlta(context, entidad: widget.entidad, campos: campos);
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RecursoForm(
        titulo: esEdicion
            ? 'Editar ${widget.entidad}'
            : (widget.tituloFormulario ?? 'Nuevo ${widget.entidad}'),
        campos: campos,
        valores: valoresIniciales,
        esEdicion: esEdicion,
        etiquetaGuardar: esEdicion ? 'Actualizar' : 'Crear',
        pestanas: widget.pestanas,
        validar: widget.validar,
        onSubmit: (body) async {
          if (esEdicion) {
            await widget.controller.actualizar(existente.id, {
              ...body,
              // Guarda optimista de productos: se devuelve la `version` que
              // se leyó al abrir el formulario; si otra persona editó el
              // registro, la API responde 409 en vez de pisar el cambio.
              // Los registros sin `version` (resto de recursos) no la envían.
              if (existente.numero('version') != null)
                'versionLeida': existente.numero('version')!.toInt(),
            });
          } else {
            await widget.controller.crear(body);
          }
        },
      ),
    );

    if (guardado == true && mounted) {
      await alertaExito(
        context,
        titulo: esEdicion ? 'Actualizado' : 'Creado',
        mensaje: esEdicion
            ? (widget.mensajeActualizado ??
                  '${_mayuscula(widget.entidad)} actualizado')
            : (widget.mensajeCreado ?? '${_mayuscula(widget.entidad)} creado'),
      );
    }
  }

  Future<void> _verDetalle(Recurso item) async {
    // Misma hoja que la edición, pero en modo solo lectura: no toca el
    // controller ni envía nada a la API.
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RecursoForm(
        // "Detalle: Gaseosa Cola 2 L" (evita "Detalle del categoría").
        titulo: 'Detalle: ${widget.columnas.first.valor(item)}',
        campos: [
          for (final campo in widget.campos)
            if (!campo.soloEnCreacion) campo,
        ],
        valores: item.datos,
        pestanas: widget.pestanas,
        soloLectura: true,
      ),
    );
  }

  Future<void> _eliminar(Recurso item) async {
    if (!_puede('eliminar')) return;
    await confirmarEliminacion(
      context: context,
      titulo: _mayuscula(widget.entidad),
      descripcion: '¿Ocultar "${widget.columnas.first.valor(item)}"?',
      onConfirmar: () async {
        try {
          await widget.controller.eliminar(item.id);
          if (mounted) {
            await alertaExito(
              context,
              titulo: 'Oculto',
              mensaje:
                  widget.mensajeEliminado ??
                  '${_mayuscula(widget.entidad)} ocultado',
            );
          }
        } catch (_) {
          if (mounted) {
            await alertaError(
              context,
              mensaje: 'No se pudo ocultar el registro',
            );
          }
        }
      },
    );
  }

  static String _mayuscula(String texto) =>
      texto.isEmpty ? texto : texto[0].toUpperCase() + texto.substring(1);

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _contenido(),
    );
  }

  Widget _contenido() {
    final controller = widget.controller;

    // Estado 2: error + Reintentar.
    if (controller.state == LoadState.error) {
      return VistaError(
        mensaje: controller.errorMessage ?? 'Error desconocido',
        onReintentar: _recargar,
      );
    }

    // Estado 1: cargando solo cuando aún no hay nada que enseñar. Con la
    // página ya cargada, la recarga en curso (búsqueda, filtro o paginación)
    // NO se sustituye por el spinner: desmontaría el buscador y el foco
    // saltaría fuera del campo con cada tecla, obligando a volver a hacer
    // click para seguir escribiendo. La tabla anterior sigue en pantalla
    // hasta que llegan los nuevos resultados (igual que en el catálogo).
    if (!controller.paginaCargada) return const VistaCargando();

    // Los registros ya llegan paginados y filtrados del servidor: aquí no
    // se corta ni se vuelve a buscar nada en cliente.
    final items = controller.paginaItems;
    final hayBusqueda = _busqueda.trim().isNotEmpty;

    final puedeCrear = _puede('crear');
    final puedeEditar = _puede('editar');
    final puedeEliminar = _puede('eliminar');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: widget.tituloSeccion,
          // Total real del servidor (con filtros y búsqueda aplicados).
          count: controller.total,
          acciones: puedeCrear && !widget.soloLectura
              ? widget.accionesCabecera
              : null,
          buttonLabel:
              puedeCrear && !widget.soloLectura && widget.etiquetaNuevo != null
              ? widget.etiquetaNuevo
              : null,
          onButtonPressed:
              puedeCrear && !widget.soloLectura && widget.etiquetaNuevo != null
              ? () => _abrirFormulario()
              : null,
        ),
        const SizedBox(height: 20),
        if (widget.complementoCabecera != null) ...[
          widget.complementoCabecera!,
          const SizedBox(height: 16),
        ],
        // Buscador + chips de filtro: van SIEMPRE, como en el catálogo. Antes
        // el buscador aparecía y desaparecía con los resultados y, al
        // desmontarse, perdía el foco y había que volver a hacer click para
        // seguir escribiendo.
        _herramientas(controller),
        const SizedBox(height: 16),
        // Estado 3: vacío (sin registros, sin coincidencias del filtro o
        // sin resultados para la búsqueda).
        if (items.isEmpty)
          hayBusqueda
              ? VistaSinResultados(
                  busqueda: _busqueda.trim(),
                  onLimpiar: _limpiarBusqueda,
                )
              : controller.filtroEstado == null
              ? VistaVacia(
                  texto: widget.textoVacio ?? 'No hay ${widget.entidad}s',
                )
              : VistaVacia(
                  texto:
                      'No hay ${widget.entidad}s con ese estado. '
                      'Toca "Todos" para verlos todos.',
                )
        else ...[
          // Estado 4: con datos (los botones de fila salen solo si el rol
          // del usuario tiene la acción correspondiente).
          RecursoTabla(
            columnas: widget.columnas,
            items: items,
            onVer: _verDetalle,
            onEditar: !widget.soloLectura && puedeEditar
                ? (item) => _abrirFormulario(existente: item)
                : null,
            onEliminar: !widget.soloLectura && puedeEliminar ? _eliminar : null,
            accionesExtras: widget.accionesExtras,
            anchoAcciones: widget.anchoAcciones,
          ),
          buildPaginationTotal(
            controller.total,
            paginaActual: controller.pagina,
          ),
        ],
      ],
    );
  }

  /// La página pedida la decide el servidor: el índice del controlador y el
  /// del mixin se actualizan juntos.
  @override
  void goToPage(int destino) {
    setState(() => pagina = destino);
    widget.controller.cargarPagina(numero: destino, porPagina: porPagina);
  }

  /// Módulo de permisos del recurso gestionado (`null` = sin correspondencia
  /// conocida: la pantalla no se restringe).
  String? get _modulo => switch (widget.controller.recurso) {
    'productos' => Modulos.productos,
    'clientes' => Modulos.clientes,
    'proveedores' => Modulos.proveedores,
    'empleados' => Modulos.empleados,
    'usuarios' => Modulos.usuarios,
    'categorias' || 'presentaciones' || 'colores' => Modulos.categorias,
    'ordenes' || 'facturas' => Modulos.ventas,
    'cotizaciones' => Modulos.cotizaciones,
    'auditoria' => Modulos.auditoria,
    'unidades' => Modulos.unidades,
    _ => null,
  };

  /// ¿Puede la sesión actual hacer [accion] en el módulo del recurso?
  bool _puede(String accion) {
    final modulo = _modulo;
    if (modulo == null) return true;
    return SesionScope.de(context)?.puede(modulo, accion) ?? true;
  }

  /// Fila de herramientas de la tabla: buscador + chips de estado. Va en un
  /// `Wrap` para que en móvil salte de línea en vez de desbordar.
  ///
  /// El buscador va siempre (como en el catálogo): si dependiera de los
  /// resultados se desmontaría al no encontrar nada y perdería el foco.
  Widget _herramientas(RecursoController controller) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BuscadorTabla(
          // La clave vacía el campo si la pantalla cambia de controlador.
          key: ValueKey(widget.controller),
          controlador: _campoBusqueda,
          onChanged: _buscar,
          textoAyuda: 'Buscar ${widget.entidad}…',
        ),
        if (widget.filtros != null) ...[
          _chip(controller, const FiltroEstado(null, 'Todos')),
          for (final filtro in widget.filtros!) _chip(controller, filtro),
        ],
        ...?widget.herramientasExtra,
      ],
    );
  }

  Widget _chip(RecursoController controller, FiltroEstado filtro) {
    final seleccionado = controller.filtroEstado == filtro.valor;
    return FilterChip(
      label: Text(filtro.etiqueta),
      selected: seleccionado,
      onSelected: (_) => _cambiarFiltro(filtro.valor),
      selectedColor: AppColors.brandGreen,
      checkmarkColor: Colors.white,
      backgroundColor: AppColors.cardBg,
      side: const BorderSide(color: AppColors.cardBorder),
      labelStyle: TextStyle(
        color: seleccionado ? Colors.white : AppColors.textSecondary,
        fontWeight: seleccionado ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
      ),
    );
  }
}
