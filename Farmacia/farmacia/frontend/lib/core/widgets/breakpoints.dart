/// Los 3 números que gobiernan toda la responsividad de la app.
///
/// Se miden contra el **ancho real del contenido** (`LayoutBuilder`), nunca
/// contra `MediaQuery.of(context)`: así el layout responde bien en web con
/// sidebar visible o ventanas redimensionables.
class Breakpoints {
  Breakpoints._();

  /// `>= 1100`: sidebar inline de 240px, sin bottom nav, grids de 4.
  static const double desktop = 1100;

  /// `>= 700`: tablas completas y grids de 3. Por debajo -> tarjetas.
  static const double tablet = 700;

  /// `< 500`: `PageHeader` apilado verticalmente.
  static const double narrow = 500;
}
