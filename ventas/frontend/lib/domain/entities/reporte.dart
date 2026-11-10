import '../../core/errors/failure.dart';

/// Producto con sus ventas agregadas (ranking del dashboard).
///
/// Es lo que devuelve `GET /api/v1/reportes/productos-vendidos`: un resumen
/// calculado por el servidor agrupando las líneas de las órdenes, no una fila
/// de un CRUD (por eso tiene su propio camino en vez de usar `Recurso`).
final class VentaProducto {
  const VentaProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
  });

  factory VentaProducto.fromJson(Map<String, dynamic> json) {
    final productoId = json['productoId'];
    final unidades = json['unidades'];
    if (productoId is! num || unidades is! num) throw const ParsingFailure();
    return VentaProducto(
      productoId: productoId.toInt(),
      nombre: '${json['nombre'] ?? ''}',
      unidades: unidades.toDouble(),
      monto: json['monto'] is num
          ? (json['monto'] as num).toDouble()
          : double.tryParse('${json['monto']}') ?? 0,
    );
  }

  final int productoId;
  final String nombre;

  /// Cantidad vendida (solo órdenes no anuladas): fraccionada, `12.75 KG`.
  final double unidades;

  /// Importe generado, en Bs.
  final double monto;
}

/// Las tarjetas KPI del informe de ventas.
///
/// El servidor lo deriva sumando la propia serie, así que el «Total vendido»
/// y la fila «Total del rango» de la tabla coinciden siempre. El ticket
/// medio no viaja en la respuesta: se calcula aquí ([ticketMedio]).
final class ResumenVentas {
  const ResumenVentas({
    required this.total,
    required this.ordenes,
    required this.unidades,
    this.utilidad = 0,
  });

  factory ResumenVentas.fromJson(Map<String, dynamic> json) {
    final ordenes = json['ordenes'];
    if (ordenes is! num) throw const ParsingFailure();
    return ResumenVentas(
      total: _decimal(json['total']),
      ordenes: ordenes.toInt(),
      unidades: _decimal(json['unidades']),
      utilidad: _decimal(json['utilidad']),
    );
  }

  /// Facturación del rango, en Bs.
  final double total;

  /// Órdenes PAGADAS del rango.
  final int ordenes;

  /// Unidades vendidas; fraccionada (`12.750`).
  final double unidades;

  /// Utilidad del rango en Bs: `monto_total − costo × cantidad` solo de las
  /// líneas con `costo_unitario` conocido (las líneas antiguas sin costo no
  /// aportan ni restan).
  final double utilidad;

  /// Facturación media por orden (0 si no hay órdenes).
  double get ticketMedio => ordenes == 0 ? 0 : total / ordenes;
}

/// Un periodo con ventas (`2026-10-01`, `2026-10` o `2026`).
///
/// La etiqueta la formatea el **servidor** en la hora local del negocio: aquí
/// solo se leen. Los periodos sin ventas no llegan (los rellena
/// [InformeVentas.conHuecos]).
final class PeriodoVenta {
  const PeriodoVenta({
    required this.etiqueta,
    required this.ordenes,
    required this.total,
    required this.unidades,
    this.utilidad = 0,
  });

  factory PeriodoVenta.fromJson(Map<String, dynamic> json) {
    final ordenes = json['ordenes'];
    final etiqueta = json['etiqueta'];
    if (ordenes is! num || etiqueta is! String) throw const ParsingFailure();
    return PeriodoVenta(
      etiqueta: etiqueta,
      ordenes: ordenes.toInt(),
      total: _decimal(json['total']),
      unidades: _decimal(json['unidades']),
      utilidad: _decimal(json['utilidad']),
    );
  }

  final String etiqueta;
  final int ordenes;
  final double total;
  final double unidades;

  /// Utilidad del periodo (solo líneas con costo conocido, ver
  /// [ResumenVentas.utilidad]).
  final double utilidad;
}

/// Informe de ventas de un rango: resumen + serie.
///
/// `GET /api/v1/reportes/ventas?desde=&hasta=&agrupacion=`.
final class InformeVentas {
  const InformeVentas({required this.resumen, required this.serie});

  factory InformeVentas.fromJson(Map<String, dynamic> json) {
    final resumen = json['resumen'];
    final serie = json['serie'];
    if (resumen is! Map<String, dynamic> || serie is! List) {
      throw const ParsingFailure();
    }
    return InformeVentas(
      resumen: ResumenVentas.fromJson(resumen),
      serie: [
        for (final periodo in serie.whereType<Map<String, dynamic>>())
          PeriodoVenta.fromJson(periodo),
      ],
    );
  }

  final ResumenVentas resumen;

  /// Solo los periodos con ventas, tal y como los manda el servidor.
  final List<PeriodoVenta> serie;

