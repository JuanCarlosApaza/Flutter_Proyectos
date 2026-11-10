/// Variante de producto: una combinación concreta de prenda + talla + color,
/// que es donde vive el **stock real** (tabla `producto_variantes`).
///
/// `productos.stock` es el agregado de las variantes visibles; una venta
/// siempre descuenta de una variante concreta.
library;

import '../rules/estados.dart';

/// Variante persistida (con nombres de talla/color ya resueltos).
final class ProductoVariante {
  const ProductoVariante({
    required this.id,
    required this.productoId,
    required this.tallaId,
    required this.colorId,
    required this.nombreTalla,
    required this.nombreColor,
    this.codigoHex,
    this.stock = 0,
    this.codigo,
    this.estado = 'ACTIVO',
  });

  final int id;
  final int productoId;
  final int tallaId;
  final int colorId;

  /// Nombre de la talla congelado en la lectura (`S`, `M`, `3`...).
  final String nombreTalla;

  /// Nombre del color congelado en la lectura (`Negro`, `Azul marino`...).
  final String nombreColor;

  /// Color de chip de la talla de UI (`#101010`), si la tiene.
  final String? codigoHex;

  /// Existencias de **esta** combinación (unidades enteras en la práctica).
  final double stock;

  /// SKU propio de la variante (opcional).
  final String? codigo;

  /// `ACTIVO`, `INACTIVO`, `BLOQUEADO` o `ELIMINADO` (borrado lógico).
  final String estado;

  bool get oculta => estado == estadoEliminado;

  /// Se puede vender ahora: visible y con existencias.
  bool get vendible => !oculta && estado != 'DESCONTINUADO' && stock > 0;

  ProductoVariante copiaCon({
    double? stock,
    String? estado,
  }) => ProductoVariante(
    id: id,
    productoId: productoId,
    tallaId: tallaId,
    colorId: colorId,
    nombreTalla: nombreTalla,
    nombreColor: nombreColor,
    codigoHex: codigoHex,
    stock: stock ?? this.stock,
    codigo: codigo,
    estado: estado ?? this.estado,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'productoId': productoId,
    'tallaId': tallaId,
    'colorId': colorId,
    'talla': nombreTalla,
    'color': nombreColor,
    'codigoHex': codigoHex,
    'codigo': codigo,
    'stock': stock,
    'estado': estado,
    'disponible': vendible,
  };
}

/// Datos para dar de alta una variante (`POST /productos/{id}/variantes`).
///
/// La combinación se puede declarar de dos formas (exactamente una por
/// campo):
///
/// * por **id** (`tallaId`/`colorId`): lo que ya existe en el catálogo;
/// * por **nombre** (`talla`/`color`): texto libre como `S`, `XXL`, `4`,
///   `Negro`... Si no hay id, el backend busca ese nombre en `tallas`/
///   `colores` (sin distinguir mayúsculas) y **lo crea** si no existe, de
///   modo que quien da de alta un producto escribe sus propias tallas y
///   colores sin depender de ninguna semilla.
final class DatoVariante {
  const DatoVariante({
    this.tallaId = 0,
    this.colorId = 0,
    this.talla,
    this.color,
    this.stock = 0,
    this.codigo,
  });

  /// Id de la talla en el catálogo (`0` = no viene: usa [talla]).
  final int tallaId;

  /// Id del color en el catálogo (`0` = no viene: usa [color]).
  final int colorId;

  /// Nombre de la talla escrita a mano (`S`, `XXL`, `4`...).
  final String? talla;

  /// Nombre del color escrito a mano (`Negro`, `Azul marino`...).
  final String? color;

  final double stock;

  final String? codigo;
}
