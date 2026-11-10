import 'package:flutter/material.dart';

import '../permisos.dart';
import '../theme/app_colors.dart';
import 'ajustes_scope.dart';
import 'alertas.dart';

/// Ítem de navegación (icono + etiqueta).
class NavItem {
  const NavItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Todos los módulos (sidebar desktop + drawer mobile).
///
/// El orden coincide con el switch de `MainScreen` y con `Modulos.todos`
/// (`core/permisos.dart`): insertar un ítem aquí obliga a reordenar sus casos
/// y a sumarlo a la migración de permisos (`009_roles_permisos` y las sucesivas).
const List<NavItem> navItems = [
  NavItem(Icons.grid_view_rounded, 'Dashboard'),
  NavItem(Icons.inventory_2_rounded, 'Productos'),
  NavItem(Icons.storefront_rounded, 'Catálogo'),
  NavItem(Icons.people_rounded, 'Clientes'),
  NavItem(Icons.shopping_cart_rounded, 'Ventas'),
  NavItem(Icons.description_rounded, 'Cotizaciones'),
  NavItem(Icons.category_rounded, 'Categorías'),
  NavItem(Icons.local_shipping_rounded, 'Proveedores'),
  NavItem(Icons.badge_rounded, 'Empleados'),
  NavItem(Icons.manage_accounts_rounded, 'Usuarios'),
  // Índice 10: ocupa el hueco que deja Ajustes al pasar al 11 (la migración
  // 010_auditoria reajusta el ajuste «página inicial» guardado).
  NavItem(Icons.history_rounded, 'Auditoría'),
  // Va al final: añadirlo delante desplazaría los índices de los demás
  // (y con ellos `navVentas`).
  NavItem(Icons.tune_rounded, 'Ajustes'),
];

/// Índice de "Ventas" dentro de [navItems] (y del switch de `MainScreen`):
/// el carrito del catálogo lo usa para saltar al módulo de ventas en cuanto
/// se genera una orden.
const int navVentas = 4;

/// Índices de [navItems] que la sesión tiene permiso de **ver**.
///
/// * `sesion == null` (pantalla aislada en un test, sidebar suelto): se
///   muestra todo, como antes del sistema de permisos.
/// * Con sesión sin ningún permiso visible se devuelve el Dashboard para que
///   el menú nunca quede vacío (la API responderá 403 en cada llamada).
List<int> indicesVisibles(DatosSesion? sesion) {
  if (sesion == null) return [for (var i = 0; i < navItems.length; i++) i];
  final visibles = [
    for (var i = 0; i < navItems.length; i++)
      if (sesion.usuario.puede(Modulos.todos[i])) i,
  ];
  return visibles.isEmpty ? const [0] : visibles;
}

/// Orden de preferencia del bottom nav móvil: Dashboard, Catálogo,
/// Productos y Ventas (los cuatro que más se usan desde el celular);
/// los módulos visibles que falten se rellenan por orden.
const List<int> _ordenBottomNav = [0, 2, 1, 4];

/// Índices para el bottom nav: hasta 4 de los visibles, empezando por los de
/// [_ordenBottomNav]. Si queda algún módulo visible fuera, el último ítem del
/// bottom nav («Más») abre el drawer con la lista completa.
List<int> bottomNavIndices(DatosSesion? sesion) {
  final visibles = indicesVisibles(sesion);
  final elegidos = [
    for (final i in _ordenBottomNav)
      if (visibles.contains(i)) i,
  ];
  for (final i in visibles) {
    if (elegidos.length >= 4) break;
    if (!elegidos.contains(i)) elegidos.add(i);
  }
  return elegidos;
}

/// Sidebar fijo de desktop (240px).
///
/// [sesion] es la sesión activa (`SesionScope.de(context)`): si hay, el pie
/// muestra el usuario conectado y el botón de cerrar sesión; si no (pantalla
/// aislada en un test), mantiene el pie genérico.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.sesion,
  });

  /// Ancho fijo: lo descuenta `ResponsiveLayout` al calcular el ancho útil
  /// que reciben las páginas.
  static const double ancho = 240;

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      color: AppColors.sidebarBg,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Logo ---
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.brandGreen,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.local_pharmacy_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AjustesScope.de(context).valor(Ajustes.nombreFarmacia),
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          // --- Sección ---
          const Padding(
            padding: EdgeInsets.only(left: 10, bottom: 8),
            child: Text(
              'NAVIGATION',
              style: TextStyle(
                color: AppColors.textOnDarkMuted,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
          ),
          // --- Ítems (solo los módulos con permiso `ver`) ---
          Expanded(
            child: Builder(
              builder: (context) {
                final visibles = indicesVisibles(sesion);
                return ListView.builder(
                  itemCount: visibles.length,
                  itemBuilder: (context, position) {
                    final index = visibles[position];
                    return _SidebarItem(
                      item: navItems[index],
                      seleccionado: index == selectedIndex,
                      onTap: () => onSelect(index),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF1B4437)),
          const SizedBox(height: 10),
          // --- Footer: usuario conectado + cerrar sesión ---
          _PieSesion(sesion: sesion),
        ],
      ),
    );
  }
}

class _PieSesion extends StatelessWidget {
  const _PieSesion({this.sesion});

  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    final conectado = sesion;

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.brandGreen,
          child: Text(
            conectado?.usuario.iniciales ?? 'AD',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conectado?.usuario.nombreUsuario ?? 'Admin',
                style: const TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                conectado?.usuario.nivelUsuario ?? 'ID #1',
                style: const TextStyle(
                  color: AppColors.textOnDarkMuted,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (conectado != null)
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => cerrarSesionConfirmada(context, conectado),
            icon: const Icon(
              Icons.logout_rounded,
              size: 18,
              color: AppColors.textOnDarkMuted,
            ),
          ),
      ],
    );
  }
}

