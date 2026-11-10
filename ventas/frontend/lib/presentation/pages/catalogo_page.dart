import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/alertas.dart';
import '../../core/widgets/ajustes_scope.dart';
import '../../core/widgets/breakpoints.dart';
import '../../core/widgets/nav_scope.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/sidebar.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/carrito_controller.dart';
import '../controllers/load_state.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/alta_persona.dart';
import '../widgets/buscador_tabla.dart';
import '../widgets/carrito_panel.dart';
import '../widgets/desplegable_buscable.dart';
import '../widgets/filtros_catalogo.dart';
import '../widgets/hojas_color.dart';
import '../widgets/producto_tarjeta.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import '../widgets/vistas_estado.dart';
import 'utilidades_pagina.dart';

/// Módulo del catálogo: vitrina de productos estilo e-commerce con
/// buscador, índice de categorías, panel de filtros (casillas de
/// verificación + rango de precio) y carrito de compras.
///
/// Responsividad: `>= 700` muestra el panel de filtros a la izquierda y el
/// grid a la derecha; por debajo los filtros se abren en una hoja modal y el
/// grid ocupa todo el ancho (2 columnas, 3 en tablet, 4 en desktop).
class CatalogoPage extends StatefulWidget {
  const CatalogoPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends State<CatalogoPage> {
  /// Ancho del panel lateral de filtros (escritorio/tablet).
  static const double _anchoPanel = 264;

  /// Productos por página: múltiplo de las 2/3/4 columnas del grid para que
  /// las páginas cuadren (24 = 6 filas de 4, 8 de 3 o 12 de 2).
  static const int _porPagina = 24;

  // --- Estado de filtros y vista ---
  String _busqueda = '';
  final Set<int> _categoriasSel = {};
  final Set<String> _disponibilidad = {};
  double? _precioMin;
  double? _precioMax;
  bool _agrupar = false;
  String _orden = 'destacados';
  int _pagina = 0;

  // Los campos los posee la página para poder limpiarlos desde sus botones.
  final _ctrlBusqueda = TextEditingController();
  final _ctrlPrecioMin = TextEditingController();
  final _ctrlPrecioMax = TextEditingController();

  /// Ancla del listado: al cambiar de página se vuelve a su primera fila
  /// (si no, el usuario se quedaría mirando el pie de la página nueva).
  final _resultadosKey = GlobalKey();

  /// Revisión de los filtros: la hoja modal de móvil se construye una sola
  /// vez al abrirse (las rutas no se repintan con la página), así que
  /// [_setFiltro] notifica para que sus casillas, campos y slider muestren
  /// el estado actual — antes quedaban congelados (el slider siempre
  /// enseñaba el tope del catálogo) y daban la impresión de no funcionar.
  final ValueNotifier<int> _revisionFiltros = ValueNotifier<int>(0);

  // --- Cachés de cálculo derivado ------------------------------------------
  // La vitrina recalcula los mismos datos en cada redibujo (búsqueda, filtros,
  // conteos por categoría, límites de precio…). Se memorizan por identidad de
  // las listas y por "huella" de los filtros: un redibujo que no cambia nada
  // no repite el trabajo.
  _IndiceCatalogo? _indice;
  Object? _indiceOrigen;
  Object? _indiceOrigenCats;

  /// Nombre de cada marca por id, para las tarjetas del catálogo (la marca
  /// solo se pinta si el producto tiene una).
  Map<int, String> _marcasPorId = const {};

  List<Recurso>? _visiblesCache;
  _IndiceCatalogo? _visiblesIndice;
  Object? _visiblesOrigen;
  String? _visiblesClave;

  @override
  void initState() {
    super.initState();
    // Vitrina + índice de categorías + clientes y vendedores del carrito +
    // unidades de medida (los decimales de cada cantidad). La utilidad ya
    // difiere la carga al post-frame: no hace falta envolver.
    precargarDespuesDelPrimerFrame(context, [
      context.read<ProductosController>(),
      context.read<CategoriasController>(),
      // Las tarjetas del catálogo pinta la marca del producto (si tiene).
      context.read<MarcasController>(),
      context.read<ClientesController>(),
      context.read<EmpleadosController>(),
      context.read<UnidadesController>(),
    ]);
  }

  bool _ajustesLeidos = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Orden inicial de la vitrina: el guardado en «Ajustes» manda sobre
    // «Destacados», siempre que siga siendo una de las cuatro opciones.
    if (_ajustesLeidos) return;
    _ajustesLeidos = true;
    final orden = AjustesScope.de(context).valor(Ajustes.ordenCatalogo);
    if (ordenesCatalogo.any((opcion) => opcion.$1 == orden)) _orden = orden;
  }

