import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'ajustes_scope.dart';
import 'breakpoints.dart';
import 'dashboard_top_bar.dart';
import 'nav_scope.dart';
import 'sesion_scope.dart';
import 'sidebar.dart';

/// Layout responsive compartido para todas las screens.
/// Maneja desktop (sidebar inline), tablet y mobile (drawer + bottom nav).
///
/// [selectedNav] y [onNavSelect] son opcionales: cuando no se pasan, los
/// tres widgets de navegación leen el [NavScope] publicado por `MainScreen`.
/// Esa lectura se hace **dentro de cada widget** (no aquí) para que al
/// cambiar de módulo solo se redibujen ellos y el contenido de la página
/// se conserve intacto.
class ResponsiveLayout extends StatelessWidget {
  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;
  final String title;
  final Widget Function(BuildContext context, BoxConstraints constraints)
  contentBuilder;
  final Widget? floatingActionButton;

  /// Gesto de «actualizar» (arrastrar hacia abajo): recarga los datos de la
  /// página. `null` = sin gesto (la página prefiere sus propios botones).
  final Future<void> Function()? onRefresh;

  const ResponsiveLayout({
    super.key,
    this.selectedNav,
    this.onNavSelect,
    required this.title,
    required this.contentBuilder,
    this.floatingActionButton,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Sesión activa (null en tests aislados: sidebar/drawer sin cierre).
    final sesion = SesionScope.de(context);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      drawer: _NavDrawer(
        indice: selectedNav,
        onSeleccionar: onNavSelect,
        sesion: sesion,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= Breakpoints.desktop;

          if (isDesktop) {
            return Row(
              children: [
                _NavSidebar(
                  indice: selectedNav,
                  onSeleccionar: onNavSelect,
                  sesion: sesion,
                ),
                Expanded(
                  child: _buildContent(
                    context,
                    constraints,
                    showMenuButton: false,
                    anchoSidebar: Sidebar.ancho,
                  ),
                ),
              ],
            );
          }

          return _buildContent(context, constraints, showMenuButton: true);
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= Breakpoints.desktop) {
            return const SizedBox.shrink();
          }
          return _NavBottomNav(
            indice: selectedNav,
            onSeleccionar: onNavSelect,
            onMoreTap: () => Scaffold.of(context).openDrawer(),
            sesion: sesion,
          );
        },
      ),
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildContent(
    BuildContext context,
    BoxConstraints constraints, {
    required bool showMenuButton,
    double anchoSidebar = 0,
  }) {
    final isMobile = constraints.maxWidth < Breakpoints.tablet;
    final padding = isMobile ? 16.0 : 28.0;
    // Las páginas deben medir su ancho **real** (descontando el sidebar y el
    // padding del scroll), no el del body completo: con el ancho bruto
    // escogían demasiadas columnas y las tarjetas se estrangulaban.
    final anchoUtil = constraints.maxWidth - anchoSidebar - padding * 2;

    return SafeArea(
      child: Builder(
        builder: (context) {
          final scroll = SingleChildScrollView(
            // Con gesto de actualizar el scroll debe estar siempre activo,
            // aunque el contenido quepa en pantalla.
            physics: onRefresh == null
                ? null
                : const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DashboardTopBar(
                  title: title,
                  showMenuButton: showMenuButton,
                  onMenuTap: () => Scaffold.of(context).openDrawer(),
                  // En escritorio/web el QR sirve para abrir la app en el celular;
                  // en móvil (pantalla estrecha o APK) no tiene sentido.
                  showAccessQr: !isMobile,
                ),
                const SizedBox(height: 22),
                contentBuilder(context, BoxConstraints(maxWidth: anchoUtil)),
              ],
            ),
          );
          final refrescar = onRefresh;
          if (refrescar == null) return scroll;
          return RefreshIndicator(onRefresh: refrescar, child: scroll);
        },
      ),
    );
  }
}

/// Sidebar de escritorio: usa los parámetros explícitos si la página los
/// trae; si no, lee el [NavScope]. Al estar la dependencia **aquí**, un
/// cambio de módulo solo redibuja este widget y su árbol (el sidebar), sin
/// tocar el contenido de la página.
class _NavSidebar extends StatelessWidget {
  const _NavSidebar({this.indice, this.onSeleccionar, this.sesion});

  final int? indice;
  final ValueChanged<int>? onSeleccionar;
  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    return Sidebar(
      selectedIndex: indice ?? NavScope.indiceDe(context),
      onSelect: onSeleccionar ?? NavScope.onSeleccionarDe(context),
      sesion: sesion,
    );
  }
}

/// Igual que [_NavSidebar] pero para el drawer de móvil/tablet: además
/// cierra el drawer al elegir módulo.
class _NavDrawer extends StatelessWidget {
  const _NavDrawer({this.indice, this.onSeleccionar, this.sesion});

  final int? indice;
  final ValueChanged<int>? onSeleccionar;
  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    final elegir = onSeleccionar ?? NavScope.onSeleccionarDe(context);
    return FullDrawer(
      selectedIndex: indice ?? NavScope.indiceDe(context),
      sesion: sesion,
      onSelect: (i) {
        elegir(i);
        Navigator.pop(context);
      },
    );
  }
}

/// Bottom nav de móvil/tablet con la misma resolución de navegación.
class _NavBottomNav extends StatelessWidget {
  const _NavBottomNav({
    this.indice,
    this.onSeleccionar,
    this.onMoreTap,
    this.sesion,
  });

