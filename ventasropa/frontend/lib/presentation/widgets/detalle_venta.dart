import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/estado_chip.dart';
import '../../domain/entities/recurso.dart';
import 'recibo_pdf.dart';
import 'recurso_tabla.dart';
import 'vistas_estado.dart';

/// Fichas de detalle del módulo Ventas.
///
/// La cabecera de la orden/factura ya viaja en el listado, pero la tabla solo
/// muestra una parte (cliente, pago, total, fecha, estado). Aquí se abre la
/// ficha completa: cliente y empleado **resueltos a nombre**, fechas y —en el
/// caso de la orden— sus líneas de producto, que sí piden un viaje a la API
/// (`GET /ordenes/{id}`, que devuelve la cabecera más `detalles`).
///
/// Es solo lectura (como la ficha de `RecursoForm(soloLectura)`): las
/// acciones de estado/cobro siguen siendo de la tabla.

/// Abre la hoja con el detalle de una orden y sus líneas.
///
/// [onCargarDetalles] trae los productos de la orden; quien llama pasa
/// `OrdenesController.detalles`, para que la hoja no dependa de proveedores
/// (se pinta aislada en los tests).
Future<void> mostrarDetalleOrden(
  BuildContext context, {
  required Recurso orden,
  required List<Recurso> clientes,
  required List<Recurso> empleados,
  required Future<List<Recurso>> Function(int ordenId) onCargarDetalles,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DetalleOrden(
      orden: orden,
      clientes: clientes,
      empleados: empleados,
      onCargarDetalles: onCargarDetalles,
    ),
  );
}

/// Abre la hoja con el detalle de una factura (sin líneas: todo su dato ya
/// viene en el listado, aquí se traducen los ids a nombres). [orden] (si se
/// pasa) aporta el resumen de **cómo se pagó**.
Future<void> mostrarDetalleFactura(
  BuildContext context, {
  required Recurso factura,
  required List<Recurso> clientes,
  required List<Recurso> empleados,
  Recurso? orden,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DetalleFactura(
      factura: factura,
      clientes: clientes,
      empleados: empleados,
      orden: orden,
    ),
  );
}

// --- Cabecera y pie comunes -------------------------------------------------

/// Hoja de detalle: manija, cabecera con título + chip de estado, cuerpo
/// desplazable y botones "Ver recibo" (si se pasa [onImprimir]) y "Cerrar"
/// (misma receta visual que el resto de hojas).
class _Ficha extends StatelessWidget {
  const _Ficha({
    required this.titulo,
    required this.estado,
    required this.contenido,
    this.onImprimir,
  });

  final String titulo;

  /// Estado a pintar como chip; vacío = sin chip.
  final String estado;

  final Widget contenido;

  /// Abre el diálogo de impresión del recibo; `null` = botón deshabilitado
  /// (p. ej. mientras cargan las líneas de la orden).
  final VoidCallback? onImprimir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (estado.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  EstadoChip(valor: estado),
                ],
              ],
            ),
            const SizedBox(height: 14),
            contenido,
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onImprimir,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Ver recibo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.cardBorder,
                      disabledForegroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Detalle de una orden ---------------------------------------------------

class _DetalleOrden extends StatefulWidget {
  const _DetalleOrden({
    required this.orden,
    required this.clientes,
    required this.empleados,
    required this.onCargarDetalles,
  });

  final Recurso orden;
  final List<Recurso> clientes;
  final List<Recurso> empleados;
  final Future<List<Recurso>> Function(int ordenId) onCargarDetalles;

  @override
  State<_DetalleOrden> createState() => _DetalleOrdenState();
}

