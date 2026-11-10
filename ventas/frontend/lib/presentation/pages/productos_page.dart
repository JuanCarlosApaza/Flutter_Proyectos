import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/desplegable_buscable.dart';
import '../widgets/importar_excel.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import 'recurso_page.dart';
import 'utilidades_pagina.dart';

/// Módulo de productos: listado con CRUD completo y filtros por estado.
class ProductosPage extends StatefulWidget {
  const ProductosPage({super.key, this.selectedNav, this.onNavSelect});

  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;

  @override
  State<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends State<ProductosPage> {
  /// Campos del formulario, guardados al construir la página: la misma
  /// lista la usa el diálogo de importación de Excel.
  List<CampoFormulario>? _camposProducto;

  @override
  void initState() {
    super.initState();
    // Los combos (categorías, presentaciones, proveedores, unidades,
    // colores, marcas) se cargan aparte, tras el primer frame (la utilidad
    // difiere la carga ella sola).
    precargarDespuesDelPrimerFrame(context, [
      context.read<CategoriasController>(),
      context.read<PresentacionesController>(),
      context.read<ProveedoresController>(),
      context.read<UnidadesController>(),
      context.read<ColoresController>(),
      context.read<MarcasController>(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final categorias = context.read<CategoriasController>();
    final presentaciones = context.read<PresentacionesController>();
    final proveedores = context.read<ProveedoresController>();
    // Catálogo de marcas (pestaña «Marcas» de Categorías): columna, filtro
    // del buscador y desplegable del formulario.
    final marcas = context.read<MarcasController>();
    // La tabla de productos (el filtro de marca le escribe `?marcaId=`).
    final productos = context.read<ProductosController>();
    // Catálogo de unidades de medida (pantalla «Unidades»): de aquí sale el
    // desplegable «Unidad de venta» y los decimales que admite cada una.
    final unidades = context.read<UnidadesController>();

    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Productos',
      controller: context.read<ProductosController>(),
      tituloSeccion: 'Gestión de Productos',
      etiquetaNuevo: 'Nuevo Producto',
      // Mismo permiso que el alta: sin `productos.crear` no aparece.
      accionesCabecera: [
        if (SesionScope.de(context)?.puede(Modulos.productos, Acciones.crear) ??
            true)
          ElevatedButton.icon(
            onPressed: () => _importarExcel(context),
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Importar Excel'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cardBg,
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.cardBorder),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
      ],
      entidad: 'producto',
      textoVacio: 'No hay productos registrados',
      filtros: const [
        FiltroEstado('DISPONIBLE', 'Disponibles'),
        FiltroEstado('AGOTADO', 'Agotados'),
        FiltroEstado('POR_VENCER', 'Por vencer'),
        FiltroEstado('DESCONTINUADO', 'Descontinuados'),
      ],
      herramientasExtra: [_filtroMarca(productos, marcas)],
      columnas: [
        const ColumnaTabla(
          clave: 'nombre',
          etiqueta: 'Nombre',
          flex: 4,
          miniatura: true,
        ),
        ColumnaTabla(
          clave: 'categoriaId',
          etiqueta: 'Categoría',
          flex: 2,
          formato: (Recurso r) => nombreDe(categorias.items, r['categoriaId']),
        ),
        // Marca en texto (023): «—» cuando el producto no lleva. Su nombre
        // también entra en la búsqueda libre `?q=` (la amplía el backend).
        ColumnaTabla(
          clave: 'marcaId',
          etiqueta: 'Marca',
          flex: 2,
          formato: (Recurso r) => nombreDe(marcas.items, r['marcaId']),
        ),
        ColumnaTabla(
          clave: 'precioVenta',
          etiqueta: 'Precio',
          flex: 2,
          formato: (Recurso r) => 'Bs ${_dinero(r)}',
        ),
        ColumnaTabla(
          clave: 'precioRebaja',
          etiqueta: 'Máx. rebaja',
          flex: 2,
          formato: (Recurso r) {
            final tope = r.numero('precioRebaja');
            return tope == null ? '—' : 'Bs ${tope.toStringAsFixed(2)}';
          },
        ),
        const ColumnaTabla(
          clave: 'stock',
          etiqueta: 'Stock',
          flex: 1,
          formato: _stockConUnidad,
        ),
        const ColumnaTabla(
          clave: 'estado',
          etiqueta: 'Estado',
          flex: 2,
          chip: true,
        ),
      ],
      // El formulario se abre con dos pestañas: lo que hay que rellenar sí
      // o sí (Obligatorio) y el resto, que se completa cuando se quiera
      // (Opcional). Al guardar se validan las dos, aunque solo una se vea.
      pestanas: const [
        PestanaFormulario('obligatorio', 'Obligatorio', icono: Icons.star),
        PestanaFormulario('opcional', 'Opcional', icono: Icons.tune),
      ],
      // Una sola fuente de reglas: esta MISMA lista llena el formulario y
      // se pasa a la importación de Excel (mismos límites y validaciones).
      campos: (_camposProducto = [
        // ── Obligatorio ────────────────────────────────────────────────
        const CampoFormulario(
          clave: 'nombre',
          etiqueta: 'Nombre *',
          pestana: 'obligatorio',
          obligatorio: true,
          minCaracteres: 2,
          maxCaracteres: 150,
        ),
        const CampoFormulario(
          clave: 'precioCompra',
          etiqueta: 'Precio de compra (Bs) *',
          pestana: 'obligatorio',
          tipo: TipoCampo.decimal,
          obligatorio: true,
          min: 0.01,
          max: 99999999.99,
        ),
        const CampoFormulario(
          clave: 'precioVenta',
          etiqueta: 'Precio de venta (Bs) *',
          pestana: 'obligatorio',
          tipo: TipoCampo.decimal,
          obligatorio: true,
          min: 0.01,
          max: 99999999.99,
          auxiliar: 'Debe ser mayor que 0 y no menor al de compra',
        ),
        // Calculadora al lado del precio: o se escribe el precio a mano o
        // se escribe el % de ganancia sobre el precio de compra y el precio
        // sale solo. No viaja al backend.
        const CampoFormulario(
          clave: 'gananciaPct',
          etiqueta: 'Ganancia %',
          pestana: 'obligatorio',
          tipo: TipoCampo.porcentaje,
          min: 0,
          max: 999,
          porcentajeSobre: 'precioCompra',
          porcentajeDestino: 'precioVenta',
          auxiliar: 'Precio de compra + %',
        ),
        const CampoFormulario(
          clave: 'stock',
          etiqueta: 'Stock *',
          pestana: 'obligatorio',
          tipo: TipoCampo.decimal,
          obligatorio: true,
          min: 0,
          max: 999999.999,
          // 3 cifras: con `KG` da precisión de gramo.
          decimales: 3,
          auxiliar: 'En la unidad de venta que elijas más abajo',
        ),
        CampoFormulario(
          clave: 'unidad',
          etiqueta: 'Unidad de venta *',
          pestana: 'obligatorio',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          // El catálogo de «Unidades» decide qué se puede vender y con
          // cuántos decimales; si todavía no está cargado (sin sesión o API
          // caída) se cae a la lista fija para no bloquear el alta.
          opcionesDinamicas: () => unidades.items.isEmpty
              ? unidadesVenta
              : unidadesDe(unidades.items),
          auxiliar: 'También define los decimales de la cantidad en el carrito',
        ),
        const CampoFormulario(
          clave: 'estado',
          etiqueta: 'Estado *',
          pestana: 'obligatorio',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          opciones: estadosProducto,
        ),
        // ── Opcional ───────────────────────────────────────────────────
        // Colores: las variaciones del producto, en filas `color ·
        // cantidad`. No todos los productos las llevan, así que es
        // opcional: sin filas se vende como unidad simple (variante
        // «Único»); con filas, el stock es la suma de las que haya.
        CampoFormulario(
          clave: 'variantes',
          etiqueta: 'Colores (stock por variante)',
          pestana: 'opcional',
          tipo: TipoCampo.variantes,
          auxiliar:
              'Sin filas = unidad (variante «Único»). Con colores, el stock '
              'del producto es la suma de las filas.',
        ),
        const CampoFormulario(
          clave: 'codigo',
          etiqueta: 'Código',
          pestana: 'opcional',
          maxCaracteres: 60,
          auxiliar: 'Interno o de barras · vacío = sin código',
        ),
        const CampoFormulario(
          clave: 'descripcion',
          etiqueta: 'Descripción',
          pestana: 'opcional',
          maxCaracteres: 255,
          maximasLineas: 4,
          auxiliar: 'Qué es o para qué sirve · vacío = sin descripción',
        ),
        const CampoFormulario(
          clave: 'precioRebaja',
          etiqueta: 'Máximo a rebajar por unidad (Bs)',
          pestana: 'opcional',
          tipo: TipoCampo.decimal,
          min: 0,
          max: 99999999.99,
          auxiliar: 'Vacío = sin límite · 0 = no se puede rebajar',
        ),
        const CampoFormulario(
          clave: 'stockMinimo',
          etiqueta: 'Stock mínimo',
          pestana: 'opcional',
          tipo: TipoCampo.decimal,
          min: 0,
          max: 999999.999,
          decimales: 3,
          auxiliar: 'Vacío = usar el umbral global de «Ajustes»',
        ),
        CampoFormulario(
          clave: 'fechaVencimiento',
          etiqueta: 'Fecha de vencimiento',
          pestana: 'opcional',
          tipo: TipoCampo.fecha,
          minFecha: _hoy(),
          auxiliar: 'No puede ser anterior a hoy',
        ),
        // Categoría, presentación y marca: los tres catálogos son
        // obligatorios (el formulario no deja guardar sin ellos y la API
        // también los exige en el alta y en toda edición que los traiga).
        CampoFormulario(
          clave: 'categoriaId',
          etiqueta: 'Categoría *',
          pestana: 'obligatorio',
          obligatorio: true,
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(categorias.items),
          // Crear una categoría sobre la marcha, sin salir del formulario.
          etiquetaCrear: 'Nueva categoría',
          onCrear: (nombre) async =>
              '${(await categorias.crear({'nombre': nombre})).id}',
        ),
        CampoFormulario(
          clave: 'presentacionId',
          etiqueta: 'Presentación *',
          pestana: 'obligatorio',
          obligatorio: true,
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(presentaciones.items),
          etiquetaCrear: 'Nueva presentación',
          onCrear: (nombre) async =>
              '${(await presentaciones.crear({'nombre': nombre})).id}',
        ),
        // Marca en texto (023), obligatoria; se imprime solo en el
        // Recibo 1 de la orden.
        CampoFormulario(
          clave: 'marcaId',
          etiqueta: 'Marca *',
          pestana: 'obligatorio',
          obligatorio: true,
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(marcas.items),
          etiquetaCrear: 'Nueva marca',
          onCrear: (nombre) async =>
              '${(await marcas.crear({'nombre': nombre})).id}',
        ),
        // Meses de garantía: presets; «— Sin asignar —» envía `null`
        // (sin garantía). Solo se muestra en la ficha del producto.
        CampoFormulario(
          clave: 'garantiaMeses',
          etiqueta: 'Garantía',
          pestana: 'opcional',
          tipo: TipoCampo.opcion,
          opciones: _garantias,
          auxiliar: 'Sin asignar = sin garantía · se ve solo en la ficha',
        ),
        CampoFormulario(
          clave: 'proveedorId',
          etiqueta: 'Proveedor',
          pestana: 'opcional',
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(proveedores.items),
          etiquetaCrear: 'Nuevo proveedor',
          onCrear: (nombre) async =>
              '${(await proveedores.crear({'nombre': nombre})).id}',
        ),
        const CampoFormulario(
          clave: 'imagen',
          etiqueta: 'Imagen del producto',
          pestana: 'opcional',
          tipo: TipoCampo.imagen,
          auxiliar: 'PNG, JPG, GIF o WebP · máx. 3 MB',
        ),
      ]),
      // Reglas entre campos: la venta nunca baja del coste y el máximo a
      // rebajar nunca supera el precio de venta (mismos 400 que la API).
      validar: (valores) =>
          rebajaNoMayorQueVenta(
            valores['precioRebaja'],
            valores['precioVenta'],
          ) ??
          ventaNoMenorQueCoste(valores['precioVenta'], valores['precioCompra']),
    );
  }

  /// Abre la importación masiva con los MISMOS campos que el formulario y
  /// recarga la lista si algo se creó (los 3 pasos del diálogo).
  Future<void> _importarExcel(BuildContext context) async {
    final campos = _camposProducto;
    if (campos == null) return;
    // El controller se toma ANTES de la espera: no puede usarse el
    // contexto después de un `await`.
    final productos = context.read<ProductosController>();
    final importado = await mostrarImportarExcel(
      context,
      campos: campos,
      categorias: context.read<CategoriasController>(),
      presentaciones: context.read<PresentacionesController>(),
      marcas: context.read<MarcasController>(),
      proveedores: context.read<ProveedoresController>(),
    );
    if (importado == true && mounted) {
      await productos.recargar();
    }
  }

  /// Hoy a medianoche, para que el calendario no permita fechas vencidas.
  static DateTime _hoy() {
    final ahora = DateTime.now();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  /// Presets de garantía (meses) del desplegable: la opción vacía que el
  /// formulario añade solo («— Sin asignar —») es «sin garantía» y envía
  /// `garantiaMeses: null` (también al editar, que así la quita).
  static const _garantias = [
    Opccion('3', '3 meses'),
    Opccion('6', '6 meses'),
    Opccion('12', '12 meses'),
    Opccion('18', '18 meses'),
    Opccion('24', '24 meses'),
    Opccion('36', '36 meses'),
    Opccion('48', '48 meses'),
    Opccion('60', '60 meses'),
  ];

  /// Desplegable «Marca» junto a los chips del buscador: filtra la tabla en
  /// el servidor (`?marcaId=`; `null` lo quita). Se repinta con el
  /// controlador de productos (ahí vive el filtro) y con el de marcas (el
  /// catálogo se carga tarde, tras el primer frame). La marca elegida que
  /// no esté en la lista cargada se conserva a mano para que el selector
  /// no quede con un valor fuera de sus opciones.
  Widget _filtroMarca(ProductosController productos, MarcasController marcas) {
    return ListenableBuilder(
      listenable: Listenable.merge([productos, marcas]),
      builder: (context, _) {
        final actual = productos.filtrosListado?['marcaId'];
        var opciones = opcionesDe(marcas.items);
        if (actual != null &&
            actual.isNotEmpty &&
            !opciones.any((o) => o.valor == actual)) {
          opciones = [
            ...opciones,
            Opccion(actual, nombreDe(marcas.items, int.tryParse(actual))),
          ];
        }
        // Clave con el valor: un `FormField` solo lee `initialValue` al
        // montarse, y hay que repintar cuando cambia el filtro elegido.
        return SizedBox(
          width: 210,
          child: DesplegableBuscable(
            key: ValueKey('marcaFiltro#${actual ?? ''}'),
            initialValue: actual ?? '',
            onChanged: (valor) => productos.filtrarPorMarca(
              valor == null || valor.isEmpty ? null : int.tryParse(valor),
            ),
            opciones: [const Opccion('', 'Todas las marcas'), ...opciones],
            decoracion: const InputDecoration(
              labelText: 'Marca',
              isDense: true,
              filled: true,
              fillColor: AppColors.cardBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide(color: AppColors.cardBorder),
              ),
            ),
          ),
        );
      },
    );
  }

  /// `12.75 KG`, `15 UN`: el stock ya es fraccionado, así que se recortan
  /// los ceros de relleno y se añade la unidad de venta del producto.
  static String _stockConUnidad(Recurso r) =>
      '${cantidadTexto(r.numero('stock') ?? 0)} '
      '${r.texto('unidad', vacio: 'UN')}';

  static String _dinero(Recurso r) {
    final precio = r.numero('precioVenta');
    return precio == null ? '—' : precio.toStringAsFixed(2);
  }
}