  @override
  void dispose() {
    _ctrlBusqueda.dispose();
    _ctrlPrecioMin.dispose();
    _ctrlPrecioMax.dispose();
    _revisionFiltros.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Se redibuja con cada cambio de productos o categorías. El carrito NO se
    // escucha aquí: el botón del header (`context.select`) y la fila de
    // acciones de cada tarjeta (`Selector`) se suscriben por su cuenta, así
    // que agregar una unidad solo repinta dos widgets sueltos.
    final productos = context.watch<ProductosController>();
    final categorias = context.watch<CategoriasController>();
    // La marca se pinta en la tarjeta «si es que tiene»: el mapa se
    // recalcula con el catálogo (pocos registros) y lo leen las tarjetas.
    final marcas = context.watch<MarcasController>();
    _marcasPorId = {
      for (final marca in marcas.items)
        if (marca.texto('nombre', vacio: '').isNotEmpty)
          marca.id: marca.texto('nombre', vacio: ''),
    };

    return ResponsiveLayout(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      title: 'Catálogo',
      // Gesto de actualizar: recarga la vitrina y los catálogos que pinta.
      onRefresh: () async {
        await Future.wait([
          productos.recargar(),
          categorias.recargar(),
          marcas.recargar(),
        ]);
      },
      contentBuilder: (context, constraints) =>
          _contenido(constraints.maxWidth, productos, categorias),
    );
  }

  // --- Estructura ----------------------------------------------------------

