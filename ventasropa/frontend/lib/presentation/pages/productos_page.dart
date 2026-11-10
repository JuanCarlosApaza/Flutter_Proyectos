import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permisos.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validation/reglas.dart';
import '../../core/widgets/sesion_scope.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
import '../widgets/importar_excel_dialog.dart';
import '../widgets/opciones_formulario.dart';
import '../widgets/recurso_contenido.dart';
import '../widgets/recurso_form.dart';
import '../widgets/recurso_tabla.dart';
import '../widgets/variantes_alta.dart';
import '../widgets/variantes_editor.dart';
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
  @override
  void initState() {
    super.initState();
    // Los combos (categorías, proveedores, tallas y colores) se cargan
    // aparte, tras el primer frame (la utilidad difiere la carga ella sola).
    precargarDespuesDelPrimerFrame(context, [
      context.read<CategoriasController>(),
      context.read<MarcasController>(),
      context.read<ProveedoresController>(),
      context.read<TallasController>(),
      context.read<ColoresController>(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final categorias = context.read<CategoriasController>();
    final marcas = context.read<MarcasController>();
    final proveedores = context.read<ProveedoresController>();
    final tallas = context.read<TallasController>();
    final colores = context.read<ColoresController>();

    final productos = context.read<ProductosController>();

    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Productos',
      controller: productos,
      tituloSeccion: 'Gestión de Productos',
      etiquetaNuevo: 'Nuevo Producto',
      // Carga masiva desde Excel, con el mismo permiso que el alta manual.
      complementoCabecera: _botonImportar(context, productos),
      entidad: 'producto',
      textoVacio: 'No hay productos registrados',
      mensajeCreado:
          'Producto creado: con sus tallas y colores, o como «Única» si no '
          'tiene. Su stock vive en cada variante: ajústalo cuando quieras '
          'con el botón de la fila.',
      filtros: const [
        FiltroEstado('DISPONIBLE', 'Disponibles'),
        FiltroEstado('AGOTADO', 'Agotados'),
        FiltroEstado('DESCONTINUADO', 'Descontinuados'),
      ],
      // El botón de tallas abre el editor de variantes: ahí vive el stock.
      accionesExtras: (producto) => [
        IconButton(
          tooltip: 'Tallas y colores (stock)',
          icon: const Icon(Icons.checkroom_outlined, size: 20),
          color: AppColors.brandGreen,
          onPressed: () => mostrarEditorVariantes(context, producto),
        ),
      ],
      anchoAcciones: 144,
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
          clave: 'variantes',
          etiqueta: 'Tallas',
          flex: 2,
          formato: _tallasDe,
        ),
        const ColumnaTabla(
          clave: 'stock',
          etiqueta: 'Stock',
          flex: 1,
          formato: _stockEntero,
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
      campos: [
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
        CampoFormulario(
          clave: 'categoriaId',
          etiqueta: 'Categoría *',
          pestana: 'obligatorio',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          opcionesDinamicas: () => opcionesDe(categorias.items),
          // Crear una categoría sobre la marcha, sin salir del formulario.
          etiquetaCrear: 'Nueva categoría',
          onCrear: (nombre) async =>
              '${(await categorias.crear({'nombre': nombre})).id}',
        ),
        // Marca opcional: una prenda puede quedar sin ella.
        CampoFormulario(
          clave: 'marcaId',
          etiqueta: 'Marca',
          pestana: 'opcional',
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(marcas.items),
          etiquetaCrear: 'Nueva marca',
          onCrear: (nombre) async =>
              '${(await marcas.crear({'nombre': nombre})).id}',
          auxiliar: 'Vacío = sin marca',
        ),
        CampoFormulario(
          clave: 'proveedorId',
          etiqueta: 'Proveedor *',
          pestana: 'obligatorio',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          opcionesDinamicas: () => opcionesDe(proveedores.items),
          etiquetaCrear: 'Nuevo proveedor',
          onCrear: (nombre) async =>
              '${(await proveedores.crear({'nombre': nombre})).id}',
        ),
        // Tallas y colores escritos a mano: cada fila es una variante con su
        // cantidad y se guardan junto con el producto. Los catálogos están
        // vacíos al principio, así que el propio campo da de alta lo que se
        // escriba («Nueva talla» / «Nuevo color»), igual que «Nueva categoría».
        // **Sin filas** el producto es «sin tallas» (medias, gorros...): el
        // backend le crea la variante única «Única» / «Único» con el stock.
        CampoFormulario(
          clave: 'variantes',
          etiqueta: 'Tallas y colores',
          pestana: 'obligatorio',
          tipo: TipoCampo.variantes,
          soloEnCreacion: true,
          auxiliar:
              '¿Tiene tallas? Añade filas (S, M, XXL, 38...). '
              '¿No tiene (medias, gorros...)? Déjalo vacío y se guardará '
              'como «Única».',
          configVariantes: ConfigVariantesAlta(
            tallas: () => _opcionesCatalogo(tallas.items),
            colores: () => _opcionesCatalogo(colores.items),
            crearTalla: (nombre) async => (await altaEnCatalogo(
              tallas,
              nombre,
            )).texto('nombre', vacio: nombre),
            crearColor: (nombre) async => (await altaEnCatalogo(
              colores,
              nombre,
            )).texto('nombre', vacio: nombre),
          ),
        ),
        // La cantidad que entra. Obligatorio en el alta: sin filas de
        // variantes es el stock de la variante «Única» (medias, gorros...);
        // con filas el backend lo ignora y el stock real lo da cada fila.
        const CampoFormulario(
          clave: 'stock',
          etiqueta: 'Stock inicial *',
          pestana: 'obligatorio',
          tipo: TipoCampo.decimal,
          obligatorio: true,
          soloEnCreacion: true,
          min: 0,
          max: 999999.999,
          decimales: 3,
          auxiliar:
              'La cantidad que entra · con filas de tallas el stock '
              'real lo da cada fila',
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
          maxCaracteres: 2000,
          maximasLineas: 4,
          auxiliar:
              'Notas, materiales, cuidados, temporada... · vacío = '
              'sin descripción',
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
          max: 999999,
          decimales: 0,
          auxiliar: 'Vacío = usar el umbral global de «Ajustes»',
        ),
        const CampoFormulario(
          clave: 'imagen',
          etiqueta: 'Imagen del producto',
          pestana: 'opcional',
          tipo: TipoCampo.imagen,
          auxiliar: 'PNG, JPG, GIF o WebP · máx. 3 MB',
        ),
      ],
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

  /// Botón «Importar Excel» (bajo el encabezado): solo aparece con el
  /// mismo permiso que el alta manual y, al terminar, recarga el listado.
  Widget? _botonImportar(BuildContext context, ProductosController productos) {
    final sesion = SesionScope.de(context);
    if (sesion != null && !sesion.puede(Modulos.productos, Acciones.crear)) {
      return null;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () =>
            mostrarImportadorExcel(context, onImportado: productos.recargar),
        icon: const Icon(Icons.file_upload_outlined, size: 18),
        label: const Text('Importar Excel'),
      ),
    );
  }

  /// Opciones de un catálogo (tallas/colores) para los desplegables del
  /// campo de variantes: valor y etiqueta son el **nombre**, que es lo que
  /// viaja a la API. Los ocultos (`ELIMINADO`) no se enseñan.
  static List<Opccion> _opcionesCatalogo(List<Recurso> items) {
    final opciones = [
      for (final item in items)
        if (item.texto('estado') != 'ELIMINADO' &&
            item.texto('nombre', vacio: '').isNotEmpty)
          Opccion(
            item.texto('nombre', vacio: ''),
            item.texto('nombre', vacio: ''),
          ),
    ];
    opciones.sort((a, b) => a.etiqueta.compareTo(b.etiqueta));
    return opciones;
  }

  /// «5 tallas» (o «Sin tallas»): el número de variantes con stock visible
  /// que trae el producto en el listado.
  static String _tallasDe(Recurso r) {
    final crudo = r.datos['variantes'];
    if (crudo is! List || crudo.isEmpty) return 'Sin tallas';
    final visibles = crudo
        .whereType<Map>()
        .where((v) => v['estado'] != 'ELIMINADO')
        .length;
    return visibles == 0 ? 'Sin tallas' : '$visibles tallas';
  }

  /// Stock en unidades enteras (el agregado de las variantes).
  static String _stockEntero(Recurso r) =>
      '${(r.numero('stock') ?? 0).toInt()} UN';

  static String _dinero(Recurso r) {
    final precio = r.numero('precioVenta');
    return precio == null ? '—' : precio.toStringAsFixed(2);
  }
}