  /// Devuelve la serie **completa**: cada periodo de [desde] a [hasta] con
  /// [agrupacion], rellenando con ceros los que no tuvieron ventas.
  ///
  /// El gráfico y la tabla tienen que mostrar también los huecos (un día en
  /// blanco se ve; un hueco en medio de la línea se ve como un salto a cero
  /// que en realidad no ocurrió — por eso el servidor no los manda y el
  /// relleno es aquí, con la misma convención de fechas).
  InformeVentas conHuecos({
    required DateTime desde,
    required DateTime hasta,
    required String agrupacion,
  }) {
    final porEtiqueta = {
      for (final periodo in serie) periodo.etiqueta: periodo,
    };
    final completo = <PeriodoVenta>[];

    var actual = DateTime(desde.year, desde.month, desde.day);
    final fin = DateTime(hasta.year, hasta.month, hasta.day);
    // Estructuras de control: al día se le suma 1 al `day` (no 24 h) y al
    // mes/año se cambia de componente, para no caer en los saltos de hora.
    while (!actual.isAfter(fin)) {
      final etiqueta = _etiqueta(actual, agrupacion);
      completo.add(
        porEtiqueta[etiqueta] ??
            PeriodoVenta(etiqueta: etiqueta, ordenes: 0, total: 0, unidades: 0),
      );
      actual = switch (agrupacion) {
        'mes' => DateTime(actual.year, actual.month + 1, 1),
        'anio' => DateTime(actual.year + 1, 1, 1),
        _ => DateTime(actual.year, actual.month, actual.day + 1),
      };
    }
    // Red de seguridad: un periodo que el servidor mandara fuera del rango
    // pedido no se pierde.
    for (final periodo in serie) {
      if (!completo.any((e) => e.etiqueta == periodo.etiqueta)) {
        completo.add(periodo);
      }
    }
    return InformeVentas(resumen: resumen, serie: completo);
  }
}

/// Producto del ranking de un rango, con su categoría.
///
/// `GET /api/v1/reportes/ventas-productos?desde=&hasta=`.
final class ProductoRango {
  const ProductoRango({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
    required this.categoria,
  });

  factory ProductoRango.fromJson(Map<String, dynamic> json) {
    final productoId = json['productoId'];
    final unidades = json['unidades'];
    if (productoId is! num || unidades is! num) throw const ParsingFailure();
    return ProductoRango(
      productoId: productoId.toInt(),
      nombre: '${json['nombre'] ?? ''}',
      unidades: unidades.toDouble(),
      monto: _decimal(json['monto']),
      categoria: json['categoria'] == null ? null : '${json['categoria']}',
    );
  }

  final int productoId;
  final String nombre;

  /// Unidades vendidas en el rango; fraccionada (`12.750 KG`).
  final double unidades;

  /// Importe generado, en Bs.
  final double monto;

  /// Nombre de la categoría; `null` cuando el producto no tiene (la tabla lo
  /// pinta como «(sin categoría)»).
  final String? categoria;
}

/// Reparto del rango por categoría (monto + unidades; el % lo calcula la
/// pantalla sobre el total del rango).
final class VentaCategoria {
  const VentaCategoria({
    required this.nombre,
    required this.monto,
    required this.unidades,
  });

  factory VentaCategoria.fromJson(Map<String, dynamic> json) => VentaCategoria(
    nombre: json['nombre'] == null ? null : '${json['nombre']}',
    monto: _decimal(json['monto']),
    unidades: _decimal(json['unidades']),
  );

  final String? nombre;
  final double monto;
  final double unidades;
}

/// Respuesta de `ventas-productos`: ranking + reparto por categorías.
final class InformeProductos {
  const InformeProductos({required this.productos, required this.categorias});

  factory InformeProductos.fromJson(Map<String, dynamic> json) {
    final productos = json['productos'];
    final categorias = json['categorias'];
    if (productos is! List || categorias is! List) {
      throw const ParsingFailure();
    }
    return InformeProductos(
      productos: [
        for (final producto in productos.whereType<Map<String, dynamic>>())
          ProductoRango.fromJson(producto),
      ],
      categorias: [
        for (final categoria in categorias.whereType<Map<String, dynamic>>())
          VentaCategoria.fromJson(categoria),
      ],
    );
  }

  final List<ProductoRango> productos;
  final List<VentaCategoria> categorias;

  /// Ventana del ranking que se pinta como barras (la tabla trae todo).
  List<ProductoRango> get top => [
    for (var i = 0; i < productos.length && i < 8; i++) productos[i],
  ];
}

/// Etiqueta de [fecha] con la misma convención que el servidor
/// (`2026-10-01`, `2026-10` o `2026` según [agrupacion]).
String _etiqueta(DateTime fecha, String agrupacion) {
  String p(int v, [int ancho = 2]) => v.toString().padLeft(ancho, '0');
  final anio = p(fecha.year, 4);
  return switch (agrupacion) {
    'mes' => '$anio-${p(fecha.month)}',
    'anio' => anio,
    _ => '$anio-${p(fecha.month)}-${p(fecha.day)}',
  };
}

double _decimal(Object? valor) => switch (valor) {
  null => 0,
  final double number => number,
  final int number => number.toDouble(),
  _ => double.tryParse('$valor') ?? 0,
};