  Widget _contenido(
    double ancho,
    ProductosController productos,
    CategoriasController categorias,
  ) {
    if (productos.cargando) return const VistaCargando();
    if (productos.state == LoadState.error) {
      return VistaError(
        mensaje: productos.errorMessage ?? 'Error desconocido',
        onReintentar: productos.recargar,
      );
    }

    final cats = categorias.items;
    final visibles = _visibles(productos.items, cats);
    // El carrito genera una orden (`ventas.crear` en la API): sin ese
    // permiso el catálogo es solo de consulta.
    final puedeVender =
        SesionScope.de(context)?.puede(Modulos.ventas, Acciones.crear) ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Catálogo',
          count: visibles.length,
          button: puedeVender ? _BotonCarrito(onPressed: _abrirCarrito) : null,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BuscadorTabla(
              controlador: _ctrlBusqueda,
              onChanged: _buscar,
              textoAyuda: 'Buscar producto o categoría…',
            ),
            _SelectorOrden(
              valor: _orden,
              onChanged: (valor) => setState(() => _orden = valor),
            ),
            _chip(
              etiqueta: 'Por categoría',
              seleccionado: _agrupar,
              onTap: () => setState(() => _agrupar = !_agrupar),
            ),
            // En móvil/tablet estrecho el panel no cabe: va a una hoja.
            if (ancho < Breakpoints.tablet) _botonFiltros(),
          ],
        ),
        const SizedBox(height: 12),
        if (productos.items.isNotEmpty) ...[
          _indiceCategorias(cats, productos.items),
          const SizedBox(height: 16),
        ],
        if (productos.items.isEmpty)
          const VistaVacia(texto: 'No hay productos en el catálogo')
        else if (visibles.isEmpty)
          _alLadoDelPanel(ancho, _sinCoincidencias(), cats)
        else
          _resultados(ancho, visibles, cats),
      ],
    );
  }

  /// Grid paginado (+ panel de filtros en pantallas anchas) con lo que supera
  /// los filtros. Solo se monta la página activa: con 300 productos el grid
  /// nunca infla más de [_porPagina] tarjetas.
  Widget _resultados(double ancho, List<Recurso> visibles, List<Recurso> cats) {
    final conPanel = ancho >= Breakpoints.tablet;
    final anchoGrid = _anchoDisponible(ancho, conPanel: conPanel);
    final int columnas;
    if (anchoGrid >= 1050) {
      columnas = 4;
    } else if (anchoGrid >= 700) {
      columnas = 3;
    } else {
      columnas = 2;
    }

    final carrito = context.read<CarritoController>();
    final indice = _indiceDe(context.read<ProductosController>().items, cats);
    final pagina = _paginaDe(visibles);

    final listado = Column(
      key: _resultadosKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_agrupar)
          _agrupados(pagina, cats, indice, columnas, carrito)
        else
          _grid(pagina, indice, columnas, carrito),
        if (visibles.length > _porPagina) _paginacion(visibles.length),
      ],
    );

    if (!conPanel) return listado;

    return _alLadoDelPanel(ancho, listado, cats);
  }

  // --- Paginación ----------------------------------------------------------

  /// Tramo de [visibles] de la página actual (recortado si un filtro o una
  /// recarga dejaron la página fuera de rango).
  List<Recurso> _paginaDe(List<Recurso> visibles) {
    final totalPaginas = math.max(1, (visibles.length / _porPagina).ceil());
    final pagina = _pagina.clamp(0, totalPaginas - 1);
    if (totalPaginas == 1) return visibles;
    final desde = pagina * _porPagina;
    return visibles.sublist(
      desde,
      math.min(desde + _porPagina, visibles.length),
    );
  }

  /// Rango visible + controles de páginas (solo si hay más de una).
  Widget _paginacion(int total) {
    final totalPaginas = (total / _porPagina).ceil();
    final pagina = _pagina.clamp(0, totalPaginas - 1);
    final desde = pagina * _porPagina + 1;
    final hasta = math.min((pagina + 1) * _porPagina, total);

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        children: [
          Text(
            'Mostrando $desde–$hasta de $total productos',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          PaginationControls(
            pagina: pagina,
            totalPaginas: totalPaginas,
            onCambio: _irAPagina,
          ),
        ],
      ),
    );
  }

  /// Cambia de página y sube al principio del listado (el scroll es del
  /// `ResponsiveLayout`, así que se ancla con [_resultadosKey]).
  void _irAPagina(int destino) {
    setState(() => _pagina = destino);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _resultadosKey.currentContext;
      if (contexto == null || Scrollable.maybeOf(contexto) == null) return;
      Scrollable.ensureVisible(contexto, duration: Duration.zero);
    });
  }

  /// Aplica un cambio de filtro y vuelve a la primera página: si no, el usuario
  /// se quedaría mirando una página que quizá ya no existe.
  void _setFiltro(VoidCallback cambio) {
    setState(() {
      cambio();
      _pagina = 0;
    });
    // Mantiene viva la hoja de filtros de móvil (ver [_revisionFiltros]).
    _revisionFiltros.value++;
  }

  /// Coloca [contenido] a la derecha del panel de filtros en pantallas
  /// anchas; en móvil/tablet estrecho el contenido ocupa todo el ancho.
  Widget _alLadoDelPanel(double ancho, Widget contenido, List<Recurso> cats) {
    if (ancho < Breakpoints.tablet) return contenido;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _anchoPanel, child: _panelFiltros(cats)),
        const SizedBox(width: 16),
        Expanded(child: contenido),
      ],
    );
  }

  /// Ancho disponible para el grid (descontando el panel lateral).
  double _anchoDisponible(double ancho, {required bool conPanel}) =>
      conPanel ? ancho - _anchoPanel - 16 : ancho;

  Widget _panelFiltros(List<Recurso> cats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: _filtros(cats),
    );
  }

  // --- Filtros -------------------------------------------------------------

  /// Construye el panel compartido: se pinta en el lateral (>= 700) o dentro
  /// de la hoja modal de móvil. Los conteos y límites salen del índice
  /// memorizado (no se reescanean los productos en cada redibujo).
  Widget _filtros(List<Recurso> cats) {
    final indice = _indiceDe(context.read<ProductosController>().items, cats);

    return FiltrosCatalogo(
      categorias: cats,
      categoriasSel: _categoriasSel,
      onToggleCategoria: (id) => _setFiltro(() {
        if (!_categoriasSel.remove(id)) _categoriasSel.add(id);
      }),
      disponibilidad: _disponibilidad,
      onToggleDisponibilidad: (clave) => _setFiltro(() {
        if (!_disponibilidad.remove(clave)) _disponibilidad.add(clave);
      }),
      conStock: indice.conStock,
      agotados: indice.agotados,
      controladorMin: _ctrlPrecioMin,
      controladorMax: _ctrlPrecioMax,
      rango: _rangoVisible(indice.limites),
      limites: indice.limites,
      rangoInvalido:
          _precioMin != null && _precioMax != null && _precioMin! > _precioMax!,
      onRango: _aplicarRango,
      onPrecioMin: (texto) => _aplicarPrecio(texto, esMin: true),
      onPrecioMax: (texto) => _aplicarPrecio(texto, esMin: false),
      onLimpiar: _limpiarFiltros,
    );
  }

  /// Selección real recortada a los límites del catálogo (y en orden) para
  /// que el `RangeSlider` nunca reciba un rango inválido.
  RangeValues _rangoVisible(RangeValues limites) {
    var inicio = (_precioMin ?? limites.start)
        .clamp(limites.start, limites.end)
        .toDouble();
    var fin = (_precioMax ?? limites.end)
        .clamp(limites.start, limites.end)
        .toDouble();
    if (inicio > fin) {
      final temporal = inicio;
      inicio = fin;
      fin = temporal;
    }
    return RangeValues(inicio, fin);
  }

  /// Arrastre del slider: escribe también en los dos campos.
  void _aplicarRango(RangeValues rango) {
    _ctrlPrecioMin.text = rango.start.toStringAsFixed(2);
    _ctrlPrecioMax.text = rango.end.toStringAsFixed(2);
    _setFiltro(() {
      _precioMin = rango.start;
      _precioMax = rango.end;
    });
  }

  /// Texto tecleado en "Desde" / "Hasta": vacío = sin límite y un valor
  /// incompleto (p. ej. `12.`) se ignora hasta poder parsearse.
  void _aplicarPrecio(String texto, {required bool esMin}) {
    final limpio = texto.trim().replaceAll(',', '.');
    if (limpio.isEmpty) {
      _setFiltro(() {
        if (esMin) {
          _precioMin = null;
        } else {
          _precioMax = null;
        }
      });
      return;
    }
    final valor = double.tryParse(limpio);
    if (valor == null) return;
    _setFiltro(() {
      if (esMin) {
        _precioMin = valor;
      } else {
        _precioMax = valor;
      }
    });
  }

  void _limpiarFiltros() {
    _ctrlPrecioMin.clear();
    _ctrlPrecioMax.clear();
    _setFiltro(() {
      _categoriasSel.clear();
      _disponibilidad.clear();
      _precioMin = null;
      _precioMax = null;
    });
  }

  /// Limpia filtros **y** búsqueda (estado "sin coincidencias").
  void _limpiarTodo() {
    _ctrlBusqueda.clear();
    _ctrlPrecioMin.clear();
    _ctrlPrecioMax.clear();
    _setFiltro(() {
      _busqueda = '';
      _categoriasSel.clear();
      _disponibilidad.clear();
      _precioMin = null;
      _precioMax = null;
    });
  }

  int get _filtrosActivos =>
      _categoriasSel.length +
      _disponibilidad.length +
      (_precioMin == null ? 0 : 1) +
      (_precioMax == null ? 0 : 1);

  /// Límites de precio del catálogo para el slider (0–100 sin datos).
  static RangeValues _limitesPrecios(List<Recurso> productos) {
    double? min;
    double? max;
    for (final producto in productos) {
      final precio = producto.numero('precioVenta');
      if (precio == null) continue;
      min = (min == null || precio < min) ? precio : min;
      max = (max == null || precio > max) ? precio : max;
    }
    if (min == null || max == null) return const RangeValues(0, 100);
    final inicio = min.floorToDouble();
    double fin = max.ceilToDouble();
    if (fin <= inicio) fin = inicio + 1;
    return RangeValues(inicio, fin);
  }

  // --- Índice derivado (memorizado) ----------------------------------------

  /// Datos que solo dependen de (productos, categorías): nombre por id,
  /// conteos por categoría, cuentas de disponibilidad y límites de precio.
  /// Se recalcula únicamente cuando cambia alguna de las dos listas.
  _IndiceCatalogo _indiceDe(List<Recurso> productos, List<Recurso> cats) {
    final cacheado = _indice;
    if (cacheado != null &&
        identical(_indiceOrigen, productos) &&
        identical(_indiceOrigenCats, cats)) {
      return cacheado;
    }

    final nombres = <int, String>{
      for (final categoria in cats)
        categoria.id: categoria.texto('nombre', vacio: 'Sin categoría'),
    };
    final conteos = <int, int>{};
    var conStock = 0;
    var agotados = 0;
    for (final producto in productos) {
      if ((producto.numero('stock') ?? 0) > 0) {
        conStock++;
      } else {
        agotados++;
      }
      final id = _categoriaId(producto);
      if (id != null) conteos[id] = (conteos[id] ?? 0) + 1;
    }

    final indice = _IndiceCatalogo(
      nombres: nombres,
      conteos: conteos,
      conStock: conStock,
      agotados: agotados,
      limites: _limitesPrecios(productos),
    );
    _indice = indice;
    _indiceOrigen = productos;
    _indiceOrigenCats = cats;
    return indice;
  }

  // --- Selección visible ---------------------------------------------------

  /// Aplica búsqueda, casillas de verificación, rango de precio y orden.
  ///
  /// El resultado queda memorizado mientras no cambie ninguna entrada: la
  /// página se redibuja con cada tecla, con cada recarga y con cada cambio de
  /// filtros, y este barrido es lo más caro de la vitrina.
  List<Recurso> _visibles(List<Recurso> productos, List<Recurso> cats) {
    final indice = _indiceDe(productos, cats);
    final clave =
        '$_busqueda|$_orden|${_categoriasSel.join(',')}|'
        '${_disponibilidad.join(',')}|$_precioMin|$_precioMax';
    final cacheado = _visiblesCache;
    if (cacheado != null &&
        identical(_visiblesOrigen, productos) &&
        identical(_visiblesIndice, indice) &&
        _visiblesClave == clave) {
      return cacheado;
    }

    var lista = filtrarPorBusqueda(
      productos,
      _columnasBusqueda(indice),
      _busqueda,
    );

    if (_categoriasSel.isNotEmpty) {
      lista = lista
          .where((p) => _categoriasSel.contains(_categoriaId(p)))
          .toList(growable: false);
    }
    if (_disponibilidad.isNotEmpty) {
      lista = lista
          .where((p) {
            final conStock = (p.numero('stock') ?? 0) > 0;
            return _disponibilidad.contains(
              conStock ? disponibilidadConStock : disponibilidadAgotado,
            );
          })
          .toList(growable: false);
    }

    final min = _precioMin;
    final max = _precioMax;
    if (min != null) {
      lista = lista
          .where((p) => (p.numero('precioVenta') ?? 0) >= min)
          .toList(growable: false);
    }
    if (max != null) {
      lista = lista
          .where((p) => (p.numero('precioVenta') ?? 0) <= max)
          .toList(growable: false);
    }

    final resultado = switch (_orden) {
      'precioAsc' => _ordenarPorPrecio(lista, descendente: false),
      'precioDesc' => _ordenarPorPrecio(lista, descendente: true),
      'nombre' => _ordenarPorNombre(lista),
      _ => lista,
    };

    _visiblesCache = resultado;
    _visiblesOrigen = productos;
    _visiblesIndice = indice;
    _visiblesClave = clave;
    return resultado;
  }

  /// Ordena por precio calculando cada precio **una sola vez** (si no, cada
  /// comparación del `sort` volvería a leer y parsear el campo).
  static List<Recurso> _ordenarPorPrecio(
    List<Recurso> lista, {
    required bool descendente,
  }) {
    final precios = <Recurso, double>{
      for (final producto in lista) producto: _precioDe(producto),
    };
    return [...lista]..sort(
      (a, b) => descendente
          ? precios[b]!.compareTo(precios[a]!)
          : precios[a]!.compareTo(precios[b]!),
    );
  }

  /// Orden A-Z normalizando el nombre una sola vez por producto en lugar de
  /// en cada comparación.
  static List<Recurso> _ordenarPorNombre(List<Recurso> lista) {
    final nombres = <Recurso, String>{
      for (final producto in lista)
        producto: normalizarTexto(producto.texto('nombre', vacio: '')),
    };
    return [...lista]..sort((a, b) => nombres[a]!.compareTo(nombres[b]!));
  }

  /// Columnas del buscador: nombre, categoría y marca resueltas por id
  /// desde el índice (O(1) en vez de recorrer la lista por producto).
  List<ColumnaTabla> _columnasBusqueda(_IndiceCatalogo indice) => [
    const ColumnaTabla(clave: 'nombre', etiqueta: 'Nombre'),
    ColumnaTabla(
      clave: 'categoriaId',
      etiqueta: 'Categoría',
      formato: (Recurso r) => indice.nombreDe(_categoriaId(r)),
    ),
    ColumnaTabla(
      clave: 'marcaId',
      etiqueta: 'Marca',
      formato: (Recurso r) {
        final marca = _marcaDe(r);
        return marca.isEmpty ? '—' : marca;
      },
    ),
  ];

  void _buscar(String valor) => _setFiltro(() => _busqueda = valor);

  static int? _categoriaId(Recurso producto) {
    final valor = producto['categoriaId'];
    return valor is num ? valor.toInt() : null;
  }

  /// Nombre de la marca del producto, o `''` si no tiene: la tarjeta solo
  /// pinta la marca cuando la trae.
  String _marcaDe(Recurso producto) {
    final valor = producto['marcaId'];
    final id = valor is num ? valor.toInt() : null;
    return id == null ? '' : (_marcasPorId[id] ?? '');
  }

  static double _precioDe(Recurso producto) =>
      producto.numero('precioVenta') ?? 0;

  // --- Índice de categorías ------------------------------------------------

  /// Chips de categorías con su conteo: son el índice rápido del catálogo y
  /// alimentan el mismo filtro que las casillas del panel.
  ///
  /// Siempre es un **carrusel horizontal** de una sola fila (en PC y en
  /// móvil): el `Wrap` anterior hacía varias filas que empujaban la vitrina
  /// hacia abajo en pantallas estrechas.
  Widget _indiceCategorias(List<Recurso> cats, List<Recurso> productos) {
    final indice = _indiceDe(productos, cats);
    final chips = [
      _chip(
        etiqueta: 'Todas (${productos.length})',
        seleccionado: _categoriasSel.isEmpty,
        onTap: () => _setFiltro(_categoriasSel.clear),
      ),
      for (final categoria in cats)
        _chip(
          etiqueta:
              '${categoria.texto("nombre", vacio: "Sin categoría")} '
              '(${indice.conteos[categoria.id] ?? 0})',
          seleccionado: _categoriasSel.contains(categoria.id),
          onTap: () => _setFiltro(() {
            if (!_categoriasSel.remove(categoria.id)) {
              _categoriasSel.add(categoria.id);
            }
          }),
        ),
    ];

    return _CarruselChips(chips: chips);
  }

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

  // --- Listado -------------------------------------------------------------

  Widget _grid(
    List<Recurso> items,
    _IndiceCatalogo indice,
    int columnas,
    CarritoController carrito,
  ) {
    return GridView(
      // El scroll lo da el ResponsiveLayout (guía §10); al ir paginado solo
      // se montan los [_porPagina] productos de la página activa.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnas,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: ProductoTarjeta.altura,
      ),
      children: [
        for (final producto in items) _tarjeta(producto, indice, carrito),
      ],
    );
  }

  /// Una sección por categoría con su encabezado (vista "índice").
  Widget _agrupados(
    List<Recurso> visibles,
    List<Recurso> cats,
    _IndiceCatalogo indice,
    int columnas,
    CarritoController carrito,
  ) {
    final secciones = <Widget>[];
    final categoriasListadas = <int>{};

    for (final categoria in cats) {
      categoriasListadas.add(categoria.id);
      final items = visibles
          .where((p) => _categoriaId(p) == categoria.id)
          .toList(growable: false);
      if (items.isEmpty) continue;
      secciones.add(
        _encabezadoSeccion(
          categoria.texto('nombre', vacio: 'Sin categoría'),
          items.length,
        ),
      );
      secciones.add(_grid(items, indice, columnas, carrito));
      secciones.add(const SizedBox(height: 16));
    }

    // Productos sin categoría asignada (o con una inexistente).
    final resto = visibles
        .where((p) => !categoriasListadas.contains(_categoriaId(p)))
        .toList(growable: false);
    if (resto.isNotEmpty) {
      secciones.add(_encabezadoSeccion('Sin categoría', resto.length));
      secciones.add(_grid(resto, indice, columnas, carrito));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: secciones,
    );
  }

  Widget _encabezadoSeccion(String nombre, int total) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.brandGreen,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.pageBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$total',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(
    Recurso producto,
    _IndiceCatalogo indice,
    CarritoController carrito,
  ) {
    // RepaintBoundary: cada tarjeta es su propia capa, así que al terminar
    // de cargar una imagen (o al repintarse una fila) solo se repinta esa
    // tarjeta y no todo el grid; durante el scroll las capas se reutilizan.
    return RepaintBoundary(
      child: ProductoTarjeta(
        producto: producto,
        categoria: indice.nombreDe(_categoriaId(producto)),
        // Vacío si el producto no tiene marca: la tarjeta no la pinta.
        marca: _marcaDe(producto),
        // Con una sola variante (o sin colores) se agrega directo: el
        // carrito la auto-selecciona. Con varios colores se abre la hoja
        // «Elige el color» y se agrega la variante elegida.
        onAgregar: () async {
          if (variantesDe(producto).length > 1) {
            final variante = await elegirVariante(context, producto: producto);
            if (variante == null || !mounted) return;
            carrito.agregar(producto, variante: variante);
          } else {
            carrito.agregar(producto);
          }
        },
        onRestar: () => carrito.restar(producto.id),
      ),
    );
  }

  // --- Estados vacíos ------------------------------------------------------

  Widget _sinCoincidencias() {
    final hayBusqueda = _busqueda.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_outlined,
            size: 40,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            hayBusqueda
                ? 'Sin resultados para "${_busqueda.trim()}"'
                : 'Ningún producto coincide con los filtros aplicados',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _limpiarTodo,
            icon: const Icon(Icons.close, size: 16),
            label: Text(hayBusqueda ? 'Limpiar búsqueda' : 'Limpiar filtros'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandGreen,
              side: const BorderSide(color: AppColors.cardBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Acciones ------------------------------------------------------------

  Future<void> _abrirCarrito() async {
    final ordenes = context.read<OrdenesController>();
    final productos = context.read<ProductosController>();
    final clientes = context.read<ClientesController>();
    final empleados = context.read<EmpleadosController>();
    // Siempre frescos al abrir: un vendedor o cliente dado de alta en otra
    // pantalla (u otro dispositivo) debe aparecer al instante en la caja.
    await empleados.cargar();
    await clientes.cargar();
    if (!mounted) return;

    // Alta de cliente sin salir de la caja: solo si la cuenta puede crear
    // clientes; si no, el selector se queda con «Cliente ocasional».
    final puedeCrearClientes =
        SesionScope.de(context)?.puede(Modulos.clientes, Acciones.crear) ??
        true;

    final generado = await mostrarCarrito(
      context,
      // Selectores de la caja; si los clientes aún no cargaron, la hoja se
      // queda con "Cliente ocasional".
      clientes: clientes.items,
      empleados: empleados.items,
      // El vendedor por defecto es quien tiene la sesión abierta: se lee aquí
      // (bajo el `SesionScope`) porque la hoja modal queda fuera de él.
      empleadoPorDefecto: SesionScope.de(context)?.usuario.empleadoId,
      onCrearCliente: puedeCrearClientes
          ? () => altaCliente(context, clientes: clientes)
          : null,
      onGenerarOrden: (body) async {
        await ordenes.crear(body);
        // La API descuenta stock: refrescamos la vitrina.
        await productos.recargar();
      },
    );
    if (generado != true || !mounted) return;

    // Orden registrada: se salta al módulo de Ventas para continuar con la
    // fase de venta (estado, factura) sin tener que buscarla a mano. Si el rol
    // no puede ver Ventas, la orden queda registrada y se avisa sin saltar.
    final puedeVentas = SesionScope.de(context)?.puede(Modulos.ventas) ?? true;
    if (puedeVentas) {
      (widget.onNavSelect ?? NavScope.onSeleccionarDe(context))(navVentas);
    }

    await alertaExito(
      context,
      titulo: 'Orden creada',
      mensaje: puedeVentas
          ? 'Venta registrada: ya estás en el módulo de Ventas.'
          : 'Venta registrada: la orden quedó pendiente en Ventas.',
    );
  }

  Future<void> _mostrarFiltros() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          child: ValueListenableBuilder<int>(
            // La hoja no se repinte sola con la página: esta revisión la
            // refresca con cada cambio de filtro mientras está abierta.
            valueListenable: _revisionFiltros,
            builder: (context, _, _) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _filtros(context.read<CategoriasController>().items),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botonFiltros() {
    final activos = _filtrosActivos;
    return ElevatedButton.icon(
      onPressed: _mostrarFiltros,
      icon: const Icon(Icons.tune_rounded, size: 16),
      label: Text(activos > 0 ? 'Filtros ($activos)' : 'Filtros'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.cardBg,
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.cardBorder),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Opciones de orden de la vitrina (`clave`, `etiqueta`).
///
/// Las comparten la página del catálogo y la vista «Ajustes» («Orden por
/// defecto del catálogo»): si se añade un orden aquí, aparece en los dos
/// sitios sin tocar más código.
const List<(String, String)> ordenesCatalogo = [
  ('destacados', 'Destacados'),
  ('precioAsc', 'Precio: menor a mayor'),
  ('precioDesc', 'Precio: mayor a menor'),
  ('nombre', 'Nombre A-Z'),
];

/// Desplegable compacto de ordenamiento del catálogo.
class _SelectorOrden extends StatelessWidget {
  const _SelectorOrden({required this.valor, required this.onChanged});

  static const _opciones = ordenesCatalogo;

  final String valor;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      // Mismo selector con buscador que el resto del proyecto: aquí son
      // cuatro opciones fijas, pero se comporta igual en todas partes.
      child: DesplegableBuscable(
        initialValue: valor,
        opciones: [
          for (final (clave, etiqueta) in _opciones) Opccion(clave, etiqueta),
        ],
        onChanged: (nuevo) {
          if (nuevo != null) onChanged(nuevo);
        },
        decoracion: const InputDecoration(
          isDense: true,
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        estiloTexto: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        icono: Icons.unfold_more_rounded,
      ),
    );
  }
}

/// Índice derivado del catálogo: se construye una vez por par de listas
/// (productos, categorías) y se reutiliza en todos los redibujos, para no
/// recontar ni reasignar nombres en cada frame.
final class _IndiceCatalogo {
  const _IndiceCatalogo({
    required this.nombres,
    required this.conteos,
    required this.conStock,
    required this.agotados,
    required this.limites,
  });

  /// Nombre de cada categoría por id (los chips y las tarjetas lo leen aquí).
  final Map<int, String> nombres;

  /// Nº de productos por id de categoría (conteos de los chips del índice).
  final Map<int, int> conteos;

  /// Productos con stock / agotados (casillas de disponibilidad).
  final int conStock;
  final int agotados;

  /// Rango mínimo–máximo de precio del catálogo (el slider nunca sale de él).
  final RangeValues limites;

  /// Igual que `nombreDe(...)`, pero resuelto en O(1).
  String nombreDe(int? id) => (id == null) ? '—' : (nombres[id] ?? '—');
}

/// Botón de carrito del header.
///
/// Se suscribe **solo** a las unidades (`context.select`): al agregar un
/// producto se repinta este botón y la fila de acciones de esa tarjeta, no
/// la página entera (antes cada +1 redibujaba la vitrina completa).
class _BotonCarrito extends StatelessWidget {
  const _BotonCarrito({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Cantidad total del carrito, que puede ser fraccionada (`2.25` si entre
    // todas las líneas hay 2,25 KG): se formatea sin ceros de relleno.
    final unidades = context.select<CarritoController, double>(
      (carrito) => carrito.unidades,
    );
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.shopping_cart_rounded, size: 16),
      label: Text(
        unidades <= 0 ? 'Carrito' : 'Carrito (${cantidadTexto(unidades)})',
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Carrusel horizontal de chips en una sola fila.
///
/// En pantallas estrechas solo se desliza (táctil). En PC/tablet —donde no
/// hay gesto táctil y arrastrar con el ratón es incómodo— se añaden
/// **flechas laterales** que saltan ~240 px; se desactivan en los extremos.
class _CarruselChips extends StatefulWidget {
  const _CarruselChips({required this.chips});

  final List<Widget> chips;

  @override
  State<_CarruselChips> createState() => _CarruselChipsState();
}

class _CarruselChipsState extends State<_CarruselChips> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Tras el primer layout el controlador ya está sujeto al ListView y el
    // estado de las flechas (activas/inactivas) puede calcularse.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _saltar(int direccion) {
    if (!_scroll.hasClients) return;
    final destino = (_scroll.offset + direccion * 240).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      destino,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = ListView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      children: [
        for (final chip in widget.chips)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: chip),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, restricciones) {
        // Tactil (móvil/tablet estrecho): solo deslizado.
        if (restricciones.maxWidth < Breakpoints.tablet) {
          return SizedBox(height: 44, child: lista);
        }

        // PC: flechas para avanzar con el ratón.
        return SizedBox(
          height: 44,
          child: Row(
            children: [
              _flecha(Icons.chevron_left_rounded, izquierda: true),
              Expanded(child: lista),
              _flecha(Icons.chevron_right_rounded, izquierda: false),
            ],
          ),
        );
      },
    );
  }

  Widget _flecha(IconData icono, {required bool izquierda}) {
    return AnimatedBuilder(
      animation: _scroll,
      builder: (context, _) {
        // Solo se juzga el extremo cuando el ListView ya tiene dimensiones:
        // antes, `maxScrollExtent` lanzaba (nulo) en el primer layout.
        final posicion = _scroll.hasClients ? _scroll.position : null;
        final activo =
            posicion != null &&
            posicion.hasContentDimensions &&
            (izquierda
                ? posicion.pixels > 0
                : posicion.pixels < posicion.maxScrollExtent);
        return IconButton(
          onPressed: activo ? () => _saltar(izquierda ? -1 : 1) : null,
          icon: Icon(icono, size: 22),
          color: AppColors.brandGreen,
          disabledColor: AppColors.cardBorder,
          visualDensity: VisualDensity.compact,
          tooltip: izquierda ? 'Categorías anteriores' : 'Más categorías',
        );
      },
    );
  }
}
