import 'package:flutter/material.dart';

import '../../core/errors/failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/estado_chip.dart';
import '../../domain/entities/recurso.dart';
import 'hoja_cotizacion_pdf.dart';
import 'imagen_recurso.dart';
import 'recurso_tabla.dart';
import 'vistas_estado.dart';

/// Ficha de detalle de una cotización (solo lectura).
///
/// La cabecera ya viene en el listado, pero aquí se resuelven cliente y
/// creador a nombre y se piden las líneas a la API
/// (`GET /cotizaciones/{id}` → cabecera + `detalles`), igual que la ficha
/// de Ventas. Los botones abren la hoja imprimible (PDF) o cierran.
Future<void> mostrarDetalleCotizacion(
  BuildContext context, {
  required Recurso cotizacion,
  required List<Recurso> clientes,
  required List<Recurso> empleados,
  required Future<List<Recurso>> Function(int cotizacionId) onCargarDetalles,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DetalleCotizacion(
      cotizacion: cotizacion,
      clientes: clientes,
      empleados: empleados,
      onCargarDetalles: onCargarDetalles,
    ),
  );
}

class _DetalleCotizacion extends StatefulWidget {
  const _DetalleCotizacion({
    required this.cotizacion,
    required this.clientes,
    required this.empleados,
    required this.onCargarDetalles,
  });

  final Recurso cotizacion;
  final List<Recurso> clientes;
  final List<Recurso> empleados;
  final Future<List<Recurso>> Function(int cotizacionId) onCargarDetalles;

  @override
  State<_DetalleCotizacion> createState() => _DetalleCotizacionState();
}

class _DetalleCotizacionState extends State<_DetalleCotizacion> {
  /// Líneas de la cotización; `null` mientras no lleguen de la API.
  List<Recurso>? _lineas;
  String? _error;
  bool _cargando = true;

  /// `true` mientras se arma el PDF (descarga las imágenes).
  bool _generandoPdf = false;

  @override
  void initState() {
    super.initState();
    // El estado arranca en "cargando": la primera petición no pinta nada.
    _pedir();
  }

  Future<void> _pedir() async {
    try {
      final lineas = await widget.onCargarDetalles(widget.cotizacion.id);
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

  /// Cliente: el nombre guardado en la cotización o el resuelto por id.
  String _cliente() {
    final nombre = widget.cotizacion.texto('nombreCliente', vacio: '');
    if (nombre.isNotEmpty) return nombre;
    if (widget.cotizacion['clienteId'] == null) return 'Cliente mostrador';
    return nombreDe(widget.clientes, widget.cotizacion['clienteId']);
  }

  /// Quien la creó (empleado de la sesión en el momento de crearla).
  String _creadoPor() => nombreDe(
    widget.empleados,
    widget.cotizacion['empleadoId'],
    vacio: 'Sin registrar',
  );

  /// Genera la hoja (con las imágenes de los productos) y abre la vista
  /// con los botones de imprimir/compartir.
  Future<void> _verPdf() async {
    if (_generandoPdf) return;
    setState(() => _generandoPdf = true);
    try {
      await mostrarHojaCotizacion(
        context,
        cotizacion: widget.cotizacion,
        lineas: _lineas ?? const [],
        cliente: _cliente(),
        creadoPor: _creadoPor(),
      );
    } catch (error) {
      if (!mounted) return;
      await alertaError(
        context,
        mensaje: error is Failure ? error.message : 'No se pudo generar el PDF',
      );
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cotizacion = widget.cotizacion;

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
                    'Cotización #${cotizacion.id}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                EstadoChip(valor: cotizacion.texto('estado', vacio: 'VIGENTE')),
              ],
            ),
            const SizedBox(height: 14),
            _seccion('Datos de la cotización', [
              _fila('Cliente', _cliente()),
              _fila('Creado por', _creadoPor()),
              _fila(
                'Fecha',
                _fecha(cotizacion.texto('fechaCotizacion', vacio: '')),
              ),
              _fila(
                'Creada',
                _fecha(cotizacion.texto('fechaCreacion', vacio: '')),
              ),
            ]),
            const SizedBox(height: 14),
            _rotulo('Productos'),
            const SizedBox(height: 8),
            _productos(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: AppColors.cardBorder),
            ),
            _filaTotal('Total', cotizacion.numero('total') ?? 0),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cargando || _generandoPdf ? null : _verPdf,
                    icon: _generandoPdf
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Ver PDF'),
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

  /// Cargando / error / vacío / lista de líneas (los estados del patrón).
  Widget _productos() {
    if (_cargando) return const VistaCargando();

    final error = _error;
    if (error != null) {
      return VistaError(mensaje: error, onReintentar: _reintentar);
    }

    final lineas = _lineas ?? const <Recurso>[];
    if (lineas.isEmpty) {
      return const VistaVacia(texto: 'La cotización no tiene productos');
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

  /// Una línea: imagen del producto, nombre con «cant × precio» y su monto.
  Widget _linea(Recurso linea) {
    final cantidad = linea.numero('cantidad')?.toInt() ?? 0;
    final precio = linea.numero('precioVenta') ?? 0;
    final monto = linea.numero('montoTotal') ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: 'Ver más grande',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => mostrarImagenAmpliada(
                context,
                ruta: linea.texto('imagen', vacio: ''),
                titulo: linea.texto(
                  'nombreProducto',
                  vacio: 'Imagen del producto',
                ),
              ),
              child: ImagenRecurso(
                ruta: linea.texto('imagen', vacio: ''),
                tamano: 48,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
                  '$cantidad × Bs ${precio.toStringAsFixed(2)}',
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

// --- Piezas de texto compartidas (mismo estilo que la ficha de Ventas) ------

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

/// ISO de la API → `2026-09-29 14:03` en hora local (`—` si no hay fecha).
String _fecha(String iso) {
  final momento = DateTime.tryParse(iso)?.toLocal();
  if (momento == null) return '—';
  String dos(int valor) => valor.toString().padLeft(2, '0');
  return '${momento.year}-${dos(momento.month)}-${dos(momento.day)} '
      '${dos(momento.hour)}:${dos(momento.minute)}';
}
