/// Ventas agregadas de un producto (modelo puro de dominio).
///
/// Es lo que devuelve el reporte del dashboard al agrupar
/// `detalles_ordenes_pedidos` por producto: cuántas unidades se han vendido y
/// qué monto han generado.
///
/// Solo cuentan las líneas de órdenes **no anuladas** (`PENDIENTE` y
/// `PAGADO`): las canceladas o devueltas no son ventas. El informe por
/// rango de fechas es aún más estricto y solo incluye `PAGADO`.
final class VentaProducto {
  const VentaProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
    this.varianteId,
    this.talla,
    this.color,
    this.categoria,
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
    varianteId: json['varianteId'] is int
        ? json['varianteId'] as int
        : int.tryParse('${json['varianteId']}'),
    talla: json['talla']?.toString(),
    color: json['color']?.toString(),
    categoria: json['categoria']?.toString(),
  );

  final int productoId;

  /// Nombre del producto tal y como lo muestra el dashboard.
  final String nombre;

  /// Cantidad vendida (suma de `cantidad`), en unidades.
  final double unidades;

  /// Importe generado (suma de `monto_total`), en bolivianos.
  final double monto;

  /// Relleno solo en el ranking `porVariante`: variante (talla + color) a la
  /// que pertenece la cifra; `null` en el ranking por producto.
  final int? varianteId;
  final String? talla;
  final String? color;

  /// Categoría del producto; solo la rellena el informe por rango de fechas
  /// (`GET /reportes/ventas-productos`), que es quien hace el `JOIN`.
  final String? categoria;

  Map<String, Object?> toJson() => {
    'productoId': productoId,
    'nombre': nombre,
    'unidades': unidades,
    'monto': monto,
    'varianteId': varianteId,
    'talla': talla,
    'color': color,
    'categoria': categoria,
  };
}

/// Ventas de un periodo concreto de la serie del informe (día, mes o año).
///
/// `etiqueta` es el agrupador tal y como lo calcula la BD en **hora de
/// Bolivia**: `2026-10-01` (día), `2026-10` (mes) o `2026` (año).
final class VentaPeriodo {
  const VentaPeriodo({
    required this.etiqueta,
    required this.ordenes,
    required this.total,
    required this.unidades,
  });

  /// Periodo (`2026-10-01`, `2026-10` o `2026`).
  final String etiqueta;

  /// Órdenes pagadas dentro del periodo.
  final int ordenes;

  /// Importe bruto cobrado (suma del `total` de las órdenes), en bolivianos.
  final double total;

  /// Unidades vendidas (suma de `cantidad` de sus líneas).
  final double unidades;

  Map<String, Object?> toJson() => {
    'etiqueta': etiqueta,
    'ordenes': ordenes,
    'total': total,
    'unidades': unidades,
  };
}

/// Cifras de cabecera del rango completo del informe: la suma de toda la
/// serie, más el ticket medio (total / nº de órdenes).
final class ResumenVentas {
  const ResumenVentas({
    required this.total,
    required this.ordenes,
    required this.unidades,
  });

  final double total;
  final int ordenes;
  final double unidades;

  /// Importe medio de una orden (`0` si no hubo ventas).
  double get ticketMedio => ordenes == 0 ? 0 : total / ordenes;

  Map<String, Object?> toJson() => {
    'total': total,
    'ordenes': ordenes,
    'unidades': unidades,
    'ticketMedio': ticketMedio,
  };
}

/// Informe «ventas por día / mes / año»: el rango pedido, su resumen y la
/// serie ya agregada (una fila por periodo con ventas).
///
/// Los periodos **sin ventas** no viajan: el frontend los rellena con ceros
/// para que el gráfico muestre los huecos del rango.
final class InformeVentas {
  const InformeVentas({
    required this.desde,
    required this.hasta,
    required this.agrupacion,
    required this.resumen,
    required this.serie,
  });

  /// Primer día del rango (`yyyy-MM-dd`, inclusive).
  final String desde;

  /// Último día del rango (`yyyy-MM-dd`, inclusive).
  final String hasta;

  /// `dia`, `mes` o `anio`.
  final String agrupacion;

  final ResumenVentas resumen;
  final List<VentaPeriodo> serie;

  Map<String, Object?> toJson() => {
    'desde': desde,
    'hasta': hasta,
    'agrupacion': agrupacion,
    'resumen': resumen.toJson(),
    'serie': [for (final fila in serie) fila.toJson()],
  };
}

/// Ventas de una categoría dentro del rango (ranking por categoría).
final class VentaCategoria {
  const VentaCategoria({
    required this.nombre,
    required this.unidades,
    required this.monto,
  });

  final String nombre;
  final double unidades;
  final double monto;

  Map<String, Object?> toJson() => {
    'nombre': nombre,
    'unidades': unidades,
    'monto': monto,
  };
}

/// Informe «ventas por producto y categoría» de un rango de fechas.
///
/// Los productos vienen ordenados de mayor a menor importe (acotados en la
/// capa de casos de uso) y las categorías sin límite: son pocas.
final class InformeProductos {
  const InformeProductos({required this.productos, required this.categorias});

  final List<VentaProducto> productos;
  final List<VentaCategoria> categorias;

  Map<String, Object?> toJson() => {
    'productos': [for (final p in productos) p.toJson()],
    'categorias': [for (final c in categorias) c.toJson()],
  };
}
