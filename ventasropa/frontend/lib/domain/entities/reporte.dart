import '../../core/errors/failure.dart';

/// Producto con sus ventas agregadas (ranking del dashboard e informe por
/// rango de fechas).
///
/// Es lo que devuelve `GET /api/v1/reportes/productos-vendidos` y
/// `GET /api/v1/reportes/ventas-productos`: un resumen calculado por el
/// servidor agrupando las líneas de las órdenes, no una fila de un CRUD
/// (por eso tiene su propio camino en vez de usar `Recurso`).
final class VentaProducto {
  const VentaProducto({
    required this.productoId,
    required this.nombre,
    required this.unidades,
    required this.monto,
    this.categoria,
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
      // La rellena el informe por rango; el ranking del dashboard no.
      categoria: json['categoria'] is String ? json['categoria'] as String : null,
    );
  }

  final int productoId;
  final String nombre;

  /// Cantidad vendida (solo órdenes no anuladas): fraccionada, `12.75 KG`.
  final double unidades;

  /// Importe generado, en bolivianos.
  final double monto;

  /// Categoría del producto (o «(sin categoría)») en el informe por rango.
  final String? categoria;
}

/// Venta de un periodo concreto de la serie del informe (día, mes o año).
final class VentaPeriodo {
  const VentaPeriodo({
    required this.etiqueta,
    required this.ordenes,
    required this.total,
    required this.unidades,
  });

  factory VentaPeriodo.fromJson(Map<String, dynamic> json) {
    final etiqueta = json['etiqueta'];
    if (etiqueta is! String) throw const ParsingFailure();
    return VentaPeriodo(
      etiqueta: etiqueta,
      ordenes: _entero(json['ordenes']),
      total: _decimal(json['total']),
      unidades: _decimal(json['unidades']),
    );
  }

  /// Periodo tal y como lo agrupa el servidor en hora de Bolivia:
  /// `2026-10-01`, `2026-10` o `2026`.
  final String etiqueta;

  final int ordenes;

  /// Importe bruto de las órdenes pagadas del periodo, en bolivianos.
  final double total;

  /// Unidades vendidas en el periodo.
  final double unidades;

  Map<String, Object?> toJson() => {
    'etiqueta': etiqueta,
    'ordenes': ordenes,
    'total': total,
    'unidades': unidades,
  };
}

/// Cifras de cabecera del rango: la suma de la serie y el ticket medio.
final class ResumenVentas {
  const ResumenVentas({
    required this.total,
    required this.ordenes,
    required this.unidades,
  });

  factory ResumenVentas.fromJson(Map<String, dynamic> json) => ResumenVentas(
    total: _decimal(json['total']),
    ordenes: _entero(json['ordenes']),
    unidades: _decimal(json['unidades']),
  );

  final double total;
  final int ordenes;
  final double unidades;

  /// Importe medio de una orden (`0` si no hubo ventas).
  double get ticketMedio => ordenes == 0 ? 0 : total / ordenes;
}

/// Informe «ventas por día / mes / año» de un rango de fechas.
///
/// El servidor solo envía los periodos **con** ventas; [serieCompleta]
/// rellena los huecos con ceros para que el gráfico muestre los días (o
/// meses) sin ventas del rango.
final class InformeVentas {
  const InformeVentas({
    required this.desde,
    required this.hasta,
    required this.agrupacion,
    required this.resumen,
    required this.serie,
  });

  factory InformeVentas.fromJson(Map<String, dynamic> json) {
    final resumen = json['resumen'];
    final serie = json['serie'];
    if (resumen is! Map<String, dynamic> || serie is! List) {
      throw const ParsingFailure();
    }
    return InformeVentas(
      desde: '${json['desde'] ?? ''}',
      hasta: '${json['hasta'] ?? ''}',
      agrupacion: '${json['agrupacion'] ?? 'dia'}',
      resumen: ResumenVentas.fromJson(resumen),
      serie: [
        for (final fila in serie.whereType<Map<String, dynamic>>())
          VentaPeriodo.fromJson(fila),
      ],
    );
  }

