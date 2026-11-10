/// Catálogo de ropa: tallas y colores base de las prendas.
///
/// Dominio puro: cada tienda define sus tallas (numéricas de niño,
/// S/M/L/XL de adulto, «Única» para prendas sin talla) y sus colores;
/// las tablas viven en `tallas` y `colores` y la traducción
/// snake_case -> camelCase ocurre en `data/`.
library;

/// Talla de una prenda (tabla `tallas`).
final class Talla {
  const Talla({
    required this.id,
    required this.nombre,
    this.orden = 0,
    this.estado = 'ACTIVO',
  });

  final int id;

  /// Nombre corto y único: `S`, `M`, `XL`, `3`, `Única`...
  final String nombre;

  /// Orden de exhibición en la UI (menor = primero).
  final int orden;

  /// `ACTIVO`, `INACTIVO`, `BLOQUEADO` o `ELIMINADO`.
  final String estado;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'orden': orden,
    'estado': estado,
  };
}

/// Color de una prenda (tabla `colores`).
final class ColorRopa {
  const ColorRopa({
    required this.id,
    required this.nombre,
    this.codigoHex,
    this.estado = 'ACTIVO',
  });

  final int id;

  /// Nombre único: `Negro`, `Azul marino`...
  final String nombre;

  /// Color de chip en la UI (`#101010`), opcional.
  final String? codigoHex;

  /// `ACTIVO`, `INACTIVO`, `BLOQUEADO` o `ELIMINADO`.
  final String estado;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'codigoHex': codigoHex,
    'estado': estado,
  };
}
