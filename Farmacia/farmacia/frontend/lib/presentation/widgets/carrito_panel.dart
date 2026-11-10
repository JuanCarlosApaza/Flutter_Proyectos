import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/carrito_controller.dart';
import 'panel_qr_pago.dart';
import 'desplegable_buscable.dart';
import 'imagen_recurso.dart';
import 'recurso_form.dart';
import 'recurso_tabla.dart';
import 'vistas_estado.dart';

/// Abre la hoja modal del carrito y devuelve `true` cuando se generó la
/// orden (para que la página avise con la alerta de éxito).
///
/// [clientes] y [empleados] alimentan los selectores de la caja: quien
/// llama los trae de sus controladores (la hoja no sabe de proveedores, así
/// el panel sigue siendo pintable aislado en un test).
///
/// [empleadoPorDefecto] es el vendedor de la sesión: se preselecciona si
/// está dado de alta como empleado, y la persona puede cambiarlo.
///
/// [onCrearCliente] da de alta un cliente desde el selector con su ficha
/// completa (la caja no conoce controladores, así que el diálogo y el alta
/// los ejecuta quien llama; ver `alta_persona.dart`). Devuelve el registro
/// creado o `null` si se canceló. `null` en el propio parámetro = el rol no
/// puede crear clientes y el botón no aparece.
Future<bool?> mostrarCarrito(
  BuildContext context, {
  required Future<void> Function(Map<String, Object?> body) onGenerarOrden,
  List<Recurso> clientes = const [],
  List<Recurso> empleados = const [],
  int? empleadoPorDefecto,
  Future<Recurso?> Function()? onCrearCliente,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CarritoPanel(
      onGenerarOrden: onGenerarOrden,
      clientes: clientes,
      empleados: empleados,
      empleadoPorDefecto: empleadoPorDefecto,
      onCrearCliente: onCrearCliente,
    ),
  );
}

/// Contenido del carrito: líneas con su contador de unidades, total,
/// cliente, vendedor, desglose de pagos y el botón que concreta la compra
/// generando la orden en la API.
///
/// El estado de las líneas vive en [CarritoController] (se escucha aquí con
/// `context.watch`); este widget solo conserva el cliente, el vendedor, las
/// líneas de pago elegidas y el estado de envío.
class CarritoPanel extends StatefulWidget {
  const CarritoPanel({
    super.key,
    required this.onGenerarOrden,
    this.clientes = const [],
    this.empleados = const [],
    this.empleadoPorDefecto,
    this.onCrearCliente,
  });

  /// Crea la orden en la API con el cuerpo armado por el panel
  /// (`{clienteId?, nombreCliente?, empleadoId?, pagos: [{metodoPago, monto,
  /// referencia?}], items: [{productoId, cantidad}]}`).
  final Future<void> Function(Map<String, Object?> body) onGenerarOrden;

  /// Clientes del desplegable; vacío = solo "Cliente ocasional".
  final List<Recurso> clientes;

  /// Empleados del desplegable de vendedor; vacío = solo "Sin asignar".
  final List<Recurso> empleados;

  /// Vendedor de la sesión: se preselecciona si figura en [empleados].
  final int? empleadoPorDefecto;

  /// Da de alta un cliente con toda su ficha y lo devuelve (su `Recurso`
  /// se une a la lista de la caja para aparecer y poder elegirse al instante)
  /// o `null` si se canceló el alta. `null` en el parámetro = no hay alta
  /// desde esta hoja.
  final Future<Recurso?> Function()? onCrearCliente;

  @override
  State<CarritoPanel> createState() => _CarritoPanelState();
}

/// Línea de pago del desglose: arranca con una sola y, si se reparte la
/// venta, se agrega una segunda (Efectivo / QR). La suma debe cuadrar con
/// el total.
class _PagoCarrito {
  String metodoPago = 'EFECTIVO';
  final monto = TextEditingController();
  bool montoEditado = false;
}

class _CarritoPanelState extends State<CarritoPanel> {
  final _formKey = GlobalKey<FormState>();
  String? _clienteId;
  String? _empleadoId;

