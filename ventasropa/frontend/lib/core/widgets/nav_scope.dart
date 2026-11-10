import 'package:flutter/material.dart';

/// Índice de navegación seleccionado + callback para cambiarlo.
///
/// Lo publica `MainScreen` alrededor del `IndexedStack` de módulos. Las
/// páginas **no** reciben el índice como parámetro: así sus widgets son
/// `const` y, al cambiar de módulo, los elementos existentes se descartan por
/// identidad (`widget == newWidget`) y **no se reconstruyen**. Sin esto,
/// cada módulo visitado (dashboard, productos, catálogo, ventas…) se
/// redibujaba entero —con su grid o tabla incluidos— en cada clic del sidebar.
///
/// Quien lee el índice con [indiceDe] queda suscrito: el `sidebar`, el
/// `drawer` y el `bottom nav` se repintan al cambiar de módulo, y nada más.
class NavScope extends InheritedNotifier<ValueNotifier<int>> {
  const NavScope({
    super.key,
    required ValueNotifier<int> seleccionado,
    required this.onSeleccionar,
    required super.child,
  }) : super(notifier: seleccionado);

  /// Cambia de módulo (el mismo callback que `MainScreen` maneja).
  final ValueChanged<int> onSeleccionar;

  /// Índice actual. Registra dependencia: quien lo llama se redibuja al
  /// cambiar la selección. Devuelve `0` fuera de la app (pantalla aislada
  /// en un test, sin `NavScope` por encima).
  static int indiceDe(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavScope>()?.notifier?.value ??
      0;

  /// Callback de navegación; sin `NavScope` devuelve un no-op para que las
  /// pantallas montadas sueltas no fallen al tocar el sidebar.
  static ValueChanged<int> onSeleccionarDe(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavScope>()?.onSeleccionar ??
      _ignorar;

  static void _ignorar(int _) {}
}
