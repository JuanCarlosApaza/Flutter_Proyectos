import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/errors/failure.dart';
import '../../core/fechas.dart';
import '../../core/formatos.dart';
import '../../core/storage/guardar_fichero.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../domain/entities/reporte.dart';
import '../controllers/informes_controller.dart';
import '../controllers/load_state.dart';
import '../widgets/grafico_serie.dart';
import '../widgets/graficos_ranking.dart';
import '../widgets/informes_export.dart';
import '../widgets/vistas_estado.dart';

/// Pantalla «Reportes»: informe de ventas de un rango con gráficos y
/// exportación a CSV/PDF.
///
/// Todo el estado (rango, agrupación, informe cargado) vive en
/// [InformesController], así que al salir al sidebar y volver la pantalla se
/// repinta con lo que ya hay y el pull-to-refresh repite la consulta con los
/// **mismos filtros**.
///
/// Estados de la pantalla (los que no caben aquí están en la tarjeta que
/// corresponde):
///
/// * carga inicial → `VistaCargando`;
/// * error sin datos → `VistaError` + «Reintentar»;
/// * error en una actualización con datos previos → banner naranja, sin
///   vaciar el informe;
/// * tablas vacías → texto propio en cada tarjeta.
class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  late InformesController _informes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _informes = context.read<InformesController>();
  }

  @override
  void initState() {
    super.initState();
    // Primera entrada (fuera del build): si el controlador ya tiene el
    // informe de una visita anterior no se vuelve a tocar el servidor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_informes.state == LoadState.initial) _informes.cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Reportes',
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      onRefresh: _informes.cargar,
      contentBuilder: (context, constraints) => ListenableBuilder(
        listenable: _informes,
        builder: (context, _) => _contenido(constraints.maxWidth),
      ),
    );
  }

  // --- Estados de pantalla -------------------------------------------------

  Widget _contenido(double ancho) {
    if (_informes.state == LoadState.initial ||
        (_informes.state == LoadState.loading && !_informes.hayDatos)) {
      return const VistaCargando();
    }
    if (_informes.state == LoadState.error && !_informes.hayDatos) {
      return VistaError(
        mensaje: _informes.errorMessage ?? 'No se pudo cargar el informe',
        onReintentar: _informes.cargar,
      );
    }

    final informe = _informes.informe!;
    final productos = _informes.productos!;
    final aviso = _informes.avisoRefresco;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Reportes'),
        const SizedBox(height: 16),
        _barraFiltros(),
        if (aviso != null) ...[const SizedBox(height: 12), _banner(aviso)],
        const SizedBox(height: 16),
        _kpis(ancho, informe.resumen),
        const SizedBox(height: 16),
        _tarjetaSerie(informe),
        const SizedBox(height: 16),
        _tarjetaProductos(productos),
        const SizedBox(height: 16),
        _tarjetaCategorias(productos, informe.resumen.total),
      ],
    );
  }

  // --- Filtros -------------------------------------------------------------

  Widget _barraFiltros() {
    final atajo = _informes.atajoActivo;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Atajos de rango; ninguno resaltado cuando el rango es a mano
        // (`emptySelectionAllowed` permite la selección vacía).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SegmentedButton<AtajoRango>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final valor in AtajoRango.values)
                ButtonSegment(value: valor, label: Text(valor.etiqueta)),
            ],
            selected: {?atajo},
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (seleccion) {
              if (seleccion.isNotEmpty) {
                _informes.aplicarAtajo(seleccion.first);
              }
            },
          ),
        ),
        _botonFecha('Desde', _informes.desde, _elegirDesde),
        _botonFecha('Hasta', _informes.hasta, _elegirHasta),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'dia', label: Text('Día')),
            ButtonSegment(value: 'mes', label: Text('Mes')),
            ButtonSegment(value: 'anio', label: Text('Año')),
          ],
          selected: {_informes.agrupacion},
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: (seleccion) =>
              _informes.cambiarAgrupacion(seleccion.first),
        ),
        // Exportaciones: deshabilitadas mientras no haya nada que exportar.
        OutlinedButton.icon(
          onPressed: _informes.puedeExportar
              ? () => _exportar(esPdf: false)
              : null,
          icon: const Icon(Icons.table_view_rounded, size: 16),
          label: const Text('CSV'),
          style: _estiloExportar,
        ),
        OutlinedButton.icon(
          onPressed: _informes.puedeExportar
              ? () => _exportar(esPdf: true)
              : null,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
          label: const Text('PDF'),
          style: _estiloExportar,
        ),
      ],
    );
  }

  static final _estiloExportar = OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    foregroundColor: AppColors.textPrimary,
    side: const BorderSide(color: AppColors.cardBorder),
    padding: const EdgeInsets.symmetric(horizontal: 12),
  );

  Widget _botonFecha(String rotulo, DateTime fecha, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_rounded, size: 15),
      label: Text('$rotulo ${fechaCorta(fecha)}'),
      style: _estiloExportar,
    );
  }

  Future<void> _elegirDesde() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _informes.desde,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (elegida == null || !mounted) return;
    // Un solo extremo cambiado → una sola consulta (dentro del setter).
    _informes.cambiarDesde(elegida);
  }

  Future<void> _elegirHasta() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _informes.hasta,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (elegida == null || !mounted) return;
    _informes.cambiarHasta(elegida);
  }

  /// Banner naranja de la actualización fallida (hay datos previos en
  /// pantalla, así que no se vacía nada).
  Widget _banner(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningOrange.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warningOrange),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warningOrange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: _informes.cargar,
            child: const Text('Reintentar'),
          ),
          IconButton(
            onPressed: _informes.cerrarAviso,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cerrar aviso',
          ),
        ],
      ),
    );
  }

  // --- KPI -----------------------------------------------------------------

  Widget _kpis(double ancho, ResumenVentas resumen) {
    final columnas = ancho >= 1000 ? 5 : 2;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columnas,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      // Ratios comprobados a 360px: las tarjetas no deben desbordar ni
      // siquiera una décima de píxel (el test de responsividad lo vigila).
      childAspectRatio: ancho >= 700 ? 1.4 : 1.15,
      children: [
        _kpi(
          icono: Icons.payments_rounded,
          color: AppColors.brandGreen,
          valor: bs(resumen.total),
          etiqueta: 'Total vendido',
        ),
        _kpi(
          icono: Icons.receipt_long_rounded,
          color: AppColors.infoBlue,
          valor: '${resumen.ordenes}',
          etiqueta: 'Órdenes pagadas',
        ),
        _kpi(
          icono: Icons.trending_up_rounded,
          color: AppColors.brandGreenDark,
          valor: bs(resumen.utilidad),
          etiqueta: 'Utilidad',
        ),
        _kpi(
          icono: Icons.stacked_bar_chart_rounded,
          color: AppColors.warningOrange,
          valor: bs(resumen.ticketMedio),
          etiqueta: 'Ticket medio',
        ),
        _kpi(
          icono: Icons.shopping_bag_rounded,
          color: AppColors.brandGreenDark,
          valor: unidadesTexto(resumen.unidades),
          etiqueta: 'Unidades',
        ),
      ],
    );
  }

  Widget _kpi({
    required IconData icono,
    required Color color,
    required String valor,
    required String etiqueta,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, color: color, size: 30),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Tarjeta: serie ------------------------------------------------------

  Widget _tarjetaSerie(InformeVentas informe) {
    final resumen = informe.resumen;
    return _tarjeta(
      titulo: 'Ventas del rango',
      hijos: [
        if (resumen.ordenes == 0)
          _sinDatos('Sin ventas en este rango')
        else ...[
          GraficoSerie(datos: informe.serie, agrupacion: _informes.agrupacion),
          const SizedBox(height: 16),
          _tabla(
            columnas: const [
              'Periodo',
              'Órdenes',
              'Unidades',
              'Total',
              'Utilidad',
            ],
            anchos: const [3, 2, 2, 3, 3],
            filas: [
              for (final periodo in informe.serie)
                [
                  periodo.etiqueta,
                  '${periodo.ordenes}',
                  unidadesTexto(periodo.unidades),
                  bs(periodo.total),
                  bs(periodo.utilidad),
                ],
            ],
            pie: [
              'Total del rango',
              '${resumen.ordenes}',
              unidadesTexto(resumen.unidades),
              bs(resumen.total),
              bs(resumen.utilidad),
            ],
            derrochas: const [false, true, true, true, true],
            altoMaximo: 280,
          ),
        ],
      ],
    );
  }

  // --- Tarjeta: productos más vendidos -------------------------------------

  Widget _tarjetaProductos(InformeProductos informe) {
    final productos = informe.productos;
    return _tarjeta(
      titulo: 'Productos más vendidos',
      hijos: [
        if (productos.isEmpty)
          _sinDatos('Sin ventas de productos en este rango')
        else ...[
          GraficoHorizontal(
            datos: [
              for (final producto in informe.top)
                DatoRanking(
                  etiqueta: producto.nombre,
                  valor: producto.monto,
                  color: AppColors.brandGreen,
                  detalle:
                      '${bs(producto.monto)} · '
                      '${unidadesTexto(producto.unidades)} uds',
                ),
            ],
          ),
          const SizedBox(height: 8),
          _tabla(
            columnas: const ['#', 'Producto', 'Categoría', 'Unidades', 'Total'],
            anchos: const [1, 5, 4, 2, 3],
            filas: [
              for (var i = 0; i < productos.length; i++)
                [
                  '${i + 1}',
                  productos[i].nombre,
                  productos[i].categoria ?? '(sin categoría)',
                  unidadesTexto(productos[i].unidades),
                  bs(productos[i].monto),
                ],
            ],
            pie: [
              'Total',
              '',
              '',
              unidadesTexto(
                productos.fold<double>(0, (s, p) => s + p.unidades),
              ),
              bs(productos.fold<double>(0, (s, p) => s + p.monto)),
            ],
            derrochas: const [true, false, false, true, true],
            altoMaximo: 420,
          ),
        ],
      ],
    );
  }

  // --- Tarjeta: reparto por categorías -------------------------------------

  Widget _tarjetaCategorias(InformeProductos informe, double totalRango) {
    final categorias = informe.categorias;
    return _tarjeta(
      titulo: 'Reparto por categorías',
      hijos: [
        if (categorias.isEmpty)
          _sinDatos('Sin ventas por categorías en este rango')
        else
          _tabla(
            columnas: const ['Categoría', 'Unidades', 'Total', '%'],
            anchos: const [5, 2, 3, 2],
            filas: [
              for (final categoria in categorias)
                [
                  categoria.nombre ?? '(sin categoría)',
                  unidadesTexto(categoria.unidades),
                  bs(categoria.monto),
                  porcentajeTexto(porcentajeDe(categoria.monto, totalRango)),
                ],
            ],
            pie: [
              'Total',
              unidadesTexto(
                informe.categorias.fold<double>(0, (s, c) => s + c.unidades),
              ),
              bs(informe.categorias.fold<double>(0, (s, c) => s + c.monto)),
              porcentajeTexto(
                porcentajeDe(
                  informe.categorias.fold<double>(0, (s, c) => s + c.monto),
                  totalRango,
                ),
              ),
            ],
            derrochas: const [false, true, true, true],
          ),
      ],
    );
  }

  // --- Piezas comunes ------------------------------------------------------

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

  /// Mensaje de tarjeta sin registros (con su propio texto).
  Widget _sinDatos(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 36,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Tabla con cabecera, filas y fila de totales.
  ///
  /// * [anchos] → peso de cada columna;
  /// * [derrochas] → `true` alinea la columna a la derecha (rótulos y
  ///   valores);
  /// * [altoMaximo] → si se pasa, la tabla crece hasta esa altura y luego
  ///   desplaza dentro de la tarjeta (rango mensual = 31 filas).
  Widget _tabla({
    required List<String> columnas,
    required List<List<String>> filas,
    required List<bool> derrochas,
    List<String>? pie,
    List<double>? anchos,
    double? altoMaximo,
  }) {
    TableRow fila(
      List<String> celdas, {
      bool esCabecera = false,
      bool esPie = false,
    }) {
      return TableRow(
        children: [
          for (var i = 0; i < celdas.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                celdas[i],
                textAlign: derrochas[i] ? TextAlign.right : TextAlign.left,
                maxLines: esCabecera ? 2 : 1,
                overflow: esCabecera ? null : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: esCabecera ? 12 : 13,
                  fontWeight: esCabecera || esPie ? FontWeight.w700 : null,
                  color: esCabecera ? AppColors.textSecondary : null,
                ),
              ),
            ),
        ],
      );
    }

    final tabla = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var i = 0; i < columnas.length; i++)
          i: FlexColumnWidth(anchos == null ? 1 : anchos[i]),
      },
      children: [
        fila(columnas, esCabecera: true),
        for (final filaDatos in filas) fila(filaDatos),
        if (pie != null) fila(pie, esPie: true),
      ],
    );

    if (altoMaximo == null) return tabla;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: altoMaximo),
      child: SingleChildScrollView(child: tabla),
    );
  }

  // --- Exportaciones -------------------------------------------------------

  Future<void> _exportar({required bool esPdf}) async {
    final informe = _informes.informe;
    final productos = _informes.productos;
    if (informe == null || productos == null) return;
    if (!_informes.puedeExportar) return;

    final nombre = nombreInforme(_informes.desde, _informes.hasta);
    try {
      final bool guardado;
      if (esPdf) {
        final bytes = await pdfInforme(
          informe: informe,
          productos: productos,
          desde: _informes.desde,
          hasta: _informes.hasta,
          agrupacion: _informes.agrupacion,
        ).save();
        guardado = await guardarFichero(
          bytes,
          '$nombre.pdf',
          etiqueta: 'Informe de ventas',
          extensiones: const ['pdf'],
        );
      } else {
        final csv = csvInforme(
          informe: informe,
          productos: productos,
          desde: _informes.desde,
          hasta: _informes.hasta,
          agrupacion: _informes.agrupacion,
        );
        // BOM para que Excel reconozca los acentos del UTF-8.
        guardado = await guardarFichero(
          Uint8List.fromList(utf8.encode('\uFEFF$csv')),
          '$nombre.csv',
          etiqueta: 'Informe de ventas',
          extensiones: const ['csv'],
        );
      }

      if (!mounted || !guardado) return;
      await alertaExito(
        context,
        titulo: 'Informe exportado',
        mensaje: esPdf ? 'Se guardó $nombre.pdf' : 'Se guardó $nombre.csv',
      );
    } catch (error) {
      if (!mounted) return;
      await alertaError(
        context,
        mensaje:
            'No se pudo exportar el informe: '
            '${error is Failure ? error.message : error}',
      );
    }
  }
}
