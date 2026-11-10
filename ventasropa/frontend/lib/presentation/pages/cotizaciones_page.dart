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
import '../widgets/buscador_tabla.dart';
import '../widgets/desplegable_buscable.dart';
import '../widgets/detalle_cotizacion.dart';
import '../widgets/imagen_recurso.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import '../widgets/selector_variante.dart';
import '../widgets/vistas_estado.dart';
import 'utilidades_pagina.dart';

/// Módulo de cotizaciones: listado con estados («Vigente», «Aceptada»,
/// «Rechazada»), alta de cotizaciones y su ficha con la hoja imprimible.
///
/// Una cotización **no toca stock** ni lleva pagos: solo fija los precios
/// vigentes para un cliente. Quien la creó lo decide la API (la sesión).
class CotizacionesPage extends StatefulWidget {
  const CotizacionesPage({super.key});

  @override
  State<CotizacionesPage> createState() => _CotizacionesPageState();
}

class _CotizacionesPageState extends State<CotizacionesPage>
    with PaginationMixin<CotizacionesPage> {
  /// Texto del buscador de la tabla (se manda al servidor con debounce).
  String _busqueda = '';

  /// Controlador del campo de búsqueda (para poder vaciarlo desde los
  /// estados sin resultados).
  final TextEditingController _campoBusqueda = TextEditingController();

  /// Peticiones de búsqueda pendientes: solo se lanza la última.
  Timer? _debounce;

  /// Ignora los clics de las acciones de fila mientras dura una operación
  /// (evita cambiar/borrar la misma cotización dos veces).
  bool _enviando = false;

  late CotizacionesController _cotizaciones;
  late ClientesController _clientes;
  late EmpleadosController _empleados;
  late ProductosController _productos;

  /// Estados comerciales que se pueden filtrar y cambiar (el borrado
  /// lógico `ELIMINADO` no se muestra nunca).
  static const _estados = ['VIGENTE', 'ACEPTADA', 'RECHAZADA'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cotizaciones = context.read<CotizacionesController>();
    _clientes = context.read<ClientesController>();
    _empleados = context.read<EmpleadosController>();
    _productos = context.read<ProductosController>();
  }

  @override
  void initState() {
    super.initState();
    // Los selectores del formulario se piden en el primer frame (solo los
    // que falten), igual que en Ventas; la tabla carga su página en el
    // servidor (offset + total reales).
    precargarDespuesDelPrimerFrame(context, [
      context.read<ClientesController>(),
      context.read<EmpleadosController>(),
      context.read<ProductosController>(),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cotizaciones.paginaCargada) return;
      _cotizaciones.cargarPagina(porPagina: porPagina);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _campoBusqueda.dispose();
    super.dispose();
  }

  Future<void> _recargar() async {
    setState(resetPage);
    await _cotizaciones.recargar();
  }

  // --- Acciones -------------------------------------------------------------

  Future<void> _ver(Recurso cotizacion) {
    return mostrarDetalleCotizacion(
      context,
      cotizacion: cotizacion,
      clientes: _clientes.items,
      empleados: _empleados.items,
      onCargarDetalles: _cotizaciones.detalles,
    );
  }

  Future<void> _cambiarEstado(Recurso cotizacion) => _unaVez(() async {
    final seleccion = await _pedirEstado(
      titulo: 'Cambiar estado de la cotización',
      opciones: _estados,
      actual: cotizacion.texto('estado'),
    );
    if (seleccion == null || !mounted) return;
    try {
      await _cotizaciones.cambiarEstado(cotizacion.id, seleccion);
      if (mounted) _aviso('Cotización #${cotizacion.id} → $seleccion');
    } catch (error) {
      _error(error);
    }
  });

  Future<void> _eliminar(Recurso cotizacion) => _unaVez(() async {
    await confirmarEliminacion(
      context: context,
      titulo: 'Cotización',
      descripcion: '¿Ocultar la cotización #${cotizacion.id}?',
      onConfirmar: () async {
        try {
          await _cotizaciones.eliminar(cotizacion.id);
          if (mounted) _aviso('Cotización #${cotizacion.id} ocultada');
        } catch (error) {
          _error(error);
        }
      },
    );
  });

  /// Ejecuta [accion] ignorando los clics que lleguen mientras dura: la
  /// operación nunca se envía dos veces (ni se apilan dos diálogos).
  Future<void> _unaVez(Future<void> Function() accion) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await accion();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  // --- Diálogo de estado (mismo patrón que Ventas) --------------------------

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

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Cotizaciones',
      // Gesto de actualizar: recarga la página de la tabla.
      onRefresh: _recargar,
      contentBuilder: (context, constraints) => ListenableBuilder(
        listenable: _cotizaciones,
        builder: (context, _) => _contenido(),
      ),
    );
  }

  Widget _contenido() {
    if (_cotizaciones.state == LoadState.error) {
      return VistaError(
        mensaje: _cotizaciones.errorMessage ?? 'Error desconocido',
        onReintentar: _recargar,
      );
    }
    // Solo el spinner a pantalla completa si todavía no hay nada cargado.
    // Con la tabla ya pintada, la recarga de la búsqueda NO desmonta la
    // columna (se iría el foco del input con cada tecla): la tabla anterior
    // sigue visible hasta que llegan los resultados nuevos, como en el
    // catálogo.
    if (!_cotizaciones.paginaCargada) return const VistaCargando();

    // Página paginada y filtrada del servidor (sin corte en cliente).
    final visibles = _cotizaciones.paginaItems;
    final hayBusqueda = _busqueda.trim().isNotEmpty;
    final sesion = SesionScope.de(context);
    // Aceptar/rechazar cotización es parte del flujo (`cotizaciones.crear`
    // en la API); borrar exige `cotizaciones.eliminar`.
    final puedeCrear =
        sesion?.puede(Modulos.cotizaciones, Acciones.crear) ?? true;
    final puedeEliminar =
        sesion?.puede(Modulos.cotizaciones, Acciones.eliminar) ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Gestión de Cotizaciones',
          count: _cotizaciones.total,
          buttonLabel: puedeCrear ? 'Nueva cotización' : null,
          onButtonPressed: puedeCrear ? _abrirNueva : null,
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
              textoAyuda: 'Buscar cotización…',
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
              seleccionado: _cotizaciones.filtroEstado == null,
              onTap: () => _filtrar(null),
            ),
            for (final estado in _estados)
              _chip(
                etiqueta: estado,
                seleccionado: _cotizaciones.filtroEstado == estado,
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
              : const VistaVacia(texto: 'No hay cotizaciones registradas')
        else ...[
          RecursoTabla(
            columnas: _columnas,
            items: visibles,
            onVer: _ver,
            onEditar: puedeCrear ? _cambiarEstado : null,
            onEliminar: puedeEliminar ? _eliminar : null,
          ),
          buildPaginationTotal(
            _cotizaciones.total,
            paginaActual: _cotizaciones.pagina,
          ),
        ],
      ],
    );
  }

  /// Manda la búsqueda al servidor con debounce y vuelve a la página 1.
  void _buscar(String valor) {
    setState(() {
      _busqueda = valor;
      resetPage();
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      _cotizaciones.busqueda = valor.trim().isEmpty ? null : valor.trim();
      await _cotizaciones.cargarPagina(numero: 0, porPagina: porPagina);
    });
  }

  void _limpiarBusqueda() {
    _campoBusqueda.clear();
    _buscar('');
  }

  Future<void> _filtrar(String? estado) async {
    setState(resetPage);
    _cotizaciones.filtroEstado = estado;
    await _cotizaciones.cargarPagina(numero: 0, porPagina: porPagina);
  }

  /// El servidor decide la página: índice del mixin y del controlador se
  /// actualizan juntos.
  @override
  void goToPage(int destino) {
    setState(() => pagina = destino);
    _cotizaciones.cargarPagina(numero: destino, porPagina: porPagina);
  }

  /// Columnas de la tabla: cliente, quién la creó (empleado resuelto por
  /// id), fecha, total y estado.
  List<ColumnaTabla> get _columnas => [
    ColumnaTabla(
      clave: 'nombreCliente',
      etiqueta: 'Cliente',
      flex: 3,
      formato: (r) => r.texto('nombreCliente', vacio: 'Cliente mostrador'),
    ),
    ColumnaTabla(
      clave: 'id',
      etiqueta: 'Cotización',
      flex: 1,
      formato: (r) => '#${r.id}',
    ),
    ColumnaTabla(
      clave: 'empleadoId',
      etiqueta: 'Creado por',
      flex: 2,
      formato: (r) => nombreDe(_empleados.items, r['empleadoId']),
    ),
    ColumnaTabla(
      clave: 'fechaCotizacion',
      etiqueta: 'Fecha',
      flex: 2,
      // La API devuelve UTC: se muestra el día en hora local (igual que la
      // ficha de detalle).
      formato: (r) => fechaCortaLocal(r.texto('fechaCotizacion', vacio: '')),
    ),
    ColumnaTabla(
      clave: 'total',
      etiqueta: 'Total',
      flex: 2,
      formato: (r) => 'Bs ${(r.numero('total') ?? 0).toStringAsFixed(2)}',
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

  // --- Nueva cotización -----------------------------------------------------

  Future<void> _abrirNueva() async {
    // Siempre frescos al abrir (no solo si están vacíos): lo dado de alta
    // en otra pantalla u otro dispositivo debe reflejarse al instante.
    await _clientes.cargar();
    await _productos.cargar();
    if (!mounted) return;

    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NuevaCotizacionForm(
        clientes: _clientes.items,
        productos: _productos.items,
        onSubmit: (body) => _cotizaciones.crear(body),
      ),
    );
    if (guardado == true && mounted) _aviso('Cotización creada');
  }
}