  /// Clientes del selector: la lista que trae la hoja más los que se den de
  /// alta mientras está abierta. El controlador recarga su propia copia al
  /// crear, pero la caja recibió la suya al abrirse, así que el recién creado
  /// se une aquí para salir en las opciones y poder resolverse a nombre.
  late List<Recurso> _clientes;

  final List<_PagoCarrito> _pagos = [_PagoCarrito()];
  bool _enviando = false;

  /// Referencia (nº de operación) **una sola vez** para todo el cobro:
  /// viaja con los pagos QR (efectivo no tiene comprobante).
  String _referencia = '';

  /// Rebaja (descuento hecho al cliente) y factura (agrega IVA 14.94 %):
  /// el total a pagar es `(subtotal − rebaja) + IVA`, y los pagos deben
  /// cuadrar contra ese total. La rebaja solo se muestra si [_conRebaja].
  final _rebaja = TextEditingController(text: '0');
  bool _conRebaja = false;
  bool _factura = false;

  /// Controlador del carrito: se escucha para mantener el monto automático
  /// sincronizado con el total en cada cambio de la caja.
  late final CarritoController _carrito;

  /// `true` mientras [_sincronizarMonto] escribe el total en el campo, para
  /// no marcarlo como editado por ese cambio programático.
  bool _sincronizandoMonto = false;

  static const _opcional = Opccion('', '— Cliente ocasional —');
  static const _sinAsignar = Opccion('', '— Sin asignar —');

  // Opciones de los selectores memorizadas por identidad de la fuente:
  // `opcionesDe` recorre y ordena la lista entera, y la hoja se repinta con
  // cada cambio del carrito (sumar/restar unidades).
  List<Opccion>? _cacheClientes;
  Object? _origenClientes;
  List<Opccion>? _cacheEmpleados;
  Object? _origenEmpleados;

  /// Vendedores del selector: solo empleados cuyo rol permite crear
  /// ventas, más el de la sesión por si su rol no da para vender (el por
  /// defecto nunca queda fuera de las opciones). Se memoiza para no
  /// recalcularlo en cada repinta.
  late final List<Recurso> _vendedores = vendedoresDe(
    widget.empleados,
    sesion: widget.empleadoPorDefecto,
  );

  @override
  void initState() {
    super.initState();
    _clientes = widget.clientes;
    // Vendedor por defecto: quien está en la sesión. Solo se aplica si ese
    // empleado figura en la lista, para que el desplegable arranque con un
    // valor que exista entre sus opciones (invariante del widget).
    final defecto = widget.empleadoPorDefecto;
    if (defecto != null && _vendedores.any((e) => e.id == defecto)) {
      _empleadoId = '$defecto';
    }
  }

