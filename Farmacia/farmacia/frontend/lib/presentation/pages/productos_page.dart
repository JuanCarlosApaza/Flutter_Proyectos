import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/validation/reglas.dart';
import '../../domain/entities/recurso.dart';
import '../controllers/recurso_controller.dart';
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
  @override
  void initState() {
    super.initState();
    // Los combos (categorías, presentaciones, proveedores) se cargan aparte,
    // tras el primer frame (la utilidad difiere la carga ella sola).
    precargarDespuesDelPrimerFrame(context, [
      context.read<CategoriasController>(),
      context.read<PresentacionesController>(),
      context.read<ProveedoresController>(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final categorias = context.read<CategoriasController>();
    final presentaciones = context.read<PresentacionesController>();
    final proveedores = context.read<ProveedoresController>();

    return RecursoPage(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      tituloBarra: 'Productos',
      controller: context.read<ProductosController>(),
      tituloSeccion: 'Gestión de Productos',
      etiquetaNuevo: 'Nuevo Producto',
      entidad: 'producto',
      textoVacio: 'No hay productos registrados',
      filtros: const [
        FiltroEstado('DISPONIBLE', 'Disponibles'),
        FiltroEstado('AGOTADO', 'Agotados'),
        FiltroEstado('POR_VENCER', 'Por vencer'),
        FiltroEstado('DESCONTINUADO', 'Descontinuados'),
      ],
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
        const ColumnaTabla(clave: 'stock', etiqueta: 'Stock', flex: 1),
        const ColumnaTabla(
          clave: 'estado',
          etiqueta: 'Estado',
          flex: 2,
          chip: true,
        ),
      ],
      campos: [
        const CampoFormulario(
          clave: 'nombre',
          etiqueta: 'Nombre *',
          obligatorio: true,
          minCaracteres: 2,
          maxCaracteres: 150,
        ),
        const CampoFormulario(
          clave: 'precioVenta',
          etiqueta: 'Precio de venta (Bs) *',
          tipo: TipoCampo.decimal,
          obligatorio: true,
          min: 0.01,
          max: 99999999.99,
          auxiliar: 'Debe ser mayor que 0 y no menor al de compra',
        ),
        const CampoFormulario(
          clave: 'precioCompra',
          etiqueta: 'Precio de compra (Bs)',
          tipo: TipoCampo.decimal,
          min: 0,
          max: 99999999.99,
        ),
        const CampoFormulario(
          clave: 'precioRebaja',
          etiqueta: 'Máximo a rebajar por unidad (Bs)',
          tipo: TipoCampo.decimal,
          min: 0,
          max: 99999999.99,
          auxiliar: 'Vacío = sin límite · 0 = no se puede rebajar',
        ),
        const CampoFormulario(
          clave: 'stock',
          etiqueta: 'Stock *',
          tipo: TipoCampo.numero,
          obligatorio: true,
          min: 0,
          max: 1000000,
        ),
        CampoFormulario(
          clave: 'fechaVencimiento',
          etiqueta: 'Fecha de vencimiento',
          tipo: TipoCampo.fecha,
          minFecha: _hoy(),
          auxiliar: 'No puede ser anterior a hoy',
        ),
        CampoFormulario(
          clave: 'categoriaId',
          etiqueta: 'Categoría',
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(categorias.items),
          // Crear una categoría sobre la marcha, sin salir del formulario.
          etiquetaCrear: 'Nueva categoría',
          onCrear: (nombre) async =>
              '${(await categorias.crear({'nombre': nombre})).id}',
        ),
        CampoFormulario(
          clave: 'presentacionId',
          etiqueta: 'Presentación',
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(presentaciones.items),
          etiquetaCrear: 'Nueva presentación',
          onCrear: (nombre) async =>
              '${(await presentaciones.crear({'nombre': nombre})).id}',
        ),
        CampoFormulario(
          clave: 'proveedorId',
          etiqueta: 'Proveedor',
          tipo: TipoCampo.opcion,
          opcionesDinamicas: () => opcionesDe(proveedores.items),
          etiquetaCrear: 'Nuevo proveedor',
          onCrear: (nombre) async =>
              '${(await proveedores.crear({'nombre': nombre})).id}',
        ),
        const CampoFormulario(
          clave: 'estado',
          etiqueta: 'Estado *',
          tipo: TipoCampo.opcion,
          obligatorio: true,
          opciones: estadosProducto,
        ),
        const CampoFormulario(
          clave: 'imagen',
          etiqueta: 'Imagen del producto',
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

  /// Hoy a medianoche, para que el calendario no permita fechas vencidas.
  static DateTime _hoy() {
    final ahora = DateTime.now();
    return DateTime(ahora.year, ahora.month, ahora.day);
  }

  static String _dinero(Recurso r) {
    final precio = r.numero('precioVenta');
    return precio == null ? '—' : precio.toStringAsFixed(2);
  }
}
