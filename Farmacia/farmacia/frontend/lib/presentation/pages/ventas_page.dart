import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/fechas.dart';
import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../core/widgets/confirmar_eliminacion.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/alta_persona.dart';
import '../widgets/buscador_tabla.dart';
import '../widgets/detalle_venta.dart';
import '../widgets/desplegable_buscable.dart';
import '../widgets/panel_qr_pago.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import '../widgets/vistas_estado.dart';
import 'utilidades_pagina.dart';

/// Módulo de ventas: pestañas de `Órdenes` y `Facturas` con sus reglas de
/// negocio (cambio de estado, emisión y anulación de facturas).
class VentasPage extends StatefulWidget {
  const VentasPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage>
    with PaginationMixin<VentasPage> {
  bool _verOrdenes = true;

  /// Texto del buscador de la tabla activa (se manda al servidor con
  /// debounce; cada pestaña guarda la suya en su controlador).
  String _busqueda = '';

  /// Controlador del campo de búsqueda (para vaciarlo al cambiar de
  /// pestaña o desde los estados sin resultados).
  final TextEditingController _campoBusqueda = TextEditingController();

  /// Peticiones de búsqueda pendientes: solo se lanza la última.
  Timer? _debounce;

  /// Ignora los clics de las acciones de fila mientras dura una operación
  /// (un doble clic podría emitir dos facturas o mandar dos PUT).
  bool _enviando = false;

  late OrdenesController _ordenes;
  late FacturasController _facturas;
  late ClientesController _clientes;
  late EmpleadosController _empleados;
  late ProductosController _productos;

  static const _estadosOrden = ['PENDIENTE', 'PAGADO', 'CANCELADO', 'DEVUELTO'];
  static const _estadosFactura = ['EMITIDA', 'ANULADA'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ordenes = context.read<OrdenesController>();
    _facturas = context.read<FacturasController>();
    _clientes = context.read<ClientesController>();
    _empleados = context.read<EmpleadosController>();
    _productos = context.read<ProductosController>();
  }

  @override
  void initState() {
    super.initState();
    // La página se carga sola: la pestaña activa pide su página al servidor
    // (offset + total reales) y los combos de los desplegables se piden en
    // el primer frame (solo los que falten). Los controladores `late` de
    // arriba se resuelven en `didChangeDependencies` (posterior a este
    // método), así que aquí se leen con `context.read`.
    precargarDespuesDelPrimerFrame(context, [
      context.read<OrdenesController>(),
      context.read<FacturasController>(),
      context.read<ClientesController>(),
      context.read<EmpleadosController>(),
      context.read<ProductosController>(),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activo = _verOrdenes ? _ordenes : _facturas;
      if (!activo.paginaCargada) activo.cargarPagina(porPagina: porPagina);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _campoBusqueda.dispose();
    super.dispose();
  }

  RecursoController get _activo => _verOrdenes ? _ordenes : _facturas;

  Future<void> _recargar() async {
    setState(resetPage);
    await _activo.recargar();
  }

  // --- Órdenes -------------------------------------------------------------

  /// Ejecuta [accion] ignorando los clics que lleguen mientras dura: los
  /// botones de fila no se deshabilitan, pero la operación nunca se envía
  /// dos veces (ni se apilan dos diálogos).
  Future<void> _unaVez(Future<void> Function() accion) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await accion();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _cambiarEstadoOrden(Recurso orden) => _unaVez(() async {
    final seleccion = await _pedirEstado(
      titulo: 'Cambiar estado de la orden',
      opciones: _estadosOrden,
      actual: orden.texto('estado'),
    );
    if (seleccion == null || !mounted) return;
    try {
      await _ordenes.cambiarEstado(orden.id, seleccion);
      if (mounted) _aviso('Orden #${orden.id} → $seleccion');
    } catch (error) {
      _error(error);
    }
  });

  /// Emite la factura de la orden cobrada. No pide importes: la factura
  /// copia subtotal, rebaja e IVA que la orden ya cobró.
  Future<void> _emitirFactura(Recurso orden) => _unaVez(() async {
    try {
      await _facturas.emitir(ordenId: orden.id);
      if (mounted) _aviso('Boleta emitida para la orden #${orden.id}');
    } catch (error) {
      _error(error);
    }
  });

  Future<void> _eliminarOrden(Recurso orden) => _unaVez(() async {
    await confirmarEliminacion(
      context: context,
      titulo: 'Orden',
      descripcion: '¿Ocultar la orden #${orden.id}?',
      onConfirmar: () async {
        try {
          await _ordenes.eliminar(orden.id);
          if (mounted) _aviso('Orden #${orden.id} ocultada');
        } catch (error) {
          _error(error);
        }
      },
    );
  });

  // --- Facturas -------------------------------------------------------------

  Future<void> _cambiarEstadoFactura(Recurso factura) => _unaVez(() async {
    final seleccion = await _pedirEstado(
      titulo: 'Cambiar estado de la factura',
      opciones: _estadosFactura,
      actual: factura.texto('estado'),
    );
    if (seleccion == null || !mounted) return;
    try {
      await _facturas.cambiarEstado(factura.id, seleccion);
      if (mounted) _aviso('Boleta #${factura.id} → $seleccion');
    } catch (error) {
      _error(error);
    }
  });

  Future<void> _eliminarFactura(Recurso factura) => _unaVez(() async {
    await confirmarEliminacion(
      context: context,
      titulo: 'Boleta',
      descripcion: '¿Ocultar la boleta #${factura.id}?',
      onConfirmar: () async {
        try {
          await _facturas.eliminar(factura.id);
          if (mounted) _aviso('Boleta #${factura.id} ocultada');
        } catch (error) {
          _error(error);
        }
      },
    );
  });

  // --- Detalle -------------------------------------------------------------

  /// Ficha completa de la orden: datos traducidos a nombres + sus líneas
  /// (la tabla solo muestra cliente, pago, total, fecha y estado).
  Future<void> _verOrden(Recurso orden) {
    return mostrarDetalleOrden(
      context,
      orden: orden,
      clientes: _clientes.items,
      empleados: _empleados.items,
      onCargarDetalles: _ordenes.detalles,
    );
  }

  /// Ficha de la factura: todos sus datos ya vienen en el listado; la
  /// orden asociada aporta el resumen de **cómo se pagó**.
  Future<void> _verFactura(Recurso factura) {
    final ordenId = factura['ordenId'];
    final orden = _ordenes.items
        .where((o) => ordenId != null && o.id == ordenId)
        .firstOrNull;
    return mostrarDetalleFactura(
      context,
      factura: factura,
      clientes: _clientes.items,
      empleados: _empleados.items,
      orden: orden,
    );
  }

  // --- Diálogos y mensajes -------------------------------------------------

  Future<String?> _pedirEstado({
    required String titulo,
    required List<String> opciones,
    required String actual,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        var elegido = actual;
        return StatefulBuilder(
          builder: (ctx, actualizar) => AlertDialog(
            title: Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final opcion in opciones)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      opcion,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    trailing: opcion == elegido
                        ? const Icon(
                            Icons.check_circle_outline,
                            color: AppColors.brandGreen,
                          )
                        : null,
                    onTap: () => actualizar(() => elegido = opcion),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, elegido),
                child: const Text(
                  'Aceptar',
                  style: TextStyle(color: AppColors.brandGreen),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _aviso(String mensaje) {
    alertaExito(context, titulo: 'Hecho', mensaje: mensaje);
  }

  void _error(Object error) {
    if (!mounted) return;
    alertaError(
      context,
      mensaje: error is Failure ? error.message : 'Error inesperado',
    );
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      title: 'Ventas',
      // Gesto de actualizar: recarga la pestaña activa (órdenes/facturas).
      onRefresh: _recargar,
      contentBuilder: (context, constraints) => ListenableBuilder(
        listenable: _activo,
        builder: (context, _) => _contenido(),
      ),
    );
  }

  Widget _contenido() {
    final controller = _activo;

    if (controller.state == LoadState.error) {
      return VistaError(
        mensaje: controller.errorMessage ?? 'Error desconocido',
        onReintentar: _recargar,
      );
    }
    // Solo el spinner a pantalla completa si todavía no hay nada cargado.
    // Después, la recarga de la búsqueda deja la columna montada (si no, el
    // input se desmonta con cada tecla y pierde el foco): la tabla anterior
    // sigue visible hasta que llegan los resultados nuevos.
    if (!controller.paginaCargada) return const VistaCargando();

    // Página paginada y filtrada del servidor (sin corte en cliente).
    final visibles = controller.paginaItems;
    final hayBusqueda = _busqueda.trim().isNotEmpty;
    final sesion = SesionScope.de(context);
    // El flujo completo de venta (orden, pago, factura) exige `ventas.crear`;
    // anular o borrar exige `ventas.eliminar` (se aplica en `_tabla`).
    final puedeCrear = sesion?.puede(Modulos.ventas, Acciones.crear) ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Gestión de Ventas',
          count: controller.total,
          buttonLabel: _verOrdenes && puedeCrear ? 'Nueva Orden' : null,
          onButtonPressed: _verOrdenes && puedeCrear
              ? () => _abrirNuevaOrden()
              : null,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Siempre montado, como en el catálogo: si apareciera y
            // desapareciera con los resultados perdería el foco al escribir.
            BuscadorTabla(
              controlador: _campoBusqueda,
              onChanged: _buscar,
              textoAyuda: _verOrdenes ? 'Buscar orden…' : 'Buscar factura…',
            ),
            _chip(
              etiqueta: 'Órdenes',
              seleccionado: _verOrdenes,
              onTap: () => _cambiarTab(true),
            ),
            _chip(
              etiqueta: 'Boletas',
              seleccionado: !_verOrdenes,
              onTap: () => _cambiarTab(false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              etiqueta: 'Todos',
              seleccionado: controller.filtroEstado == null,
              onTap: () => _filtrar(null),
            ),
            for (final estado in _verOrdenes ? _estadosOrden : _estadosFactura)
              _chip(
                etiqueta: estado,
                seleccionado: controller.filtroEstado == estado,
                onTap: () => _filtrar(estado),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (visibles.isEmpty)
          hayBusqueda
              ? VistaSinResultados(
                  busqueda: _busqueda.trim(),
                  onLimpiar: _limpiarBusqueda,
                )
              : VistaVacia(
                  texto: _verOrdenes
                      ? 'No hay órdenes registradas'
                      : 'No hay facturas',
                )
        else ...[
          _tabla(visibles),
          buildPaginationTotal(controller.total, paginaActual: controller.pagina),
        ],
      ],
    );
  }

  /// Cambia de pestaña: recupera la página/búsqueda que tenía la otra tabla
  /// y carga su página 0 si todavía no se ha pedido.
  void _cambiarTab(bool aOrdenes) {
    if (aOrdenes == _verOrdenes) return;
    final activo = aOrdenes ? _ordenes : _facturas;
    setState(() {
      _verOrdenes = aOrdenes;
      _busqueda = activo.busqueda ?? '';
      pagina = activo.pagina;
    });
    _campoBusqueda.text = _busqueda;
    if (!activo.paginaCargada) activo.cargarPagina(porPagina: porPagina);
  }

  /// Manda la búsqueda al servidor (con debounce) sobre la pestaña activa.
  void _buscar(String valor) {
    setState(() {
      _busqueda = valor;
      resetPage();
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final activo = _activo;
      activo.busqueda = valor.trim().isEmpty ? null : valor.trim();
      await activo.cargarPagina(numero: 0, porPagina: porPagina);
    });
  }

  void _limpiarBusqueda() {
    _campoBusqueda.clear();
    _buscar('');
  }

  Future<void> _filtrar(String? estado) async {
    setState(resetPage);
    _activo.filtroEstado = estado;
    await _activo.cargarPagina(numero: 0, porPagina: porPagina);
  }

  /// El servidor decide la página de la pestaña activa.
  @override
  void goToPage(int destino) {
    setState(() => pagina = destino);
    _activo.cargarPagina(numero: destino, porPagina: porPagina);
  }

  Widget _tabla(List<Recurso> visibles) {
    final sesion = SesionScope.de(context);
    final puedeCrear = sesion?.puede(Modulos.ventas, Acciones.crear) ?? true;
    final puedeEliminar =
        sesion?.puede(Modulos.ventas, Acciones.eliminar) ?? true;

    if (_verOrdenes) {
      // Botones visibles: ojo + (emitir factura y cambiar estado si puede
      // crear) + (borrar si puede eliminar).
      final botones = 1 + (puedeCrear ? 2 : 0) + (puedeEliminar ? 1 : 0);
      return RecursoTabla(
        columnas: _columnasOrden,
        items: visibles,
        onVer: _verOrden,
        onEditar: puedeCrear ? _cambiarEstadoOrden : null,
        onEliminar: puedeEliminar ? _eliminarOrden : null,
        anchoAcciones: 34.0 * botones + 12,
        accionesExtras: puedeCrear
            ? (orden) => [
                if (orden.texto('estado') == 'PAGADO')
                  botonAccion(
                    icono: Icons.receipt_long_outlined,
                    color: AppColors.brandGreen,
                    onTap: () => _emitirFactura(orden),
                  ),
              ]
            : null,
      );
    }

    return RecursoTabla(
      columnas: _columnasFactura,
      items: visibles,
      onVer: _verFactura,
      // Anular una factura emita es una eliminación lógica.
      onEditar: puedeEliminar ? _cambiarEstadoFactura : null,
      onEliminar: puedeEliminar ? _eliminarFactura : null,
    );
  }

  /// Resumen del desglose de pagos de una orden: `Efectivo + Yape`...
  static String _resumenPagos(Recurso r) {
    final pagos = r['pagos'];
    if (pagos is! List || pagos.isEmpty) return '—';
    String etiqueta(Object? metodo) {
      for (final tipo in tiposPago) {
        if (tipo.valor == metodo) return tipo.etiqueta;
      }
      return metodo?.toString() ?? '?';
    }

    return pagos
        .map((p) => etiqueta(p is Map ? p['metodoPago'] : null))
        .join(' + ');
  }

  static final List<ColumnaTabla> _columnasOrden = [
    ColumnaTabla(
      clave: 'nombreCliente',
      etiqueta: 'Cliente',
      flex: 3,
      formato: (r) => r.texto('nombreCliente', vacio: 'Cliente no registrado'),
    ),
    ColumnaTabla(
      clave: 'id',
      etiqueta: 'Orden',
      flex: 1,
      formato: (r) => '#${r.id}',
    ),
    ColumnaTabla(
      clave: 'pagos',
      etiqueta: 'Pago',
      flex: 2,
      formato: _resumenPagos,
    ),
    ColumnaTabla(
      clave: 'total',
      etiqueta: 'Total',
      flex: 2,
      formato: (r) => 'Bs ${(r.numero('total') ?? 0).toStringAsFixed(2)}',
    ),
    ColumnaTabla(
      clave: 'fechaOrden',
      etiqueta: 'Fecha',
      flex: 2,
      // La API devuelve UTC: se muestra el día en hora local (igual que la
      // ficha de detalle).
      formato: (r) => fechaCortaLocal(r.texto('fechaOrden', vacio: '')),
    ),
    const ColumnaTabla(
      clave: 'estado',
      etiqueta: 'Estado',
      flex: 2,
      chip: true,
    ),
  ];

  /// Columnas de la pestaña Facturas: las de importes más **cómo se pagó**
  /// (resuelto desde la orden asociada, que ya está cargada).
  List<ColumnaTabla> get _columnasFactura => [
    ColumnaTabla(
      clave: 'id',
      etiqueta: 'Boleta',
      flex: 2,
      formato: (r) => '#${r.id}',
    ),
    ColumnaTabla(
      clave: 'ordenId',
      etiqueta: 'Orden',
      flex: 2,
      formato: (r) => r['ordenId'] == null ? '—' : '#${r['ordenId']}',
    ),
    ColumnaTabla(
      clave: 'subtotal',
      etiqueta: 'Subtotal',
      flex: 2,
      formato: (r) => 'Bs ${(r.numero('subtotal') ?? 0).toStringAsFixed(2)}',
    ),
    ColumnaTabla(
      clave: 'rebaja',
      etiqueta: 'Rebaja',
      flex: 2,
      formato: (r) => 'Bs ${(r.numero('rebaja') ?? 0).toStringAsFixed(2)}',
    ),
    ColumnaTabla(
      clave: 'iva',
      etiqueta: 'IVA',
      flex: 2,
      formato: (r) => 'Bs ${(r.numero('iva') ?? 0).toStringAsFixed(2)}',
    ),
    ColumnaTabla(
      clave: 'total',
      etiqueta: 'Total',
      flex: 2,
      formato: (r) => 'Bs ${(r.numero('total') ?? 0).toStringAsFixed(2)}',
    ),
    ColumnaTabla(
      clave: 'pago',
      etiqueta: 'Pago',
      flex: 2,
      formato: (r) {
        final ordenId = r['ordenId'];
        final orden = _ordenes.items
            .where((o) => ordenId != null && o.id == ordenId)
            .firstOrNull;
        return orden == null ? '—' : _resumenPagos(orden);
      },
    ),
    const ColumnaTabla(
      clave: 'estado',
      etiqueta: 'Estado',
      flex: 2,
      chip: true,
    ),
  ];

  Widget _chip({
    required String etiqueta,
    required bool seleccionado,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(etiqueta),
      selected: seleccionado,
      onSelected: (_) => onTap(),
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

  // --- Nueva orden ---------------------------------------------------------

  Future<void> _abrirNuevaOrden() async {
    // Siempre frescos al abrir (no solo si están vacíos): un vendedor,
    // cliente o producto dado de alta en otra pantalla — o en otro
    // dispositivo — debe aparecer al instante en estos selectores.
    await _empleados.cargar();
    await _clientes.cargar();
    await _productos.cargar();
    if (!mounted) return;

    // Alta de cliente sin salir del formulario: solo si la cuenta puede
    // crear clientes (si no, el selector se queda con «Cliente ocasional»).
    final puedeCrearClientes =
        SesionScope.de(context)?.puede(Modulos.clientes, Acciones.crear) ??
        true;

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NuevaOrdenForm(
        clientes: _clientes.items,
        empleados: _empleados.items,
        productos: _productos.items,
        // Quien está en la sesión es el vendedor por defecto. Se lee aquí y
        // no dentro de la hoja: el modal queda montado fuera del
        // `SesionScope`, así que allí no habría sesión que leer.
        empleadoPorDefecto: SesionScope.de(context)?.usuario.empleadoId,
        onCrearCliente: puedeCrearClientes
            ? () => altaCliente(context, clientes: _clientes)
            : null,
        onSubmit: (body) => _ordenes.crear(body),
      ),
    );
    if (guardado == true && mounted) _aviso('Orden creada');
  }
}

// --- Formulario de nueva orden ---------------------------------------------

class _ItemOrden {
  int? productoId;
  int cantidad = 1;
}

/// Línea de pago de «Nueva Orden»: arranca con una sola y, si se reparte
/// la venta, se agrega una segunda (solo Efectivo / QR).
class _PagoNuevo {
  String metodoPago = 'EFECTIVO';
  double? monto;
}

class _NuevaOrdenForm extends StatefulWidget {
  const _NuevaOrdenForm({
    required this.clientes,
    required this.empleados,
    required this.productos,
    required this.onSubmit,
    this.empleadoPorDefecto,
    this.onCrearCliente,
  });

  final List<Recurso> clientes;
  final List<Recurso> empleados;
  final List<Recurso> productos;
  final Future<void> Function(Map<String, Object?> body) onSubmit;

  /// Empleado de la cuenta conectada: sale marcado en «Empleado» para que la
  /// venta se le asigne a quien la está haciendo (se puede cambiar).
  final int? empleadoPorDefecto;

  /// Da de alta un cliente con su ficha completa y lo devuelve: une su
  /// `Recurso` a la lista del selector para elegirlo en el acto, o devuelve
  /// `null` si se cancela el alta. `null` en el propio parámetro = la cuenta
  /// no puede crear clientes y el botón no aparece.
  final Future<Recurso?> Function()? onCrearCliente;

  @override
  State<_NuevaOrdenForm> createState() => _NuevaOrdenFormState();
}

class _NuevaOrdenFormState extends State<_NuevaOrdenForm> {
  final _formKey = GlobalKey<FormState>();
  final List<_ItemOrden> _items = [_ItemOrden()];
  String? _clienteId;
  String? _empleadoId;
  final List<_PagoNuevo> _pagos = [_PagoNuevo()];
  bool _enviando = false;

  /// Referencia (nº de operación) **una sola vez** para todo el cobro:
  /// viaja con los pagos QR (efectivo no tiene comprobante).
  String _referencia = '';

  /// Rebaja (descuento al cliente) y factura (agrega IVA 14.94 %): los
  /// pagos cuadran contra `(subtotal − rebaja) + IVA`. La rebaja solo se
  /// muestra si [_conRebaja].
  final _rebaja = TextEditingController(text: '0');
  bool _conRebaja = false;
  bool _factura = false;

  @override
  void dispose() {
    _rebaja.dispose();
    super.dispose();
  }

  /// Clientes del selector: la lista que trae el formulario más los que se
  /// den de alta mientras está abierto (el controlador recarga la suya al
  /// crear, pero esta hoja ya recibió la suya al abrirse). Al cambiar de
  /// identidad se invalida la caché de opciones.
  late List<Recurso> _clientes;

  /// Empleados del desplegable de vendedor: solo los cuyo rol permite
  /// crear ventas, más el de la sesión por si su rol no da para vender
  /// (así el vendedor por defecto nunca queda fuera de sus propias
  /// opciones). Se memoiza porque `initState` y `build` leen la misma
  /// lista.
  late final List<Recurso> _vendedores = vendedoresDe(
    widget.empleados,
    sesion: widget.empleadoPorDefecto,
  );

  @override
  void initState() {
    super.initState();
    _clientes = widget.clientes;
    // Vendedor por defecto, pero solo si está entre las opciones del select.
    // El resto del formulario queda igual y el usuario puede cambiarlo —o
    // volver a «— Sin asignar —»— antes de crear la orden.
    final defecto = widget.empleadoPorDefecto;
    if (defecto != null && _vendedores.any((e) => e.id == defecto)) {
      _empleadoId = '$defecto';
    }
  }

  bool _ajustesLeidos = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Justo después de `initState` y una sola vez: los ajustes guardados en
    // «Ajustes» mandan sobre los valores de fábrica (y sobre la cuenta de la
    // sesión); se pueden cambiar antes de crear la orden.
    if (_ajustesLeidos) return;
    _ajustesLeidos = true;
    _aplicarAjustes(AjustesScope.de(context));
  }

  void _aplicarAjustes(AjustesValores ajustes) {
    // Dos métodos posibles en el cobro (Efectivo / QR): el ajuste decide
    // con cuál arranca la única fila de pago.
    final tipoPago = ajustes.valor(Ajustes.tipoPagoPorDefecto);
    if (tipoPago == 'QR' || tipoPago == 'EFECTIVO') {
      _pagos.first.metodoPago = tipoPago;
    }

    final cliente = ajustes.valor(Ajustes.clientePorDefecto);
    if (cliente.isNotEmpty && _clientes.any((c) => '${c.id}' == cliente)) {
      _clienteId = cliente;
    }

    // Solo si ese empleado está entre los vendedores: uno dado de baja no
    // puede preseleccionarse (invariante del selector).
    final vendedor = int.tryParse(ajustes.valor(Ajustes.vendedorPorDefecto));
    if (vendedor != null && _vendedores.any((e) => e.id == vendedor)) {
      _empleadoId = '$vendedor';
    }
  }

  // Opciones de los desplegables, memorizadas por clave mientras la fuente no
  // cambie de identidad: `opcionesDe` recorre **y ordena** la lista entera,
  // y los tres desplegables se repintan con cada tecla del formulario.
  final Map<String, List<Opccion>> _cacheOpciones = {};
  final Map<String, Object> _origenOpciones = {};

  /// Opciones de [origen] con [inicial] por delante, construidas una sola vez
  /// por fuente.
  List<Opccion> _opciones(
    String clave,
    List<Recurso> origen,
    Opccion inicial, {
    bool conImagen = false,
  }) {
    if (!identical(_origenOpciones[clave], origen)) {
      _origenOpciones[clave] = origen;
      _cacheOpciones[clave] = [
        inicial,
        ...opcionesDe(origen, conImagen: conImagen),
      ];
    }
    return _cacheOpciones[clave]!;
  }

  double get _total {
    var suma = 0.0;
    for (final item in _items) {
      final producto = _productoDe(item.productoId);
      if (producto == null) continue;
      suma += (producto.numero('precioVenta') ?? 0) * item.cantidad;
    }
    return suma;
  }

  /// Rebaja escrita: entre 0 y el subtotal de los productos (0 si el
  /// interruptor de rebaja está apagado).
  double get _rebajaValor {
    if (!_conRebaja) return 0;
    final texto = _rebaja.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(texto) ?? 0;
    if (valor <= 0) return 0;
    final tope = _total;
    return double.parse((valor > tope ? tope : valor).toStringAsFixed(2));
  }

  /// IVA boliviano (14.94 %): solo si la venta es factura (espejo de
  /// `ivaDe` del backend).
  double get _ivaValor {
    final base = _total - _rebajaValor;
    if (!_factura || base <= 0) return 0;
    return double.parse((base * ivaBolivia).toStringAsFixed(2));
  }

  /// Total a pagar: lo que deben sumar los pagos.
  double get _totalPagar => _total - _rebajaValor + _ivaValor;

  /// Máximo que se puede rebajar con estos productos: la suma de los topes
  /// por línea (`precioRebaja`; sin tope, el precio completo), nunca por
  /// encima del precio de venta.
  double get _maxRebaja {
    var suma = 0.0;
    for (final item in _items) {
      final producto = _productoDe(item.productoId);
      if (producto == null) continue;
      final precio = producto.numero('precioVenta') ?? 0;
      final tope = producto.numero('precioRebaja');
      final unitario = tope == null || tope > precio ? precio : tope;
      suma += unitario * item.cantidad;
    }
    return double.parse(suma.toStringAsFixed(2));
  }

  Recurso? _productoDe(int? id) {
    if (id == null) return null;
    for (final producto in widget.productos) {
      if (producto.id == id) return producto;
    }
    return null;
  }

  /// Suma de los montos de pago escritos (redondeada a 2 decimales).
  double get _sumaPagos {
    var suma = 0.0;
    for (final pago in _pagos) {
      final monto = pago.monto;
      if (monto == null) continue;
      suma += double.parse(monto.toStringAsFixed(2));
    }
    return suma;
  }

  /// Sección de **método de pago** (lo principal al cobrar): tarjeta con
  /// acento de marca, una línea por método y el estado del reparto en una
  /// píldora de color (verde = cuadrado, naranja = falta).
  Widget _seccionPagos() {
    final falta = _totalPagar - _sumaPagos;
    final cuadrado = falta.abs() <= 0.009;
    final acento = cuadrado ? AppColors.brandGreen : AppColors.warningOrange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: acento, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: acento.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.payments_rounded,
                size: 18,
                color: AppColors.brandGreenDark,
              ),
              const SizedBox(width: 6),
              const Text(
                'Método de pago',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandGreenDark,
                ),
              ),
              const Spacer(),
              Text(
                'Bs ${_totalPagar.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandGreenDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Una sola referencia para todo el cobro, al inicio de la sección.
          TextField(
            maxLength: 100,
            enabled: !_enviando,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
            decoration: const InputDecoration(
              labelText: 'Referencia (nº de operación) — opcional',
              labelStyle: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              counterText: '',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (valor) => setState(() => _referencia = valor),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _pagos.length; i++) _lineaPago(i),
          // Con QR en el cobro, se muestra el QR de pago (contenido del
          // ajuste `qrPago`, editable desde Ajustes) para que se escanee.
          if (_pagos.any((pago) => pago.metodoPago == 'QR')) ...[
            const SizedBox(height: 6),
            Center(child: panelQrPago(context)),
          ],
          // Hasta dos pagos: el segundo arranca con el método contrario al
          // primero (efectivo → QR y al revés).
          if (_pagos.length == 1)
            TextButton.icon(
              onPressed: _enviando
                  ? null
                  : () => setState(() {
                      _pagos.add(
                        _PagoNuevo()
                          ..metodoPago =
                              _pagos.first.metodoPago == 'QR'
                                  ? 'EFECTIVO'
                                  : 'QR',
                      );
                    }),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Agregar pago',
                style: TextStyle(color: AppColors.brandGreen),
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: acento,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                cuadrado
                    ? '✓ Cuadrado · Bs ${_sumaPagos.toStringAsFixed(2)}'
                    : 'Falta Bs ${falta.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Línea de pago: método (solo Efectivo / QR) + monto, con quitar si ya
  /// hay dos filas. La referencia vive una sola vez arriba, no aquí.
  Widget _lineaPago(int indice) {
    final pago = _pagos[indice];
    OutlineInputBorder borde() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.cardBorder),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: DesplegableBuscable(
              initialValue: pago.metodoPago,
              opciones: metodosCobro,
              habilitado: !_enviando,
              decoracion: InputDecoration(
                labelText: 'Método',
                labelStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: borde(),
              ),
              onChanged: (valor) =>
                  setState(() => pago.metodoPago = valor ?? 'EFECTIVO'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: pago.monto?.toStringAsFixed(2),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
              ],
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Monto (Bs)',
                labelStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                border: borde(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              // La primera fila es la que cubre el total; la segunda es
              // opcional (vacío = ese método no participa).
              validator: (valor) {
                final texto = (valor ?? '').trim().replaceAll(',', '.');
                if (texto.isEmpty) return indice == 0 ? 'Monto' : null;
                final monto = double.tryParse(texto);
                if (monto == null || monto < 0) return 'Número';
                return null;
              },
              onChanged: (valor) => setState(() {
                pago.monto = double.tryParse(
                  valor.trim().replaceAll(',', '.'),
                );
              }),
            ),
          ),
          if (_pagos.length > 1) ...[
            const SizedBox(width: 4),
            botonAccion(
              icono: Icons.remove_circle_outline,
              color: AppColors.negativeRed,
              onTap: () => setState(() => _pagos.removeAt(indice)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // No se rebaja más de lo que los productos permiten.
    if (_rebajaValor > _maxRebaja) {
      await alertaError(
        context,
        titulo: 'Rebaja excedida',
        mensaje:
            'La rebaja (Bs ${_rebajaValor.toStringAsFixed(2)}) supera el '
            'máximo a rebajar (Bs ${_maxRebaja.toStringAsFixed(2)}).',
      );
      return;
    }
    // Todos los productos seleccionados deben existir.
    if (_items.any((item) => item.productoId == null)) {
      await alertaError(
        context,
        titulo: 'Orden incompleta',
        mensaje: 'Cada línea necesita un producto',
      );
      return;
    }

    // Dos métodos fijos (Efectivo y QR): lo que quede vacío o en cero no
    // viaja. La referencia (una sola, de la sección) se lleva el pago QR.
    final pagos = <Map<String, Object?>>[];
    for (final pago in _pagos) {
      final monto = pago.monto;
      if (monto == null || monto <= 0) continue;
      pagos.add({
        'metodoPago': pago.metodoPago,
        'monto': double.parse(monto.toStringAsFixed(2)),
        if (pago.metodoPago == 'QR' && _referencia.trim().isNotEmpty)
          'referencia': _referencia.trim(),
      });
    }

    final total = _totalPagar;
    if ((_sumaPagos - total).abs() > 0.009) {
      await alertaError(
        context,
        titulo: 'Pagos por repartir',
        mensaje:
            'Los pagos suman Bs ${_sumaPagos.toStringAsFixed(2)} pero el '
            'total a pagar es Bs ${total.toStringAsFixed(2)}.\n'
            'Ajusta los montos o agrega otro método de pago.',
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      await widget.onSubmit({
        if (_clienteId != null && _clienteId!.isNotEmpty)
          'clienteId': int.parse(_clienteId!),
        if (_clienteId != null && _clienteId!.isNotEmpty)
          'nombreCliente': _nombreDe(_clientes, _clienteId),
        if (_empleadoId != null && _empleadoId!.isNotEmpty)
          'empleadoId': int.parse(_empleadoId!),
        'rebaja': _rebajaValor,
        'factura': _factura,
        'pagos': pagos,
        'items': [
          for (final item in _items)
            {'productoId': item.productoId, 'cantidad': item.cantidad},
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      await alertaError(
        context,
        mensaje: error is Failure ? error.message : 'Error inesperado',
      );
    }
  }

  static String? _nombreDe(List<Recurso> items, String? id) {
    for (final item in items) {
      if ('${item.id}' == id) return nombreCompletoDe(item);
    }
    return null;
  }

  /// Da de alta un cliente desde el propio selector y devuelve su id para
  /// que el desplegable lo deje elegido en el acto. El diálogo con la ficha
  /// completa lo abre la página (`widget.onCrearCliente`, que sabe de
  /// controladores). El registro nuevo se suma a [_clientes] (el formulario
  /// ya recibió su lista al abrirse) y cambia la identidad de la fuente, con
  /// lo que se invalida la caché de opciones. Se reconstruye la lista sin
  /// duplicados por si la que recibió el formulario compartía memoria con la
  /// del controlador. `null` = alta cancelada.
  Future<String?> _crearCliente() async {
    final crear = widget.onCrearCliente;
    if (crear == null) return null;
    final creado = await crear();
    if (creado == null) return null;
    if (!mounted) return '${creado.id}';
    setState(() {
      _clientes = [
        for (final cliente in _clientes)
          if (cliente.id != creado.id) cliente,
        creado,
      ];
    });
    return '${creado.id}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nueva Orden',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              // Lo importante primero: quién compra y quién atiende, juntos.
              Row(
                children: [
                  Expanded(
                    child: _desplegable(
                      etiqueta: 'Cliente',
                      valor: _clienteId,
                      requerido: false,
                      opciones: _opciones(
                        'cliente',
                        _clientes,
                        const Opccion('', '— Cliente ocasional —'),
                      ),
                      onChanged: (valor) => setState(() => _clienteId = valor),
                      // Alta de cliente sin salir del formulario (si el rol).
                      etiquetaCrear: widget.onCrearCliente == null
                          ? null
                          : 'Nuevo cliente',
                      onAlta: widget.onCrearCliente == null
                          ? null
                          : _crearCliente,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _desplegable(
                      etiqueta: 'Vendedor',
                      valor: _empleadoId,
                      requerido: false,
                      opciones: _opciones(
                        'empleado',
                        // Solo vendedores (+ el de la sesión): `vendedoresDe`.
                        _vendedores,
                        const Opccion('', '— Sin asignar —'),
                      ),
                      onChanged: (valor) =>
                          setState(() => _empleadoId = valor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Productos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _items.length; i++) _lineaItem(i),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => setState(() => _items.add(_ItemOrden())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Agregar producto',
                  style: TextStyle(color: AppColors.brandGreen),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total estimado',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    'Bs ${_total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Rebaja y factura como interruptores; el monto de la rebaja
              // solo aparece si se enciende.
              Row(
                children: [
                  Switch(
                    value: _conRebaja,
                    onChanged: _enviando
                        ? null
                        : (valor) => setState(() => _conRebaja = valor),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const Text(
                    'Rebaja',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Checkbox(
                    value: _factura,
                    onChanged: _enviando
                        ? null
                        : (valor) =>
                              setState(() => _factura = valor ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  Flexible(
                    child: Text(
                      'Boleta (IVA 14.94%)',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (_conRebaja)
                TextField(
                  controller: _rebaja,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                    ),
                  ],
                  enabled: !_enviando,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Monto de la rebaja (Bs)',
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    // El tope calculado de los productos, junto al monto.
                    helperText:
                        'Máximo a rebajar: Bs ${_maxRebaja.toStringAsFixed(2)}',
                    errorText: _rebajaValor > _maxRebaja
                        ? 'Máx. Bs ${_maxRebaja.toStringAsFixed(2)}'
                        : null,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              if (_rebajaValor > 0 || _factura) ...[
                const Divider(height: 10, color: AppColors.cardBorder),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        [
                          if (_rebajaValor > 0)
                            'Rebaja −Bs ${_rebajaValor.toStringAsFixed(2)}',
                          if (_factura)
                            'IVA +Bs ${_ivaValor.toStringAsFixed(2)}',
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      'Total a pagar Bs ${_totalPagar.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandGreen,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _seccionPagos(),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _enviando
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.cardBorder),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _enviando ? null : _guardar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Crear'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineaItem(int indice) {
    final item = _items[indice];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _desplegable(
              etiqueta: 'Producto',
              valor: item.productoId?.toString(),
              requerido: true,
              opciones: _opciones(
                'producto',
                widget.productos,
                const Opccion('', '— Selecciona —'),
                // El selector de productos muestra la miniatura de
                // cada uno al escogerlo.
                conImagen: true,
              ),
              onChanged: (valor) =>
                  setState(() => item.productoId = int.tryParse(valor ?? '')),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: TextFormField(
              initialValue: '${item.cantidad}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Cant.',
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
              ),
              validator: (valor) {
                final cantidad = int.tryParse((valor ?? '').trim());
                if (cantidad == null || cantidad <= 0) {
                  return 'Mín. 1';
                }
                // No se puede vender más de lo que hay en stock.
                final producto = item.productoId == null
                    ? null
                    : widget.productos
                          .where((p) => p.id == item.productoId)
                          .firstOrNull;
                final stock = producto?.numero('stock');
                if (stock != null && cantidad > stock) {
                  return 'Máx. $stock';
                }
                return null;
              },
              onChanged: (valor) => setState(
                () => item.cantidad = int.tryParse(valor.trim()) ?? 0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          botonAccion(
            icono: Icons.remove_circle_outline,
            color: AppColors.negativeRed,
            onTap: () {
              if (_items.length == 1) return;
              setState(() => _items.removeAt(indice));
            },
          ),
        ],
      ),
    );
  }

  Widget _desplegable({
    required String etiqueta,
    required String? valor,
    required bool requerido,
    required List<Opccion> opciones,
    required ValueChanged<String?> onChanged,
    String? etiquetaCrear,
    Future<String?> Function()? onAlta,
  }) {
    final actual = valor ?? '';
    var items = opciones;
    if (actual.isNotEmpty && !items.any((o) => o.valor == actual)) {
      items = [...items, Opccion(actual, actual)];
    }

    return DesplegableBuscable(
      initialValue: actual.isEmpty ? (requerido ? null : '') : actual,
      opciones: items,
      // Alta sobre la marcha en la hoja de opciones (solo el cliente).
      etiquetaCrear: etiquetaCrear,
      onAlta: onAlta,
      decoracion: InputDecoration(
        labelText: etiqueta,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      validator: (valor) {
        if (requerido && (valor == null || valor.isEmpty)) {
          return 'Selecciona una opción';
        }
        return null;
      },
      onChanged: onChanged,
    );
  }
}
