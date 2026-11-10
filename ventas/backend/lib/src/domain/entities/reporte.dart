/// Ventas agregadas de un producto (modelo puro de dominio).
///
/// Es lo que devuelve el reporte del dashboard al agrupar
/// `detalles_ordenes_pedidos` por producto: cuántas unidades se han vendido y
/// qué monto han generado.
///
/// Solo cuentan las líneas de órdenes **no anuladas** (`PENDIENTE` y
/// `PAGADO`): las canceladas o devueltas no son ventas.
final class VentaProducto {
  const VentaProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
  });

  /// Fila `{"productoId": 7, ...}` -> entidad.
  factory VentaProducto.fromJson(Map<String, Object?> json) => VentaProducto(
    productoId: json['productoId'] is int
        ? json['productoId'] as int
        : int.tryParse('${json['productoId']}') ?? 0,
    nombre: '${json['nombre'] ?? ''}',
    unidades: json['unidades'] is num
        ? (json['unidades'] as num).toDouble()
        : double.tryParse('${json['unidades']}') ?? 0,
    monto: json['monto'] is num
        ? (json['monto'] as num).toDouble()
        : double.tryParse('${json['monto']}') ?? 0,
  );

  final int productoId;

  /// Nombre del producto tal y como lo muestra el dashboard.
  final String nombre;

  /// Cantidad vendida (suma de `cantidad`): fraccionada, `12.75 KG`.
  final double unidades;

  /// Importe generado (suma de `monto_total`), en soles.
  final double monto;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'nombre': nombre,
    'unidades': unidades,
    'monto': monto,
  };
}

/// Resumen del rango consultado (las tarjetas KPI de «Reportes»).
///
/// No es una fila de la BD: el servidor lo derive **sumando la serie** que
/// devuelve, de modo que la fila «Total del rango» de la tabla siempre
/// cuadra con los KPI de arriba (mismo origen, misma cifra).
final class ResumenVentas {
  const ResumenVentas({
    required this.total,
    required this.ordenes,
    required this.unidades,
    this.utilidad = 0,
  });

  Map<String, Object?> toJson() => {
    'total': total,
    'ordenes': ordenes,
    'unidades': unidades,
    'utilidad': utilidad,
  };

  /// Facturación del rango, en Bs.
  final double total;

  /// Órdenes pagadas incluidas en el rango.
  final int ordenes;

  /// Unidades vendidas (fraccionadas: `12.750`).
  final double unidades;

  /// Utilidad del rango (`monto_total − costo×cantidad`) solo de las líneas
  /// con `costo_unitario` conocido, en Bs: las líneas antiguas sin costo no
  /// aportan ni restan.
  final double utilidad;
}

/// Un periodo de la serie (`2026-10-01`, `2026-10` o `2026`).
///
/// La etiqueta la genera **el servidor** en la hora local del negocio: el
/// cliente solo rellena los huecos del rango con ceros para que el gráfico
/// muestre también los días sin ventas.
final class PeriodoVenta {
  const PeriodoVenta({
    required this.etiqueta,
    required this.ordenes,
    required this.total,
    required this.unidades,
    this.utilidad = 0,
  });

  final String etiqueta;
  final int ordenes;
  final double total;
  final double unidades;

  /// Utilidad del periodo (solo líneas con costo conocido, ver
  /// [ResumenVentas.utilidad]).
  final double utilidad;

  Map<String, Object?> toJson() => {
    'etiqueta': etiqueta,
    'ordenes': ordenes,
    'total': total,
    'unidades': unidades,
    'utilidad': utilidad,
  };
}

/// Informe de ventas de un rango: resumen + serie de periodos con ventas.
///
/// El servidor devuelve **solo los periodos con ventas**; los huecos los
/// rellena el cliente con ceros.
final class InformeVentas {
  const InformeVentas({required this.resumen, required this.serie});

  /// Construye el informe derivando el resumen de la serie: así los KPI y la
  /// fila de total de la tabla proceden del mismo cálculo y no pueden
  /// descuadrar.
  factory InformeVentas.resumiendo(List<PeriodoVenta> serie) {
    var total = 0.0;
    var unidades = 0.0;
    var utilidad = 0.0;
    var ordenes = 0;
    for (final periodo in serie) {
      total += periodo.total;
      unidades += periodo.unidades;
      utilidad += periodo.utilidad;
      ordenes += periodo.ordenes;
    }
    return InformeVentas(
      resumen: ResumenVentas(
        total: total,
        ordenes: ordenes,
        unidades: unidades,
        utilidad: utilidad,
      ),
      serie: serie,
    );
  }

  final ResumenVentas resumen;
  final List<PeriodoVenta> serie;

  Map<String, Object?> toJson() => {
    'resumen': resumen.toJson(),
    'serie': [for (final periodo in serie) periodo.toJson()],
  };
}

/// Producto del ranking de un rango, con su categoría (`null` = producto
/// sin categoría).
final class ProductoRango {
  const ProductoRango({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
    required this.categoria,
  });

  final int productoId;
  final String nombre;

  /// Unidades vendidas: fraccionadas (`12.750 KG`).
  final double unidades;

  /// Importe generado, en Bs.
  final double monto;

  /// Nombre de la categoría o `null` si el producto no tiene.
  final String? categoria;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'nombre': nombre,
    'unidades': unidades,
    'monto': monto,
    'categoria': categoria,
  };
}

/// Reparto de un rango por categoría (monto + unidades; el % lo calcula la
/// pantalla sobre el total del rango).
final class VentaCategoria {
  const VentaCategoria({
    required this.nombre,
    required this.monto,
    required this.unidades,
  });

  /// `null` cuando la venta fue de un producto sin categoría.
  final String? nombre;
  final double monto;
  final double unidades;

  Map<String, Object?> toJson() => {
    'nombre': nombre,
    'monto': monto,
    'unidades': unidades,
  };
}

/// Ranking de productos de un rango + reparto por categorías.
final class InformeProductos {
  const InformeProductos({required this.productos, required this.categorias});

  final List<ProductoRango> productos;
  final List<VentaCategoria> categorias;

  Map<String, Object?> toJson() => {
    'productos': [for (final producto in productos) producto.toJson()],
    'categorias': [for (final categoria in categorias) categoria.toJson()],
  };
}