  final int? indice;
  final ValueChanged<int>? onSeleccionar;
  final VoidCallback? onMoreTap;
  final DatosSesion? sesion;

  @override
  Widget build(BuildContext context) {
    return MobileBottomNav(
      selectedIndex: indice ?? NavScope.indiceDe(context),
      onSelect: onSeleccionar ?? NavScope.onSeleccionarDe(context),
      onMoreTap: onMoreTap,
      sesion: sesion,
    );
  }
}

/// Título de sección + contador + botón primario de acción.
///
/// Se apila en vertical cuando el ancho disponible es `< 500` para que el
/// botón nunca desborde en móviles estrechos.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.count,
    this.buttonLabel,
    this.onButtonPressed,
    this.buttonIcon = Icons.add,
    this.button,
  });

  final String title;
  final int? count;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;
  final IconData buttonIcon;

  /// Botón propio (p. ej. con estado reactivo como el carrito). Cuando existe
  /// tiene prioridad sobre [buttonLabel]/[buttonIcon]/[onButtonPressed].
  final Widget? button;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final apilado = constraints.maxWidth < Breakpoints.narrow;

        final texto = Text(
          count == null ? title : '$title ($count)',
          style: TextStyle(
            fontSize: apilado ? 20 : 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        );

        final boton =
            button ??
            ((buttonLabel == null || onButtonPressed == null)
                ? null
                : ElevatedButton.icon(
                    onPressed: onButtonPressed,
                    icon: Icon(buttonIcon, size: 18),
                    label: Text(buttonLabel!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ));

        if (apilado) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              texto,
              if (boton != null) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: boton),
              ],
            ],
          );
        }

        return Row(
          children: [
            Flexible(child: texto),
            if (boton != null) ...[const SizedBox(width: 16), boton],
          ],
        );
      },
    );
  }
}

/// Contenedor base de una tarjeta en mobile (borde suave + radio 16).
class MobileCardContainer extends StatelessWidget {
  const MobileCardContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

/// Fila de paginación: 36x36, radio 8, la página activa en `brandGreen`.
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.pagina,
    required this.totalPaginas,
    required this.onCambio,
  });

  final int pagina;
  final int totalPaginas;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    // Ventana de páginas: primera, última y las vecinas de la actual.
    final paginas = <int>{
      0,
      totalPaginas - 1,
      pagina - 1,
      pagina,
      pagina + 1,
    }.where((p) => p >= 0 && p < totalPaginas).toList()..sort();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Boton(
          icono: Icons.chevron_left_rounded,
          habilitado: pagina > 0,
          onTap: () => onCambio(pagina - 1),
        ),
        for (var i = 0; i < paginas.length; i++) ...[
          if (i > 0 && paginas[i] - paginas[i - 1] > 1)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '…',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          _Boton(
            texto: '${paginas[i] + 1}',
            activo: paginas[i] == pagina,
            onTap: () => onCambio(paginas[i]),
          ),
        ],
        _Boton(
          icono: Icons.chevron_right_rounded,
          habilitado: pagina < totalPaginas - 1,
          onTap: () => onCambio(pagina + 1),
        ),
      ],
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    this.texto,
    this.icono,
    this.activo = false,
    this.habilitado = true,
    required this.onTap,
  });

  final String? texto;
  final IconData? icono;
  final bool activo;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: habilitado ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? AppColors.brandGreen : AppColors.cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: icono != null
              ? Icon(
                  icono,
                  size: 18,
                  color: habilitado
                      ? (activo ? Colors.white : AppColors.textSecondary)
                      : AppColors.cardBorder,
                )
              : Text(
                  texto!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                    color: activo ? Colors.white : AppColors.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 10 elementos por página; se usa dentro de cualquier tabla.
///
/// La cifra viene del ajuste «Filas por página» (vista «Ajustes»), así que
/// cambiarlo afecta a todas las tablas del sistema a la vez; sin scope
/// (pantallas aisladas en tests) se queda en 10.
///
/// Las tablas paginan en el **servidor** (`RecursoController.cargarPagina`):
/// el mixin solo lleva el índice de página y pinta los controles a partir
/// del total real.
mixin PaginationMixin<T extends StatefulWidget> on State<T> {
  int pagina = 0;

  int get porPagina {
    final ajustado = AjustesScope.de(context).numero(Ajustes.porPagina);
    return ajustado < 1 ? 10 : ajustado;
  }

  int pageCountTotal(int total) => (total / porPagina).ceil();

  void goToPage(int destino) => setState(() => pagina = destino);

  void resetPage() => pagina = 0;

  /// Controles de paginación a partir del [total] real de filas.
  ///
  /// [paginaActual] permite que la página muestre el índice que tiene el
  /// controlador (p. ej. tras un buscar lanzado desde otro widget).
  Widget buildPaginationTotal(int total, {int? paginaActual}) {
    final paginas = pageCountTotal(total);
    if (paginas <= 1) return const SizedBox.shrink();
    final actual = (paginaActual ?? pagina)
        .clamp(0, math.max(0, paginas - 1))
        .toInt();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: PaginationControls(
        pagina: actual,
        totalPaginas: paginas,
        onCambio: goToPage,
      ),
    );
  }
}

/// Scroll horizontal de respaldo cuando una tabla excede el ancho disponible.
class ResponsiveTableWrapper extends StatelessWidget {
  const ResponsiveTableWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );
  }
}