/// Confirmación estándar del cierre de sesión (mismo patrón que el resto de
/// alertas de la app) y, si se acepta, invalida el token en el servidor.
Future<void> cerrarSesionConfirmada(
  BuildContext context,
  DatosSesion sesion,
) async {
  final confirmado = await confirmarAccion(
    context,
    titulo: 'Cerrar sesión',
    mensaje:
        '¿Quieres salir de ${AjustesScope.de(context).valor(Ajustes.nombreFarmacia)}?',
    nota:
        'Se cerrará la sesión en este equipo y se olvidará el usuario '
        'guardado: la próxima vez tendrás que iniciar sesión de nuevo.',
    textoConfirmar: 'Cerrar sesión',
    colorConfirmar: AppColors.negativeRed,
  );
  if (confirmado) await sesion.cerrarSesion();
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.item,
    required this.seleccionado,
    required this.onTap,
  });

  final NavItem item;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: seleccionado ? AppColors.brandGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: seleccionado ? Colors.white : AppColors.textOnDarkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: seleccionado
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: seleccionado
                        ? Colors.white
                        : AppColors.textOnDarkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom nav de tablet/mobile: hasta 4 de los módulos visibles (siguiendo el
/// orden histórico de [_ordenBottomNav]); si queda alguno fuera, el último
/// ítem «Más» abre el drawer con la lista completa.
class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.onMoreTap,
    this.sesion,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onMoreTap;

  /// Sesión activa (null en tests/pantallas aisladas: se muestra todo).
  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    final elegidos = bottomNavIndices(sesion);
    final visibles = indicesVisibles(sesion);
    final hayMas = visibles.length > elegidos.length;
    // Si el módulo actual no está en la barra (p. ej. Cotizaciones), se
    // marca «Más» para no señalar un ítem que no corresponde.
    final posicion = elegidos.indexOf(selectedIndex);

    final items = [
      for (final indice in elegidos)
        BottomNavigationBarItem(
          icon: Icon(navItems[indice].icon),
          label: navItems[indice].label,
        ),
      if (hayMas)
        const BottomNavigationBarItem(
          icon: Icon(Icons.menu_rounded),
          label: 'Más',
        ),
    ];

    return BottomNavigationBar(
      currentIndex: posicion >= 0 ? posicion : (hayMas ? items.length - 1 : 0),
      onTap: (index) {
        if (hayMas && index == elegidos.length) {
          onMoreTap?.call();
        } else {
          onSelect(elegidos[index]);
        }
      },
      backgroundColor: AppColors.sidebarBg,
      selectedItemColor: AppColors.brandGreen,
      unselectedItemColor: AppColors.textOnDarkMuted,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      selectedFontSize: 11,
      unselectedFontSize: 11,
      items: items,
    );
  }
}

/// Drawer completo (mobile/tablet) con la lista de todos los módulos.
class FullDrawer extends StatelessWidget {
  const FullDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.sesion,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.sidebarBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_pharmacy_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AjustesScope.de(context).valor(Ajustes.nombreFarmacia),
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1B4437)),
            Expanded(
              child: Builder(
                builder: (context) {
                  final visibles = indicesVisibles(sesion);
                  return ListView.builder(
                    itemCount: visibles.length,
                    itemBuilder: (context, position) {
                      final index = visibles[position];
                      final seleccionado = index == selectedIndex;
                      return ListTile(
                        leading: Icon(
                          navItems[index].icon,
                          size: 22,
                          color: seleccionado
                              ? AppColors.brandGreen
                              : AppColors.textOnDarkMuted,
                        ),
                        title: Text(
                          navItems[index].label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: seleccionado
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: seleccionado
                                ? AppColors.brandGreen
                                : AppColors.textOnDarkMuted,
                          ),
                        ),
                        selected: seleccionado,
                        selectedColor: AppColors.brandGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () => onSelect(index),
                      );
                    },
                  );
                },
              ),
            ),
            // --- Sesión activa: usuario + cerrar sesión (móvil/tablet) ---
            if (sesion != null) ...[
              const Divider(color: Color(0xFF1B4437)),
              ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.brandGreen,
                  child: Text(
                    sesion!.usuario.iniciales,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  sesion!.usuario.nombreUsuario,
                  style: const TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  sesion!.usuario.nivelUsuario,
                  style: const TextStyle(
                    color: AppColors.textOnDarkMuted,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () => cerrarSesionConfirmada(context, sesion!),
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.textOnDarkMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