  /// Primer día del rango (`yyyy-MM-dd`, inclusive).
  final String desde;

  /// Último día del rango (`yyyy-MM-dd`, inclusive).
  final String hasta;

  /// `dia`, `mes` o `anio`.
  final String agrupacion;

  final ResumenVentas resumen;

  /// Periodos con ventas, en orden ascendente.
  final List<VentaPeriodo> serie;

  /// Serie completa del rango, con ceros en los periodos sin ventas.
  ///
  /// El gráfico la necesita: sin rellenar, un día sin ventas parecería que
  /// el rango se cortara.
  List<VentaPeriodo> get serieCompleta {
    final inicio = DateTime.tryParse(desde);
    final fin = DateTime.tryParse(hasta);
    if (inicio == null || fin == null || fin.isBefore(inicio)) return serie;

    final etiquetas = <String>[];
    switch (agrupacion) {
      case 'mes':
        var mes = DateTime(inicio.year, inicio.month);
        final ultimo = DateTime(fin.year, fin.month);
        while (!mes.isAfter(ultimo)) {
          etiquetas.add(
            '${mes.year}-${mes.month.toString().padLeft(2, '0')}',
          );
          mes = DateTime(mes.year, mes.month + 1);
        }
      case 'anio':
        for (var anio = inicio.year; anio <= fin.year; anio++) {
          etiquetas.add('$anio');
        }
      default:
        for (var dia = inicio; !dia.isAfter(fin); ) {
          etiquetas.add(
            '${dia.year.toString().padLeft(4, '0')}-'
            '${dia.month.toString().padLeft(2, '0')}-'
            '${dia.day.toString().padLeft(2, '0')}',
          );
          dia = dia.add(const Duration(days: 1));
        }
    }
    if (etiquetas.isEmpty) return serie;

    final porEtiqueta = {for (final fila in serie) fila.etiqueta: fila};
    return [
      for (final etiqueta in etiquetas)
        porEtiqueta[etiqueta] ??
            VentaPeriodo(etiqueta: etiqueta, ordenes: 0, total: 0, unidades: 0),
    ];
  }
}

/// Ventas de una categoría dentro del rango (reparto por categoría).
final class VentaCategoria {
  const VentaCategoria({
    required this.nombre,
    required this.unidades,
    required this.monto,
  });

  factory VentaCategoria.fromJson(Map<String, dynamic> json) {
    final nombre = json['nombre'];
    if (nombre is! String) throw const ParsingFailure();
    return VentaCategoria(
      nombre: nombre,
      unidades: _decimal(json['unidades']),
      monto: _decimal(json['monto']),
    );
  }

  final String nombre;
  final double unidades;
  final double monto;
}

/// Informe «ventas por producto y categoría» de un rango de fechas.
final class InformeProductos {
  const InformeProductos({
    required this.productos,
    required this.categorias,
  });

  factory InformeProductos.fromJson(Map<String, dynamic> json) {
    final productos = json['productos'];
    final categorias = json['categorias'];
    if (productos is! List || categorias is! List) {
      throw const ParsingFailure();
    }
    return InformeProductos(
      productos: [
        for (final p in productos.whereType<Map<String, dynamic>>())
          VentaProducto.fromJson(p),
      ],
      categorias: [
        for (final c in categorias.whereType<Map<String, dynamic>>())
          VentaCategoria.fromJson(c),
      ],
    );
  }

  final List<VentaProducto> productos;
  final List<VentaCategoria> categorias;
}

double _decimal(Object? valor) =>
    valor is num ? valor.toDouble() : (double.tryParse('$valor') ?? 0);

int _entero(Object? valor) => valor is num
    ? valor.toInt()
    : (int.tryParse('$valor') ?? 0);
