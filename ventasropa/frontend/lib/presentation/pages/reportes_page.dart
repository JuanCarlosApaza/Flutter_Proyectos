import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/exportar/informe_csv.dart';
import '../../core/storage/guardar_fichero.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../domain/entities/reporte.dart';
import '../controllers/informe_controller.dart';
import '../controllers/load_state.dart';
import '../widgets/graficos_ranking.dart';
import '../widgets/informe_graficos.dart';
import '../widgets/informe_pdf.dart';
import '../widgets/vistas_estado.dart';

/// Pantalla «Reportes»: ventas de un rango de fechas agrupadas por día, mes
/// o año, más el ranking por producto y el reparto por categoría.
///
/// Los filtros (rango + agrupación) viven en [InformeController], no aquí:
/// así, al volver al módulo desde otra pantalla, `MainScreen` recarga con el
/// rango que estaba puesto y no con uno nuevo.
class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  late InformeController _informe;

  @override
  void initState() {
    super.initState();
    // Carga inicial en el primer frame (aquí `context.read` aún no vale).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final informe = context.read<InformeController>();
      if (informe.state == LoadState.initial) informe.cargar();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _informe = context.read<InformeController>();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      title: 'Reportes',
      // Gesto de actualizar: repide el informe con los filtros actuales.
      onRefresh: _informe.recargar,
      contentBuilder: (context, constraints) => ListenableBuilder(
        // El refresco que dispara MainScreen al volver a esta pestaña
        // repinta sola, sin un setState manual.
        listenable: _informe,
        builder: (context, _) => _contenido(constraints.maxWidth),
      ),
    );
  }

  // --- Estructura -----------------------------------------------------------

  Widget _contenido(double ancho) {
    final ventas = _informe.ventas;
    final detalle = _informe.detalle;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: 'Reportes de ventas'),
          const SizedBox(height: 16),
          _barraHerramientas(),
          const SizedBox(height: 16),
          if (_informe.state == LoadState.error && ventas == null)
            VistaError(
              mensaje: _informe.errorMessage ?? 'Error',
              onReintentar: _informe.cargar,
            )
          else if (ventas == null || detalle == null)
            const VistaCargando()
          else ...[
            // Un refresco fallido deja ver el informe anterior + el aviso.
            if (_informe.state == LoadState.error) ...[
              _avisoFallo(),
              const SizedBox(height: 16),
            ],
            _kpis(ancho, ventas),
            const SizedBox(height: 16),
            _tarjetaSerie(ancho, ventas),
            const SizedBox(height: 16),
            _tarjetaProductos(ancho, detalle),
            const SizedBox(height: 16),
            _tarjetaCategorias(ancho, ventas, detalle),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _avisoFallo() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warningOrange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.warningOrange),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: AppColors.warningOrange),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'No se pudo actualizar: ${_informe.errorMessage ?? 'error'}',
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
        TextButton(onPressed: _informe.cargar, child: const Text('Reintentar')),
      ],
    ),
  );

  // --- Barra de herramientas -------------------------------------------------

  Widget _barraHerramientas() {
    final sinDatos = _informe.ventas == null;
    final hoy = _dia(DateTime.now());
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));

    final atajos = <({String etiqueta, DateTime desde, DateTime hasta})>[
      (etiqueta: 'Hoy', desde: hoy, hasta: hoy),
      (
        etiqueta: 'Ayer',
        desde: hoy.subtract(const Duration(days: 1)),
        hasta: hoy.subtract(const Duration(days: 1)),
      ),
      (etiqueta: 'Esta semana', desde: lunes, hasta: hoy),
      (
        etiqueta: 'Este mes',
        desde: DateTime(hoy.year, hoy.month, 1),
        hasta: hoy,
      ),
      (etiqueta: 'Este año', desde: DateTime(hoy.year, 1, 1), hasta: hoy),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final atajo in atajos)
          OutlinedButton(
            onPressed: () =>
                _informe.aplicar(desde: atajo.desde, hasta: atajo.hasta),
            style: _estiloRango(_activo(atajo.desde, atajo.hasta)),
            child: Text(
              atajo.etiqueta,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _activo(atajo.desde, atajo.hasta)
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(
            'Desde ${_fechaTexto(_informe.desde)}',
            style: const TextStyle(fontSize: 13),
          ),
          onPressed: () => _elegirFecha(esDesde: true),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 15),
          label: Text(
            'Hasta ${_fechaTexto(_informe.hasta)}',
            style: const TextStyle(fontSize: 13),
          ),
          onPressed: () => _elegirFecha(esDesde: false),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'dia', label: Text('Día')),
            ButtonSegment(value: 'mes', label: Text('Mes')),
            ButtonSegment(value: 'anio', label: Text('Año')),
          ],
          selected: {_informe.agrupacion},
          showSelectedIcon: false,
          onSelectionChanged: (seleccion) =>
              _informe.aplicar(agrupacion: seleccion.first),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.table_view_rounded, size: 15),
          label: const Text('CSV', style: TextStyle(fontSize: 13)),
          onPressed: sinDatos ? null : _exportarCsv,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
          label: const Text('PDF', style: TextStyle(fontSize: 13)),
          onPressed: sinDatos ? null : _exportarPdf,
        ),
      ],
    );
  }

  /// El atajo está activo cuando el rango puesto es exactamente el suyo.
  bool _activo(DateTime desde, DateTime hasta) =>
      _mismoDia(_informe.desde, desde) && _mismoDia(_informe.hasta, hasta);

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  ButtonStyle _estiloRango(bool activo) => OutlinedButton.styleFrom(
    foregroundColor: activo ? AppColors.brandGreen : AppColors.textPrimary,
    backgroundColor: activo
        ? AppColors.brandGreen.withValues(alpha: 0.10)
        : Colors.transparent,
    side: BorderSide(
      color: activo ? AppColors.brandGreen : AppColors.cardBorder,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    visualDensity: VisualDensity.compact,
  );

  Future<void> _elegirFecha({required bool esDesde}) async {
    final actual = esDesde ? _informe.desde : _informe.hasta;
    final hoy = _dia(DateTime.now());
    final elegida = await showDatePicker(
      context: context,
      initialDate: actual.isAfter(hoy) ? hoy : actual,
      firstDate: DateTime(2020),
      lastDate: hoy,
    );
    if (elegida == null || !mounted) return;

    // El rango no puede quedar invertido: al mover un extremo se arrastra
    // el otro (y así solo se pide el informe una vez).
    var desde = _informe.desde;
    var hasta = _informe.hasta;
    if (esDesde) {
      desde = elegida;
      if (desde.isAfter(hasta)) hasta = desde;
    } else {
      hasta = elegida;
      if (hasta.isBefore(desde)) desde = hasta;
    }
    await _informe.aplicar(desde: desde, hasta: hasta);
  }

  // --- Exportaciones ---------------------------------------------------------

  Future<void> _exportarCsv() async {
    final ventas = _informe.ventas;
    final detalle = _informe.detalle;
    if (ventas == null || detalle == null) return;

    try {
      final csv = construirInformeCsv(ventas: ventas, detalle: detalle);
      await guardarFichero(
        Uint8List.fromList(utf8.encode(csv)),
        'informe_ventas_${ventas.desde}_${ventas.hasta}.csv',
        extensiones: const ['csv'],
        etiqueta: 'Informe de ventas',
        mimeType: 'text/csv',
      );
    } catch (_) {
      if (mounted) _avisoExportacion('No se pudo guardar el CSV');
    }
  }

  Future<void> _exportarPdf() async {
    final ventas = _informe.ventas;
    final detalle = _informe.detalle;
    if (ventas == null || detalle == null) return;

    try {
      await mostrarInformePdf(context, ventas: ventas, detalle: detalle);
    } catch (_) {
      if (mounted) _avisoExportacion('No se pudo generar el PDF');
    }
  }

  void _avisoExportacion(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColors.negativeRed),
    );
  }

  // --- KPIs -------------------------------------------------------------------

  Widget _kpis(double ancho, InformeVentas ventas) {
    final columnas = ancho >= 1000 ? 4 : 2;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columnas,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      // Celdas holgadas: el valor va con `FittedBox` y la etiqueta no debe
      // partirse en dos líneas dentro de la tarjeta.
      childAspectRatio: columnas == 4 ? 1.8 : 1.25,
      children: [
        _kpi(
          'Bs ${ventas.resumen.total.toStringAsFixed(2)}',
          'Total vendido',
          Icons.payments_outlined,
          AppColors.brandGreen,
        ),
        _kpi(
          '${ventas.resumen.ordenes}',
          'Órdenes pagadas',
          Icons.receipt_long_outlined,
          AppColors.infoBlue,
        ),
        _kpi(
          'Bs ${ventas.resumen.ticketMedio.toStringAsFixed(2)}',
          'Ticket medio',
          Icons.point_of_sale_outlined,
          AppColors.warningOrange,
        ),
        _kpi(
          _unidades(ventas.resumen.unidades),
          'Unidades',
          Icons.inventory_2_outlined,
          AppColors.brandGreenDark,
        ),
      ],
    );
  }

  Widget _kpi(String valor, String etiqueta, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, color: color, size: 28),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            etiqueta,
            style: const TextStyle(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // --- Tarjetas ---------------------------------------------------------------

  Widget _tarjetaSerie(double ancho, InformeVentas ventas) {
    final resumen = ventas.resumen;
    return _tarjeta(
      titulo: 'Ventas por ${_agrupacionLarga(ventas.agrupacion)}',
      hijos: [
        GraficoSerie(serie: ventas.serieCompleta),
        const SizedBox(height: 16),
        _tabla(
          ancho: ancho,
          cabeceras: const ['Periodo', 'Órdenes', 'Unidades', 'Total'],
          anchos: const [150, 90, 110, 130],
          derecha: const [false, true, true, true],
          filas: [
            for (final periodo in ventas.serieCompleta)
              [
                periodo.etiqueta,
                '${periodo.ordenes}',
                _unidades(periodo.unidades),
                'Bs ${periodo.total.toStringAsFixed(2)}',
              ],
          ],
          // El pie cuadra con los KPI de arriba: suma del rango entero.
          total: [
            'Total del rango',
            '${resumen.ordenes}',
            _unidades(resumen.unidades),
            'Bs ${resumen.total.toStringAsFixed(2)}',
          ],
        ),
      ],
    );
  }

  Widget _tarjetaProductos(double ancho, InformeProductos detalle) {
    final top = detalle.productos.take(8).toList();
    final unidades = detalle.productos.fold<double>(
      0,
      (suma, producto) => suma + producto.unidades,
    );
    final monto = detalle.productos.fold<double>(
      0,
      (suma, producto) => suma + producto.monto,
    );
    return _tarjeta(
      titulo: 'Productos más vendidos',
      hijos: [
        if (top.isNotEmpty) ...[
          GraficoHorizontal(
            datos: [
              for (final producto in top)
                DatoRanking(
                  etiqueta: producto.nombre,
                  valor: producto.monto,
                  color: AppColors.brandGreen,
                  detalle:
                      'Bs ${producto.monto.toStringAsFixed(2)} · '
                      '${_unidades(producto.unidades)} uds',
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _tabla(
          ancho: ancho,
          // Ranking: puesto 1, 2, 3… (el backend los trae por monto).
          enumerar: true,
          cabeceras: const ['Producto', 'Categoría', 'Unidades', 'Total'],
          anchos: const [210, 150, 100, 120],
          derecha: const [false, false, true, true],
          filas: [
            for (final producto in detalle.productos)
              [
                producto.nombre,
                producto.categoria ?? '(sin categoría)',
                _unidades(producto.unidades),
                'Bs ${producto.monto.toStringAsFixed(2)}',
              ],
          ],
          total: [
            'Total',
            '',
            _unidades(unidades),
            'Bs ${monto.toStringAsFixed(2)}',
          ],
          vacio: 'Sin ventas de productos en este rango',
        ),
      ],
    );
  }

  Widget _tarjetaCategorias(
    double ancho,
    InformeVentas ventas,
    InformeProductos detalle,
  ) {
    final total = ventas.resumen.total;
    final unidades = detalle.categorias.fold<double>(
      0,
      (suma, categoria) => suma + categoria.unidades,
    );
    final monto = detalle.categorias.fold<double>(
      0,
      (suma, categoria) => suma + categoria.monto,
    );
    return _tarjeta(
      titulo: 'Reparto por categoría',
      hijos: [
        if (detalle.categorias.isNotEmpty) ...[
          GraficoHorizontal(
            datos: [
              for (final categoria in detalle.categorias)
                DatoRanking(
                  etiqueta: categoria.nombre,
                  valor: categoria.monto,
                  color: AppColors.brandGreenDark,
                  detalle:
                      'Bs ${categoria.monto.toStringAsFixed(2)} · '
                      '${_porcentaje(categoria.monto, total)} %',
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _tabla(
          ancho: ancho,
          cabeceras: const ['Categoría', 'Unidades', 'Total', '% total'],
          anchos: const [200, 100, 130, 80],
          derecha: const [false, true, true, true],
          filas: [
            for (final categoria in detalle.categorias)
              [
                categoria.nombre,
                _unidades(categoria.unidades),
                'Bs ${categoria.monto.toStringAsFixed(2)}',
                '${_porcentaje(categoria.monto, total)} %',
              ],
          ],
          total: [
            'Total',
            _unidades(unidades),
            'Bs ${monto.toStringAsFixed(2)}',
            '${_porcentaje(monto, total)} %',
          ],
          vacio: 'Sin ventas por categoría en este rango',
        ),
      ],
    );
  }

  Widget _tarjeta({required String titulo, required List<Widget> hijos}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...hijos,
        ],
      ),
    );
  }

  /// Tabla de informe pensada para leerse de un vistazo:
  ///
  /// * cabecera con fondo y fija (no se va con el scroll de filas);
  /// * filas a cebra, para no desviarte al seguir la línea;
  /// * `enumerar` añade la columna «#» con el puesto (podio en verde);
  /// * `total` deja una fila de **totales siempre visible** al pie;
  /// * y si la tabla no cabe entera, avisa de hay que deslizarla.
  ///
  /// [ancho] es el ancho disponible de la tarjeta: con él se decide si hace
  /// falta avisar del scroll horizontal.
  Widget _tabla({
    required double ancho,
    required List<String> cabeceras,
    required List<double> anchos,
    required List<bool> derecha,
    required List<List<String>> filas,
    List<String>? total,
    bool enumerar = false,
    String vacio = 'Sin ventas en el rango seleccionado',
  }) {
    if (filas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          vacio,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    // Con puesto, la columna «#» va delante de todas. La copia es
    // modificable: los anchos llegan como lista constante.
    final columnas = <double>[if (enumerar) 34.0, ...anchos];
    final cabecera = enumerar ? ['#', ...cabeceras] : cabeceras;
    final alinear = enumerar ? [true, ...derecha] : derecha;
    final cuerpo = [
      for (var i = 0; i < filas.length; i++)
        if (enumerar) ['${i + 1}', ...filas[i]] else filas[i],
    ];
    // El pie usa las mismas columnas (y la de «#» queda en blanco).
    final pie = total == null ? null : (enumerar ? ['', ...total] : total);

    // La tabla llena la tarjeta: el sobrante se lo lleva la columna de
    // texto (la primera que no va a la derecha), y las de cifras conservan
    // su ancho. Si no cabe, mantiene estos anchos mínimos y se desplaza.
    final sumaAnchos = columnas.fold<double>(0, (suma, a) => suma + a);
    final disponible = ancho - 40; // tarjeta: 20 px de margen por lado
    final excedente = disponible > sumaAnchos ? disponible - sumaAnchos : 0.0;
    final flexible = alinear.indexWhere((aLaDerecha) => !aLaDerecha);
    if (excedente > 0) columnas[flexible < 0 ? 0 : flexible] += excedente;
    final anchoTotal = sumaAnchos + excedente;
    // Altura real de fila (10 + 10 de margen + ~16 de texto): cuántas caben
    // sin scroll dentro de los 320 px máximos de la tabla.
    final visibles = (320 / 36).floor();

    final avisos = <String>[
      if (anchoTotal > ancho - 40) 'Desliza en horizontal',
      if (filas.length > visibles)
        'Desliza en vertical · ${filas.length} filas',
    ];

    Widget celdas(
      List<String> valores, {
      required bool cabecera,
      int puesto = 0,
      bool esPie = false,
    }) => Row(
      children: [
        for (var i = 0; i < valores.length; i++)
          () {
            // Solo la casilla del puesto se marca; el resto de la fila no.
            final podio =
                !cabecera && !esPie && i == 0 && puesto > 0 && puesto <= 3;
            return SizedBox(
              width: columnas[i],
              child: Padding(
                // Las cifras no deben pegarse al borde de la tabla.
                padding: EdgeInsets.only(right: alinear[i] ? 12 : 0),
                child: Text(
                  valores[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alinear[i] ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: cabecera || esPie || podio
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: cabecera
                        ? AppColors.textSecondary
                        : esPie
                        ? AppColors.brandGreenDark
                        : podio
                        ? AppColors.brandGreen
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }(),
      ],
    );

    return ResponsiveTableWrapper(
      child: SizedBox(
        width: anchoTotal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.pageBg,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: celdas(cabecera, cabecera: true),
            ),
            const Divider(height: 1, color: AppColors.cardBorder),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < cuerpo.length; i++)
                    Container(
                      color: i.isOdd ? AppColors.pageBg : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: celdas(
                          cuerpo[i],
                          cabecera: false,
                          puesto: enumerar ? i + 1 : 0,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (pie != null) ...[
              Divider(
                height: 1,
                thickness: 1.4,
                color: AppColors.textSecondary.withValues(alpha: 0.45),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: celdas(pie, cabecera: false, esPie: true),
              ),
            ],
            if (avisos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 14,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final aviso in avisos)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.swipe,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            aviso,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- Texto y fechas ----------------------------------------------------------

/// `dia` → `día`, `mes` → `mes`, `anio` → `año` (para los títulos).
String _agrupacionLarga(String agrupacion) => switch (agrupacion) {
  'mes' => 'mes',
  'anio' => 'año',
  _ => 'día',
};

/// Porcentaje de [valor] sobre el total del rango (`0` sin ventas).
String _porcentaje(double valor, double total) =>
    total == 0 ? '0,0' : (valor * 100 / total).toStringAsFixed(1);

/// Unidades de ropa: enteras (`12`); solo si acaso viniera fracción, con
/// decimales (`12.5`). En el informe se vende por unidades, no por peso.
String _unidades(double valor) => valor == valor.roundToDouble()
    ? valor.toInt().toString()
    : valor.toStringAsFixed(2);

/// `DateTime` → `2026-10-07`.
String _fechaTexto(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-'
    '${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

/// Hoy sin hora, para que dos comparaciones seguidas no acaben en días
/// distintos si el reloj cruza la medianoche.
DateTime _dia(DateTime momento) =>
    DateTime(momento.year, momento.month, momento.day);