  bool _ajustesLeidos = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Corre justo después de `initState` y una sola vez: los ajustes
    // guardados en «Ajustes» mandan sobre el valor de fábrica (y sobre la
    // cuenta de la sesión); la persona puede cambiarlos antes de comprar.
    if (_ajustesLeidos) return;
    _ajustesLeidos = true;
    _carrito = context.read<CarritoController>();
    _carrito.addListener(_sincronizarMonto);
    _aplicarAjustes(AjustesScope.de(context));
    _sincronizarMonto();
  }

  @override
  void dispose() {
    _carrito.removeListener(_sincronizarMonto);
    for (final pago in _pagos) {
      pago.monto.dispose();
    }
    _rebaja.dispose();
    super.dispose();
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

    // Solo si ese empleado está entre los vendedores: un vendedor dado de
    // baja no puede preseleccionarse (invariante del selector).
    final vendedor = int.tryParse(ajustes.valor(Ajustes.vendedorPorDefecto));
    if (vendedor != null && _vendedores.any((e) => e.id == vendedor)) {
      _empleadoId = '$vendedor';
    }
  }

  List<Opccion> _opcionesClientes() {
    if (!identical(_origenClientes, _clientes)) {
      _origenClientes = _clientes;
      _cacheClientes = [_opcional, ...opcionesDe(_clientes)];
    }
    return _cacheClientes!;
  }

  List<Opccion> _opcionesEmpleados() {
    if (!identical(_origenEmpleados, _vendedores)) {
      _origenEmpleados = _vendedores;
      _cacheEmpleados = [_sinAsignar, ...opcionesDe(_vendedores)];
    }
    return _cacheEmpleados!;
  }

  /// Id elegido en el desplegable (`null` = cliente ocasional).
  int? get _clienteElegido {
    final texto = _clienteId;
    if (texto == null || texto.isEmpty) return null;
    return int.tryParse(texto);
  }

  /// Vendedor elegido (`null` = sin asignar, la orden sale sin `empleadoId`).
  int? get _vendedorElegido {
    final texto = _empleadoId;
    if (texto == null || texto.isEmpty) return null;
    return int.tryParse(texto);
  }

  /// El backend guarda `nombreCliente` como copia al crear la orden (no lo
  /// resuelve desde el id), así que se manda junto con el `clienteId`. La
  /// copia lleva el nombre completo («Nombre Apellido»).
  String? _nombreDe(int id) {
    for (final cliente in _clientes) {
      if (cliente.id == id) return nombreCompletoDe(cliente);
    }
    return null;
  }

  /// Da de alta un cliente desde el selector de la caja y devuelve su id
  /// para que el desplegable lo deje elegido en el acto. El diálogo con la
  /// ficha completa lo abre la página (`widget.onCrearCliente`, que sabe de
  /// controladores). El registro nuevo se suma a [_clientes] (la hoja ya
  /// recibió su lista al abrirse) reconstruyendo la lista entera: cambia la
  /// identidad, con lo que se invalida la caché de opciones, y no se duplica
  /// aunque la fuente compartiera memoria con la del controlador. `null` =
  /// alta cancelada.
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

  Future<void> _generar() async {
    final carrito = context.read<CarritoController>();
    if (carrito.vacio || _enviando) return;
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

    // Dos métodos fijos (Efectivo y QR): lo que quede en cero no viaja.
    // La referencia (una sola, de la sección) se lleva el pago QR.
    final pagos = <Map<String, Object?>>[];
    for (final pago in _pagos) {
      final texto = pago.monto.text.trim().replaceAll(',', '.');
      final monto = texto.isEmpty ? 0.0 : double.tryParse(texto);
      if (monto == null) {
        await alertaError(
          context,
          titulo: 'Pago incompleto',
          mensaje: 'Cada método de pago necesita un monto numérico',
        );
        return;
      }
      if (monto <= 0) continue;
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

    final cliente = _clienteElegido;
    setState(() => _enviando = true);
    try {
      await widget.onGenerarOrden({
        if (cliente != null) ...{
          'clienteId': cliente,
          'nombreCliente': _nombreDe(cliente),
        },
        'empleadoId': ?_vendedorElegido,
        'rebaja': _rebajaValor,
        'factura': _factura,
        'pagos': pagos,
        'items': [
          for (final linea in carrito.lineas)
            {'productoId': linea.productoId, 'cantidad': linea.cantidad},
        ],
      });
      carrito.vaciar();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _enviando = false);
      await alertaError(
        context,
        mensaje: error is Failure
            ? error.message
            : 'No se pudo generar la orden',
      );
    }
  }

  Future<void> _vaciar() async {
    final confirmado = await confirmarAccion(
      context,
      titulo: 'Vaciar carrito',
      mensaje: '¿Quitar todos los productos del carrito?',
      textoConfirmar: 'Vaciar',
      colorConfirmar: AppColors.negativeRed,
    );
    if (!confirmado || !mounted) return;
    context.read<CarritoController>().vaciar();
  }

  @override
  Widget build(BuildContext context) {
    // Se redibuja con cada cambio del carrito (agregar, quitar, vaciar…).
    final carrito = context.watch<CarritoController>();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Flexible + ellipsis: en anchos estrechos (móvil) el
                  // título con las unidades no debe desbordar la hoja.
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Tu carrito',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!carrito.vacio) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${carrito.unidades} u.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!carrito.vacio)
                    TextButton(
                      onPressed: _enviando ? null : _vaciar,
                      child: const Text(
                        'Vaciar',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.negativeRed,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (carrito.vacio) _vacio() else _contenido(carrito),
            ],
          ),
        ),
      ),
    );
  }

  // --- Carrito vacío -------------------------------------------------------

  Widget _vacio() {
    return Column(
      children: [
        const VistaVacia(texto: 'Tu carrito está vacío'),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandGreen,
              side: const BorderSide(color: AppColors.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Seguir comprando'),
          ),
        ),
      ],
    );
  }

  // --- Carrito con productos ----------------------------------------------

  Widget _contenido(CarritoController carrito) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final linea in carrito.lineas) _linea(linea, carrito),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: AppColors.cardBorder),
        ),
        // Lo importante primero: quién compra y quién atiende, en una fila.
        Row(
          children: [
            Expanded(
              child: _desplegable(
                etiqueta: 'Cliente',
                valor: _clienteId,
                opciones: _opcionesClientes(),
                onChanged: (valor) => setState(() => _clienteId = valor),
                // Alta de cliente sin salir de la caja (si el rol puede).
                etiquetaCrear: widget.onCrearCliente == null
                    ? null
                    : 'Nuevo cliente',
                onAlta: widget.onCrearCliente == null ? null : _crearCliente,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _desplegable(
                etiqueta: 'Vendedor',
                valor: _empleadoId,
                opciones: _opcionesEmpleados(),
                onChanged: (valor) => setState(() => _empleadoId = valor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            Text(
              'Bs ${carrito.total.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        // Rebaja y factura como interruptores; el monto de la rebaja solo
        // aparece si se enciende.
        Row(
          children: [
            Switch(
              value: _conRebaja,
              onChanged: _enviando
                  ? null
                  : (valor) => setState(() {
                      _conRebaja = valor;
                      _sincronizarMonto();
                    }),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const Text(
              'Rebaja',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 8),
            Checkbox(
              value: _factura,
              onChanged: _enviando
                  ? null
                  : (valor) => setState(() {
                      _factura = valor ?? false;
                      _sincronizarMonto();
                    }),
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}(\.\d{0,2})?')),
            ],
            enabled: !_enviando,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
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
            // El monto automático del pago sigue el total a pagar.
            onChanged: (_) => setState(_sincronizarMonto),
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
                    if (_factura) 'IVA +Bs ${_ivaValor.toStringAsFixed(2)}',
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
        const SizedBox(height: 12),
        _seccionPagos(),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _enviando ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Seguir comprando'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _enviando ? null : _generar,
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
                    : const Text('Generar orden'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Desglose de pagos ---------------------------------------------------

  /// Suma de los montos escritos (redondeada a 2 decimales).
  double get _sumaPagos {
    var suma = 0.0;
    for (final pago in _pagos) {
      final texto = pago.monto.text.trim().replaceAll(',', '.');
      final monto = double.tryParse(texto);
      if (monto == null) continue;
      suma += double.parse(monto.toStringAsFixed(2));
    }
    return suma;
  }

  /// Rebaja escrita: entre 0 y el subtotal de las líneas (0 si el
  /// interruptor de rebaja está apagado).
  double get _rebajaValor {
    if (!_conRebaja) return 0;
    final texto = _rebaja.text.trim().replaceAll(',', '.');
    final valor = double.tryParse(texto) ?? 0;
    if (valor <= 0) return 0;
    final tope = _carrito.total;
    return double.parse((valor > tope ? tope : valor).toStringAsFixed(2));
  }

  /// IVA boliviano (14.94 %): solo si la venta es factura y hay base
  /// (subtotal − rebaja) positiva. Espejo de `ivaDe` del backend.
  double get _ivaValor {
    final base = _carrito.total - _rebajaValor;
    if (!_factura || base <= 0) return 0;
    return double.parse((base * ivaBolivia).toStringAsFixed(2));
  }

  /// Total a pagar: lo que deben sumar los pagos.
  double get _totalPagar => _carrito.total - _rebajaValor + _ivaValor;

  /// Máximo que se puede rebajar en este carrito: la suma de los topes por
  /// línea (`precioRebaja` del producto; sin tope, su precio completo),
  /// nunca por encima del precio de venta.
  double get _maxRebaja {
    var suma = 0.0;
    for (final linea in _carrito.lineas) {
      final tope = linea.precioRebaja;
      final unitario =
          tope == null || tope > linea.precio ? linea.precio : tope;
      suma += unitario * linea.cantidad;
    }
    return double.parse(suma.toStringAsFixed(2));
  }

  /// El total a pagar arranca en la primera fila hasta que se edite a mano;
  /// si hay una segunda, la primera asume el total menos lo de la segunda.
  void _sincronizarMonto() {
    final primero = _pagos.first;
    if (primero.montoEditado) return;
    var otro = 0.0;
    if (_pagos.length > 1) {
      otro =
          double.tryParse(_pagos[1].monto.text.trim().replaceAll(',', '.')) ??
          0;
    }
    final pendiente = _totalPagar - otro;
    final texto = (pendiente < 0 ? 0.0 : pendiente).toStringAsFixed(2);
    if (primero.monto.text == texto) return;
    _sincronizandoMonto = true;
    primero.monto.text = texto;
    _sincronizandoMonto = false;
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
              // Flexible: en anchos estrechos el rótulo se recorta antes
              // que desbordar la tarjeta; el importe siempre cabe entero.
              Expanded(
                child: Text(
                  'Método de pago',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandGreenDark,
                  ),
                ),
              ),
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
                        _PagoCarrito()
                          ..metodoPago =
                              _pagos.first.metodoPago == 'QR'
                                  ? 'EFECTIVO'
                                  : 'QR',
                      );
                      _sincronizarMonto();
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
              controller: pago.monto,
              enabled: !_enviando,
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
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: borde(),
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
              onChanged: (_) {
                if (_sincronizandoMonto) return;
                setState(() {
                  pago.montoEditado = true;
                  // Repartir a mano: la otra fila se reajusta sola.
                  _sincronizarMonto();
                });
              },
            ),
          ),
          if (_pagos.length > 1) ...[
            const SizedBox(width: 4),
            botonAccion(
              icono: Icons.remove_circle_outline,
              color: AppColors.negativeRed,
              onTap: () => setState(() {
                _pagos.removeAt(indice);
                _sincronizarMonto();
              }),
            ),
          ],
        ],
      ),
    );
  }

  /// Desplegable compacto (cliente y vendedor) que se bloquea mientras la
  /// orden viaja a la API. [etiquetaCrear] + [onAlta] añaden el botón de
  /// alta en la hoja de opciones (solo lo usa el cliente).
  Widget _desplegable({
    String? etiqueta,
    required String? valor,
    required List<Opccion> opciones,
    required ValueChanged<String?> onChanged,
    String? etiquetaCrear,
    Future<String?> Function()? onAlta,
  }) {
    return DesplegableBuscable(
      initialValue: valor ?? '',
      opciones: opciones,
      etiquetaCrear: etiquetaCrear,
      onAlta: onAlta,
      decoracion: InputDecoration(
        labelText: etiqueta,
        labelStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      // Mientras la orden viaja a la API el selector queda bloqueado.
      habilitado: !_enviando,
      onChanged: onChanged,
    );
  }

  /// Fila de una línea: foto, nombre/precio unitario, contador y subtotal.
  Widget _linea(LineaCarrito linea, CarritoController carrito) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImagenRecurso(ruta: linea.imagen, tamano: 48, radio: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linea.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Bs ${linea.precio.toStringAsFixed(2)} c/u',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BotonMini(
                      icono: Icons.remove_rounded,
                      tooltip: 'Quitar una unidad',
                      onTap: () =>
                          carrito.cambiarCantidad(linea.productoId, -1),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${linea.cantidad}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _BotonMini(
                      icono: Icons.add_rounded,
                      tooltip: 'Agregar una unidad',
                      activo: true,
                      onTap: () => carrito.cambiarCantidad(linea.productoId, 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Bs ${linea.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              IconButton(
                tooltip: 'Quitar del carrito',
                onPressed: () => carrito.quitar(linea.productoId),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.negativeRed,
                ),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cuadrado 32×32 para +/− dentro de una línea del carrito.
class _BotonMini extends StatelessWidget {
  const _BotonMini({
    required this.icono,
    required this.onTap,
    required this.tooltip,
    this.activo = false,
  });

  final IconData icono;
  final VoidCallback onTap;
  final String tooltip;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? AppColors.brandGreen : AppColors.pageBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Icon(
            icono,
            size: 16,
            color: activo ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