// --- Formulario de nueva cotización -----------------------------------------

class _ItemCotizacion {
  int? productoId;

  /// Variante (talla + color) cotada: obligatoria antes de guardar.
  int? varianteId;

  double cantidad = 1;
}

/// Hoja de alta: cliente + líneas producto/cantidad + total en vivo.
///
/// **No valida stock** (una cotización puede proyectar una compra futura) y
/// no lleva pagos: el precio lo fija el servidor con la BD.
class _NuevaCotizacionForm extends StatefulWidget {
  const _NuevaCotizacionForm({
    required this.clientes,
    required this.productos,
    required this.onSubmit,
  });

  final List<Recurso> clientes;
  final List<Recurso> productos;
  final Future<void> Function(Map<String, Object?> body) onSubmit;

  @override
  State<_NuevaCotizacionForm> createState() => _NuevaCotizacionFormState();
}

class _NuevaCotizacionFormState extends State<_NuevaCotizacionForm> {
  final _formKey = GlobalKey<FormState>();
  final List<_ItemCotizacion> _items = [_ItemCotizacion()];
  String? _clienteId;
  bool _enviando = false;

  bool _ajustesLeidos = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // El cliente por defecto de «Ajustes» manda sobre «Cliente ocasional»;
    // se lee una sola vez, justo después de montar.
    if (_ajustesLeidos) return;
    _ajustesLeidos = true;
    final cliente = AjustesScope.de(context).valor(Ajustes.clientePorDefecto);
    if (cliente.isNotEmpty &&
        widget.clientes.any((c) => '${c.id}' == cliente)) {
      _clienteId = cliente;
    }
  }

  /// Opciones de los dos desplegables, memorizadas por clave mientras la
  /// fuente no cambie (mismo patrón que «Nueva Orden»).
  final Map<String, List<Opccion>> _cacheOpciones = {};
  final Map<String, Object> _origenOpciones = {};

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
      if (_productoDe(item.productoId) == null) continue;
      suma += _precioDe(item) * item.cantidad;
    }
    return suma;
  }

  /// Precio unitario de la línea: el del producto (un único precio por
  /// prenda, sin importe propio por variante).
  double _precioDe(_ItemCotizacion item) {
    final producto = _productoDe(item.productoId);
    if (producto == null) return 0;
    return producto.numero('precioVenta') ?? 0;
  }

  Recurso? _productoDe(int? id) {
    if (id == null) return null;
    for (final producto in widget.productos) {
      if (producto.id == id) return producto;
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_items.any((item) => item.productoId == null)) {
      await alertaError(
        context,
        titulo: 'Cotización incompleta',
        mensaje: 'Cada línea necesita un producto',
      );
      return;
    }
    if (_items.any((item) => item.varianteId == null)) {
      await alertaError(
        context,
        titulo: 'Cotización incompleta',
        mensaje: 'Cada línea necesita su talla y color',
      );
      return;
    }
    final variantes = _items.map((item) => item.varianteId).toSet();
    if (variantes.length != _items.length) {
      await alertaError(
        context,
        titulo: 'Línea duplicada',
        mensaje: 'Hay una talla y color repetidos en la cotización.',
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      await widget.onSubmit({
        if (_clienteId != null && _clienteId!.isNotEmpty)
          'clienteId': int.parse(_clienteId!),
        if (_clienteId != null && _clienteId!.isNotEmpty)
          'nombreCliente': _nombreDe(widget.clientes, _clienteId),
        'items': [
          for (final item in _items)
            {
              'productoId': item.productoId,
              'varianteId': item.varianteId,
              'cantidad': item.cantidad,
            },
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
                'Nueva Cotización',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _desplegable(
                etiqueta: 'Cliente',
                valor: _clienteId,
                requerido: false,
                opciones: _opciones(
                  'cliente',
                  widget.clientes,
                  const Opccion('', '— Cliente mostrador —'),
                ),
                onChanged: (valor) => setState(() => _clienteId = valor),
              ),
              const SizedBox(height: 20),
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
                onPressed: () => setState(() => _items.add(_ItemCotizacion())),
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

  /// Variantes visibles (talla + color) de la prenda elegida en la línea.
  List<Recurso> _variantesDeItem(_ItemCotizacion item) {
    final producto = _productoDe(item.productoId);
    if (producto == null) return const [];
    return variantesDe(producto)
        .where((v) => v.texto('estado') != 'ELIMINADO')
        .toList();
  }

  /// Abre la hoja de selector de variante (la del catálogo) para la prenda
  /// elegida en la línea y anota la variante escogida.
  ///
  /// Una sola variante se anota sola, sin hoja; cancelar la hoja deja la
  /// talla sin marcar, para elegirla después en el desplegable. La espera
  /// de un instante es para que la hoja de opciones de la prenda termine
  /// de cerrarse y la de variante no se cruce con su animación.
  Future<void> _elegirVarianteDe(_ItemCotizacion item) async {
    final producto = _productoDe(item.productoId);
    if (producto == null) return;
    final productoId = producto.id;
    if (_variantesDeItem(item).length > 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || item.productoId != productoId) return;
    }
    final elegida = await elegirVariante(context, producto);
    if (elegida == null || !mounted || item.productoId != productoId) return;
    setState(() => item.varianteId = elegida.id);
  }

  Widget _lineaItem(int indice) {
    final item = _items[indice];
    final producto = _productoDe(item.productoId);
    final variantes = _variantesDeItem(item);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _desplegable(
                  etiqueta: 'Prenda',
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
                  onChanged: (valor) {
                    setState(() {
                      item.productoId = int.tryParse(valor ?? '');
                      item.varianteId = null;
                    });
                    // Mismo flujo que «Agregar» en el catálogo: elegir la
                    // prenda abre la hoja de talla/color.
                    _elegirVarianteDe(item);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _desplegable(
                  etiqueta: 'Talla / color',
                  valor: item.varianteId?.toString(),
                  requerido: true,
                  opciones: [
                    const Opccion('', '— Talla —'),
                    for (final variante in variantes)
                      Opccion('${variante.id}', etiquetaVariante(variante)),
                  ],
                  onChanged: (valor) => setState(
                    () => item.varianteId = int.tryParse(valor ?? ''),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: TextFormField(
                  initialValue: cantidadTexto(item.cantidad),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    // Unidades enteras (la ropa no se vende por gramos).
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}')),
                  ],
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
                    final cantidad = double.tryParse((valor ?? '').trim());
                    // Sin tope de stock: una cotización puede proyectar más
                    // unidades de las que hay hoy; sí, unidades enteras.
                    if (cantidad == null || cantidad <= 0) return 'Mín. 1';
                    if (cantidad != cantidad.roundToDouble()) {
                      return 'Solo enteros';
                    }
                    return null;
                  },
                  onChanged: (valor) => setState(
                    () => item.cantidad = double.tryParse(valor.trim()) ?? 0,
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
          if (producto != null) ...[
            const SizedBox(height: 8),
            // El precio que se muestra es el de la línea: el de su variante
            // si la tiene propio.
            _vistaProducto(producto, _precioDe(item)),
          ],
        ],
      ),
    );
  }

  /// Miniatura grande del producto elegido (toca la imagen para ampliarla);
  /// al lado, precio y stock para poder cotizar sin salir del formulario.
  /// [precio] es el unitario de esta línea (ver [_precioDe]).
  Widget _vistaProducto(Recurso producto, double precio) {
    final ruta = producto.texto('imagen', vacio: '');
    final nombre = producto.texto('nombre', vacio: 'Imagen del producto');
    final stock = producto.numero('stock');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Ver más grande',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () =>
                mostrarImagenAmpliada(context, ruta: ruta, titulo: nombre),
            child: ImagenRecurso(ruta: ruta, tamano: 64, radio: 10),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bs ${precio.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              if (stock != null)
                Text(
                  'Stock disponible: ${cantidadTexto(stock)} '
                  '${producto.texto('unidad', vacio: 'UN')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desplegable({
    required String etiqueta,
    required String? valor,
    required bool requerido,
    required List<Opccion> opciones,
    required ValueChanged<String?> onChanged,
  }) {
    final actual = valor ?? '';
    var items = opciones;
    if (actual.isNotEmpty && !items.any((o) => o.valor == actual)) {
      items = [...items, Opccion(actual, actual)];
    }

    return DesplegableBuscable(
      // Clave por valor: `FormField` no sincroniza `initialValue` y la
      // talla / color se elige sola al marcar la prenda.
      key: ValueKey('$etiqueta#${valor ?? ''}'),
      initialValue: actual.isEmpty ? (requerido ? null : '') : actual,
      opciones: items,
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