class _DetalleOrdenState extends State<_DetalleOrden> {
  /// Líneas de la orden; `null` mientras no lleguen de la API.
  List<Recurso>? _lineas;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    // El estado ya arranca en "cargando", así que la primera petición no
    // necesita notificar (no hay build que repintar todavía).
    _pedir();
  }

  Future<void> _pedir() async {
    try {
      final lineas = await widget.onCargarDetalles(widget.orden.id);
      if (!mounted) return;
      setState(() {
        _lineas = lineas;
        _error = null;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is Failure ? error.message : 'Error inesperado';
        _cargando = false;
      });
    }
  }

  void _reintentar() {
    setState(() {
      _cargando = true;
      _error = null;
      _lineas = null;
    });
    _pedir();
  }

  /// Cliente: el nombre guardado en la orden y, si no, el resuelto por id.
  String _cliente() {
    final nombre = widget.orden.texto('nombreCliente', vacio: '');
    if (nombre.isNotEmpty) return nombre;
    if (widget.orden['clienteId'] == null) return 'Cliente ocasional';
    return nombreDe(widget.clientes, widget.orden['clienteId']);
  }

  String _empleado() {
    if (widget.orden['empleadoId'] == null) return '— Sin asignar —';
    return nombreDe(widget.empleados, widget.orden['empleadoId']);
  }

  /// Desglose de pagos de la orden (efectivo + Yape...); se omite si no viene.
  Widget _pagos() {
    final pagos = widget.orden['pagos'];
    if (pagos is! List || pagos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _seccion('Pagos', [
        for (final p in pagos)
          if (p is Map)
            _fila(metodoLegible(p['metodoPago']), _importe(p)),
      ]),
    );
  }

  static String _importe(Map p) {
    final monto = p['monto'] is num ? (p['monto'] as num).toDouble() : 0.0;
    final referencia = p['referencia'];
    final referenciaTexto = referencia is String && referencia.trim().isNotEmpty
        ? ' · ${referencia.trim()}'
        : '';
    return 'Bs ${monto.toStringAsFixed(2)}$referenciaTexto';
  }

  /// Abre la vista previa del recibo de la orden (sus líneas ya vinieron
  /// de la API al abrir la ficha) para imprimirlo o compartirlo.
  Future<void> _imprimir() async {
    try {
      await mostrarReciboOrden(
        context,
        widget.orden,
        lineas: _lineas ?? const [],
        cliente: _cliente(),
        empleado: _empleado(),
      );
    } catch (error) {
      if (!mounted) return;
      await alertaError(
        context,
        mensaje: error is Failure ? error.message : 'No se pudo imprimir',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orden = widget.orden;

    return _Ficha(
      titulo: 'Orden #${orden.id}',
      estado: orden.texto('estado', vacio: ''),
      // Sin líneas cargadas el recibo saldría vacío: se habilita al llegar.
      onImprimir: _cargando ? null : _imprimir,
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _seccion('Datos de la venta', [
            _fila('Cliente', _cliente()),
            _fila('Empleado', _empleado()),
            _fila(
              'Fecha de orden',
              _fecha(orden.texto('fechaOrden', vacio: '')),
            ),
            _fila('Creada', _fecha(orden.texto('fechaCreacion', vacio: ''))),
            _fila(
              'Actualizada',
              _fecha(orden.texto('fechaActualizacion', vacio: '')),
            ),
          ]),
          const SizedBox(height: 14),
          _pagos(),
          _rotulo(_tituloProductos()),
          const SizedBox(height: 8),
          _productos(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: AppColors.cardBorder),
          ),
          _filaTotal('Total', orden.numero('total') ?? 0),
        ],
      ),
    );
  }

  String _tituloProductos() {
    final lineas = _lineas;
    if (lineas == null) return 'Productos';
    final unidades = lineas.fold<double>(
      0,
      (suma, linea) => suma + (linea.numero('cantidad') ?? 0),
    );
    return 'Productos · ${lineas.length} líneas · ${cantidadTexto(unidades)} u.';
  }

  /// Cargando / error / vacío / lista de líneas (los estados del patrón).
  Widget _productos() {
    if (_cargando) return const VistaCargando();

    final error = _error;
    if (error != null) {
      return VistaError(mensaje: error, onReintentar: _reintentar);
    }

    final lineas = _lineas ?? const <Recurso>[];
    if (lineas.isEmpty) {
      return const VistaVacia(texto: 'La orden no tiene productos');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lineas.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.cardBorder),
            _linea(lineas[i]),
          ],
        ],
      ),
    );
  }

  /// Una línea: producto, "cantidad × precio unitario" y su monto.
  Widget _linea(Recurso linea) {
    final cantidad = cantidadTexto(linea.numero('cantidad') ?? 0);
    final precio = linea.numero('precioVenta') ?? 0;
    final monto = linea.numero('montoTotal') ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  linea.texto('nombreProducto', vacio: 'Producto'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (linea.texto('marca', vacio: '').isNotEmpty)
                      linea.texto('marca'),
                    if (linea.texto('talla', vacio: '').isNotEmpty)
                      '${linea.texto('talla')} · ${linea.texto('color')}',
                    '$cantidad ${linea.texto('unidad', vacio: 'UN')} × '
                    'Bs ${precio.toStringAsFixed(2)}',
                  ].join(' — '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Bs ${monto.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Detalle de una factura --------------------------------------------------

class _DetalleFactura extends StatelessWidget {
  const _DetalleFactura({
    required this.factura,
    required this.clientes,
    required this.empleados,
    this.orden,
  });

  final Recurso factura;
  final List<Recurso> clientes;
  final List<Recurso> empleados;

  /// Orden asociada: de ella sale el resumen de cómo se pagó.
  final Recurso? orden;

  /// Resumen del pago (`Efectivo + QR`) de la orden asociada.
  String _pago() {
    final pagos = orden?['pagos'];
    if (pagos is! List || pagos.isEmpty) return '—';
    final resumen = pagos
        .whereType<Map>()
        .map((p) => metodoLegible(p['metodoPago']))
        .join(' + ');
    return resumen.isEmpty ? '—' : resumen;
  }

  /// Abre la vista previa del recibo de la factura para imprimirlo o
  /// compartirlo (sus datos ya vienen en el listado, aquí solo se
  /// traducen los ids a nombres).
  Future<void> _imprimir(BuildContext context) async {
    try {
      await mostrarReciboFactura(
        context,
        factura,
        cliente: nombreDe(clientes, factura['clienteId']),
        empleado: nombreDe(empleados, factura['empleadoId']),
        pagos: orden?['pagos'],
      );
    } catch (error) {
      if (!context.mounted) return;
      await alertaError(
        context,
        mensaje: error is Failure ? error.message : 'No se pudo imprimir',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Ficha(
      titulo: 'Boleta #${factura.id}',
      estado: factura.texto('estado', vacio: ''),
      onImprimir: () => _imprimir(context),
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _seccion('Datos de la factura', [
            _fila(
              'Orden',
              factura['ordenId'] == null ? '—' : '#${factura['ordenId']}',
            ),
            if (orden != null) _fila('Pago', _pago()),
            _fila('Cliente', nombreDe(clientes, factura['clienteId'])),
            _fila('Empleado', nombreDe(empleados, factura['empleadoId'])),
            _fila(
              'Fecha de factura',
              _fecha(factura.texto('fechaFactura', vacio: '')),
            ),
            _fila('Creada', _fecha(factura.texto('fechaCreacion', vacio: ''))),
            _fila(
              'Actualizada',
              _fecha(factura.texto('fechaActualizacion', vacio: '')),
            ),
          ]),
          const SizedBox(height: 14),
          _seccion('Importes', [
            _fila(
              'Subtotal',
              'Bs ${(factura.numero('subtotal') ?? 0).toStringAsFixed(2)}',
            ),
            _fila(
              'Rebaja',
              '− Bs ${(factura.numero('rebaja') ?? 0).toStringAsFixed(2)}',
            ),
            _fila(
              'IVA 14.94%',
              'Bs ${(factura.numero('iva') ?? 0).toStringAsFixed(2)}',
            ),
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: AppColors.cardBorder),
          ),
          _filaTotal('Total', factura.numero('total') ?? 0),
        ],
      ),
    );
  }
}

// --- Piezas de texto compartidas -------------------------------------------

/// Rótulo de una sección (mismo estilo que "Tipo de pago" del carrito).
Widget _rotulo(String texto) {
  return Text(
    texto,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );
}

/// Tarjeta con fondo de página para agrupar filas `etiqueta → valor`.
Widget _seccion(String titulo, List<Widget> filas) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_rotulo(titulo), const SizedBox(height: 8), ...filas],
    ),
  );
}

/// Fila de datos: etiqueta a la izquierda y valor (en negrita) a la derecha;
/// el valor puede ocupar dos líneas para no cortar nombres largos.
Widget _fila(String etiqueta, String valor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(
            etiqueta,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Fila de importe final (la que remata el carrito y estas fichas).
Widget _filaTotal(String etiqueta, double monto) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        etiqueta,
        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
      ),
      Text(
        'Bs ${monto.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    ],
  );
}

/// `EFECTIVO` → `Efectivo`: en la ficha se lee mejor que en mayúsculas.
String _legible(String texto) {
  if (texto.isEmpty) return '—';
  final minus = texto.toLowerCase();
  return minus[0].toUpperCase() + minus.substring(1);
}

/// Nombre legible de un método de pago (`EFECTIVO` → `Efectivo`; `QR` va
/// tal cual, `_legible` lo dejaría como «Qr»).
String metodoLegible(Object? metodo) {
  final texto = metodo?.toString() ?? '';
  if (texto == 'QR') return 'QR';
  return _legible(texto);
}

/// ISO de la API → `2026-09-29 14:03` en hora local (`—` si no hay fecha).
String _fecha(String iso) {
  final momento = DateTime.tryParse(iso)?.toLocal();
  if (momento == null) return '—';
  String dos(int valor) => valor.toString().padLeft(2, '0');
  return '${momento.year}-${dos(momento.month)}-${dos(momento.day)} '
      '${dos(momento.hour)}:${dos(momento.minute)}';
}
