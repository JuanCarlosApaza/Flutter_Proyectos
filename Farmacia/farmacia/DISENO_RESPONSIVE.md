# Diseño y Responsividad — Guía para replicar en otro proyecto

> Extraído del frontend de este proyecto (`lib/core/` + `lib/modules/`).
> Este documento es la **fuente única** para copiar el mismo diseño y la misma
> responsividad en un proyecto nuevo, sin perder el comportamiento responsive
> que ya está probado acá.

---

## 1. Resumen del sistema

| Capa | Implementación |
|------|----------------|
| Paleta de colores | `lib/core/theme/app_colors.dart` (clase `AppColors`) |
| Layout base | `lib/core/widgets/responsive_layout.dart` (`ResponsiveLayout`) |
| Navegación | `lib/core/widgets/sidebar.dart` (`Sidebar`, `MobileBottomNav`, `FullDrawer`) |
| Header de página | `PageHeader` (dentro de `responsive_layout.dart`) |
| Tablas | Patrón doble: tabla desktop / tarjetas mobile |
| Forms | `showModalBottomSheet` con `isScrollControlled: true` |
| Tema global | `MaterialApp` con `useMaterial3: true` y `ColorScheme.fromSeed` |

**Principio rector:** *un solo árbol de widgets que cambia de forma según el
ancho disponible*, usando `LayoutBuilder` en vez de `MediaQuery.of(context)`
— así el layout responde al **ancho real del contenido**, no al de la pantalla
(importante en web con sidebar visible o ventanas redimensionables).

---

## 2. Breakpoints (los 3 números que gobiernan todo)

Estos valores están usados de forma consistente en todo el proyecto. **No los
cambies si quieres que el resultado se vea igual.**

| Breakpoint | Comportamiento |
|------------|----------------|
| `>= 1100` | **Desktop**: sidebar fijo de 240px a la izquierda, sin bottom nav, grids de 4 columnas, tablas completas |
| `>= 700` y `< 1100` | **Tablet**: drawer + bottom nav, grids de 3 columnas, tablas completas |
| `< 700` | **Mobile**: drawer + bottom nav, grids de 2 columnas, **tablas → tarjetas apiladas**, padding de 16px |
| `< 500` | **Mobile estrecho**: `PageHeader` se apila verticalmente (título arriba, botón abajo) |

Definición central (extraer siempre como constantes):

```dart
class Breakpoints {
  Breakpoints._();
  static const double desktop = 1100; // >= : sidebar inline
  static const double tablet = 700;   // >= : tablas completas, 3 columnas
  static const double narrow = 500;   // <  : header apilado
}
```

---

## 3. Paleta de colores (copiar tal cual)

Archivo: `lib/core/theme/app_colors.dart`

```dart
import 'package:flutter/material.dart';

/// Paleta central del dashboard.
/// Verde profundo para sidebar / cards oscuras, fondo hueso suave para el
/// contenido y un único acento verde usado de forma consistente.
class AppColors {
  AppColors._();

  // Familia verde de marca
  static const Color brandGreen = Color(0xFF2FBE7A);
  static const Color brandGreenDark = Color(0xFF0E3B2E);
  static const Color sidebarBg = Color(0xFF0B2E24);
  static const Color darkCardBg = Color(0xFF0E3B2E);
  static const Color darkCardBg2 = Color(0xFF123F32);

  // Fondo neutro / contenido
  static const Color pageBg = Color(0xFFEDEEEA);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE7E8E3);

  // Texto
  static const Color textPrimary = Color(0xFF16241F);
  static const Color textSecondary = Color(0xFF7C8983);
  static const Color textOnDark = Color(0xFFFFFFFF);
  static const Color textOnDarkMuted = Color(0xFFAFC2BA);

  // Acentos de estado
  static const Color negativeRed = Color(0xFFE8604C);
  static const Color positiveGreen = Color(0xFF2FBE7A);
  static const Color trackGrey = Color(0xFFEDEEEA);
  static const Color darkTrack = Color(0xFF13221D);

  // Acentos de mapa (heat)
  static const Color mapHighest = Color(0xFFE8604C);
  static const Color mapHigh = Color(0xFFEE8A6E);
  static const Color mapMed = Color(0xFFF4B49D);
  static const Color mapLow = Color(0xFFF8D7C9);

  // Acentos de estado (extendidos)
  static const Color infoBlue = Color(0xFF4A90D9);
  static const Color warningOrange = Color(0xFFF5A623);
}
```

### Reglas de uso del color

- **Fondo de página**: siempre `AppColors.pageBg` (`#EDEEEA`, hueso, no blanco puro).
- **Cards claras**: `cardBg` + `border: Border.all(color: cardBorder)` + radio 16–20.
- **Cards oscuras** (KPIs destacados): `darkCardBg` (`#0E3B2E`), **sin borde**, radio 18.
- **Sidebar / bottom nav / drawer**: `sidebarBg` (`#0B2E24`).
- **Acento único**: `brandGreen` para selección, botones primarios y estados "positivos".
- **Nunca** usar `Colors.green` u otros verdes fuera de la paleta: rompe la coherencia.
- Texto secundario (`textSecondary`) para labels, encabezados de columna y metadatos.

### Tema global (`main.dart`)

```dart
MaterialApp(
  title: 'Mi App',
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.pageBg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.brandGreen,
      primary: AppColors.brandGreen,
    ),
  ),
  home: const MainScreen(),
);
```

---

## 4. Tipografía y espaciado

| Elemento | Estilo |
|----------|--------|
| Título de top bar | `fontSize: 22`, `fontWeight: w700`, `textPrimary` |
| Título `PageHeader` desktop | `fontSize: 22`, `w700` |
| Título `PageHeader` mobile | `fontSize: 20`, `w700` |
| Valor de KPI | `fontSize: 24–28`, `w700`, `textPrimary` |
| Label de KPI / columna de tabla | `fontSize: 13`, `textSecondary` |
| Celda de tabla | `fontSize: 14` (`textPrimary`) o `13` (secundario) |
| Texto de card mobile | `fontSize: 13`, labels en `textSecondary` |
| Enlaces/valores dentro de card mobile | `fontSize: 13`, `textPrimary` |
| Sidebar item | `fontSize: 14`, `w600` si está seleccionado, `w400` si no |
| Subtítulo sidebar (sección) | `fontSize: 11`, `letterSpacing: 1.1`, uppercase |

**Espaciado:**

| Contexto | Valor |
|----------|-------|
| Padding del contenido (`desktop/tablet`) | `EdgeInsets.all(28)` |
| Padding del contenido (`mobile < 700`) | `EdgeInsets.all(16)` |
| Separación top bar → contenido | `22` |
| Separación `PageHeader` → siguiente bloque | `16`–`20` |
| Gap en grids | `16` |
| Padding de card | `18`–`20` |
| Radio de card | `16` (tablas/contenedores), `18`–`20` (KPIs), `12` (botones/items) |
| Gap entre filtros (`Wrap`) | `spacing: 8`, `runSpacing: 8` |

---

## 5. Layout base: `ResponsiveLayout`

Archivo: `lib/core/widgets/responsive_layout.dart` (copiar completo).

```dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'sidebar.dart';
import 'dashboard_top_bar.dart';

/// Layout responsive compartido para todas las screens.
/// Maneja desktop (sidebar inline), tablet y mobile (drawer + bottom nav).
///
/// `selectedNav`/`onNavSelect` son opcionales: cuando una pantalla no los
/// pasa, los tres widgets de navegación (_NavSidebar/_NavDrawer/_NavBottomNav)
/// leen el `NavScope` que publica `MainScreen`. La lectura se hace **dentro
/// de cada widget de navegación** (nunca aquí): así, al cambiar de módulo solo
/// se redibuja la navegación y el contenido de la página queda intacto.
class ResponsiveLayout extends StatelessWidget {
  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;
  final String title;
  final Widget Function(BuildContext context, BoxConstraints constraints) contentBuilder;
  final Widget? floatingActionButton;

  const ResponsiveLayout({
    super.key,
    this.selectedNav,
    this.onNavSelect,
    required this.title,
    required this.contentBuilder,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      drawer: _NavDrawer(indice: selectedNav, onSeleccionar: onNavSelect),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1100;

          if (isDesktop) {
            return Row(
              children: [
                _NavSidebar(indice: selectedNav, onSeleccionar: onNavSelect),
                Expanded(child: _buildContent(context, constraints, showMenuButton: false)),
              ],
            );
          }

          return _buildContent(context, constraints, showMenuButton: true);
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1100) return const SizedBox.shrink();
          return _NavBottomNav(
            indice: selectedNav,
            onSeleccionar: onNavSelect,
            onMoreTap: () => Scaffold.of(context).openDrawer(),
          );
        },
      ),
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _buildContent(BuildContext context, BoxConstraints constraints, {required bool showMenuButton}) {
    final isMobile = constraints.maxWidth < 700;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardTopBar(
              title: title,
              showMenuButton: showMenuButton,
              onMenuTap: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(height: 22),
            contentBuilder(context, constraints),
          ],
        ),
      ),
    );
  }
}
```

### Detalles que sostienen la responsividad (no eliminar)

1. **`bottomNavigationBar` usa su propio `LayoutBuilder`**: el `bottomNavigationBar`
   recibe constraints distintos a los del `body`, por eso se vuelve a medir y se
   oculta con `SizedBox.shrink()` en desktop. Si lo sacas, aparece una barra
   inferior fantasma en pantallas grandes.
2. **`Scaffold.of(context).openDrawer()`** se llama desde el `body`, donde el
   `Scaffold` está en el árbol (el drawer siempre existe, aunque solo se muestre
   en mobile/tablet).
3. **Un único `SingleChildScrollView`** en la raíz del contenido: todas las
   pantallas se desplazan igual y nunca hay scroll anidado conflictivo.
4. **`SafeArea`** alrededor del contenido protege notch y gestures.

---

## 6. Navegación

Archivo: `lib/core/widgets/sidebar.dart`.

### 6.1 Estructura de ítems

```dart
class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Todos los módulos (sidebar desktop + drawer mobile)
const List<NavItem> navItems = [
  NavItem(Icons.grid_view_rounded, 'Dashboard'),
  NavItem(Icons.people_rounded, 'Usuarios'),
  NavItem(Icons.inventory_2_rounded, 'Productos'),
  NavItem(Icons.groups_rounded, 'Clientes'),
  NavItem(Icons.shopping_cart_rounded, 'Ventas'),
  // ... agrega los tuyos
];

/// Máximo 5 ítems para el bottom nav; el último abre el drawer
const List<NavItem> bottomNavItems = [
  NavItem(Icons.grid_view_rounded, 'Inicio'),
  NavItem(Icons.groups_rounded, 'Clientes'),
  NavItem(Icons.shopping_cart_rounded, 'Ventas'),
  NavItem(Icons.inventory_2_rounded, 'Productos'),
  NavItem(Icons.menu_rounded, 'Más'),
];

/// Mapeo bottom-nav index → screen index (el índice 4 "Más" no está)
const Map<int, int> bottomNavToScreen = {0: 0, 1: 3, 2: 4, 3: 2};
```

**Regla de oro del bottom nav:** máximo **5 ítems**, y el último **siempre** es
"Más" que abre el `Drawer` con la lista completa. Así en mobile no se pierde
ningún módulo aunque no cabiga en la barra.

### 6.2 `Sidebar` (desktop, ancho fijo 240)

- `Container(width: 240, color: AppColors.sidebarBg)`.
- Logo: cuadrado 32×32 verde (`brandGreen`, radio 9) + nombre en `w700`.
- Separador de sección: texto `NAVIGATION` en 11px, `letterSpacing: 1.1`.
- Ítem: `InkWell` con `borderRadius: 12`, fondo `brandGreen` cuando está
  seleccionado (icono y texto en blanco), transparente con texto
  `textOnDarkMuted` cuando no.
- Footer: `Divider(color: Color(0xFF1B4437))` + avatar circular + nombre/ID.
- `Spacer()` empuja el footer al final.

### 6.3 `MobileBottomNav`

```dart
BottomNavigationBar(
  currentIndex: selectedIndex.clamp(0, bottomNavItems.length - 1),
  onTap: (index) {
    if (index == bottomNavItems.length - 1) {
      onMoreTap?.call(); // abre el drawer
    } else {
      final screenIndex = bottomNavToScreen[index];
      if (screenIndex != null) onSelect(screenIndex);
    }
  },
  backgroundColor: AppColors.sidebarBg,
  selectedItemColor: AppColors.brandGreen,
  unselectedItemColor: AppColors.textOnDarkMuted,
  type: BottomNavigationBarType.fixed,
  showUnselectedLabels: true,
  selectedFontSize: 11,
  unselectedFontSize: 11,
  items: bottomNavItems
      .map((item) => BottomNavigationBarItem(icon: Icon(item.icon), label: item.label))
      .toList(),
);
```

### 6.4 `FullDrawer` (mobile/tablet)

Mismo fondo `sidebarBg`, encabezado con avatar + marca, `Divider`, y
`ListView` de `ListTile` donde el seleccionado usa
`brandGreen.withValues(alpha: 0.1)` de fondo y texto `brandGreen`.
Cada `ListTile.onTap` llama a `onSelect(i)` **y** `Navigator.pop(context)`.

### 6.5 `DashboardTopBar`

```dart
Row(
  children: [
    if (showMenuButton) ...[
      IconButton(
        onPressed: onMenuTap,
        icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
      ),
      const SizedBox(width: 4),
    ],
    Expanded(
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      ),
    ),
  ],
)
```

En desktop el botón hamburguesa **no aparece**; en tablet/mobile sí.

### 6.6 Salto programático de módulo

Una pantalla también puede **mandar** al usuario a otro módulo sin recibir
parámetros: el carrito del catálogo lo hace al generar una orden, para
continuar directo en la fase de venta (el módulo `Ventas`).

```dart
(widget.onNavSelect ?? NavScope.onSeleccionarDe(context))(navVentas);
```

- `navVentas` (= 4) vive en `sidebar.dart`, junto a `navItems`, que es la
  fuente de verdad de los índices (moverlo obligaría a revisar el `switch`
  de `MainScreen`).
- Se usa el `onNavSelect` de la pantalla cuando la pasaron (lo hacen los
  tests) y si no el del `NavScope`: así ninguna pantalla se queda sin
  navegación al pintarse aislada.
- El índice **no** se lee con `NavScope.indiceDe(context)`: eso registra
  dependencia y redibujaría la página entera en cada salto. Solo se llama al
  callback.

---

## 7. Componentes compartidos de `responsive_layout.dart`

### 7.1 `PageHeader` — título + acción

Se apila en vertical cuando `constraints.maxWidth < 500`, en fila cuando es más ancho.

```dart
PageHeader(
  title: 'Gestión de Clientes',
  count: _controller.clientes.length,     // opcional: muestra "Título (n)"
  buttonLabel: 'Nuevo Cliente',
  onButtonPressed: () => _abrirFormulario(),
  buttonIcon: Icons.add,                  // opcional
)
```

- **`< 500`**: `Column` con título arriba y botón `stretch` abajo (gap 12).
- **`>= 500`**: `Row` con `mainAxisAlignment.spaceBetween`, título en
  `Flexible` + `overflow: TextOverflow.ellipsis` (nunca desborda), botón con
  `padding: horizontal 16 / vertical 10`.
- Botón primario: `ElevatedButton.icon` con `backgroundColor: brandGreen`,
  `foregroundColor: Colors.white`.

### 7.2 `MobileCardContainer` — card base en mobile

```dart
Container(
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.cardBg,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.cardBorder),
  ),
  child: child,
)
```

### 7.3 `PaginationControls` + `PaginationMixin`

- Botones de 36×36, radio 8, borde `cardBorder`; la página activa se rellena
  con `brandGreen` y texto blanco.
- El mixin da `pageItems(list)`, `pageCount(list)`, `goToPage`, `resetPage` y
  `buildPagination(list)` — 10 ítems por página.
- Uso en cualquier tabla:

```dart
class _MiTablaState extends State<MiTabla> with PaginationMixin {
  @override
  Widget build(BuildContext context) {
    final items = pageItems(widget.datos);
    return Column(children: [
      LayoutBuilder(builder: (context, c) =>
          c.maxWidth < 700 ? _buildMobileCards(items) : _buildDesktopTable(items)),
      buildPagination(widget.datos),
    ]);
  }
}
```

### 7.4 `ResponsiveTableWrapper`

`SingleChildScrollView` horizontal de respaldo cuando una tabla excede el ancho.

---

## 8. Patrón de pantalla (plantilla estándar)

Todas las pantallas del proyecto siguen **exactamente** esta forma:

```dart
class ClientesScreen extends StatefulWidget {
  final int? selectedNav;
  final ValueChanged<int>? onNavSelect;
  const ClientesScreen({super.key, this.selectedNav, this.onNavSelect});
  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _controller = ClientesController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _controller.cargarClientes();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _abrirFormulario({dynamic existente}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ClienteForm(
        existente: existente,
        onSubmit: (cliente) async {
          if (existente != null) {
            await _controller.actualizarCliente(cliente);
          } else {
            await _controller.crearCliente(cliente);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(existente != null ? 'Cliente actualizado' : 'Cliente creado')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      selectedNav: widget.selectedNav,
      onNavSelect: widget.onNavSelect,
      title: 'Clientes',
      contentBuilder: (context, constraints) => _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_controller.isLoading) return const Center(child: CircularProgressIndicator());
    if (_controller.error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.negativeRed),
        const SizedBox(height: 16),
        Text('Error: ${_controller.error}', style: const TextStyle(color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _controller.cargarClientes, child: const Text('Reintentar')),
      ]));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Gestión de Clientes',
        count: _controller.clientes.length,
        buttonLabel: 'Nuevo Cliente',
        onButtonPressed: () => _abrirFormulario(),
      ),
      const SizedBox(height: 20),
      if (_controller.clientes.isEmpty)
        Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const Center(child: Text('No hay clientes', style: TextStyle(color: AppColors.textSecondary))),
        )
      else
        ClienteTable(
          clientes: _controller.clientes,
          onEdit: (c) => _abrirFormulario(existente: c),
          onDelete: (c) => ClienteActions.confirmarEliminar(context, c, () async {
            try {
              await _controller.eliminarCliente(c.id);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.negativeRed));
            }
          }),
        ),
    ]);
  }
}
```

**Los 4 estados siempre presentes:** `isLoading` → `error` (+ botón Reintentar)
→ `vacío` → `con datos`. Esta estructura es idéntica en todos los módulos.

---

## 9. Patrón de tabla responsive (el más importante)

**Regla: `constraints.maxWidth < 700` → tarjetas apiladas; si no → tabla.**

### 9.1 Versión desktop/tablet (>= 700)

```dart
Widget _buildDesktopTable(List<Dato> items) {
  return Container(
    decoration: BoxDecoration(
      color: AppColors.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(children: [
      // Encabezado
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
        child: const Row(children: [
          Expanded(flex: 3, child: Text('Nombre', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 13))),
          Expanded(flex: 3, child: Text('Email',   style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 13))),
          Expanded(flex: 2, child: Text('Teléfono',style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 13))),
          SizedBox(width: 76), // columna de acciones
        ]),
      ),
      // Filas
      ...items.map((d) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
        child: Row(children: [
          Expanded(flex: 3, child: Text(d.nombre, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 3, child: Text(d.email ?? '-', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 2, child: Text(d.tel ?? '-', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(width: 76, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => onEdit(d), color: AppColors.brandGreen, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
            const SizedBox(width: 4),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => onDelete(d), color: AppColors.negativeRed, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
          ])),
        ]),
      )),
    ]),
  );
}
```

Claves visuales:
- Las columnas se dimensionan con **`Expanded(flex: n)`**, nunca con anchos fijos
  (excepto la columna de acciones, `SizedBox(width: 56–76)`).
- Última columna de acciones **alineada a la derecha** (`MainAxisAlignment.end`).
- Toda celda lleva `maxLines: 1` + `overflow: TextOverflow.ellipsis`.
- Separador inferior en cada fila; **sin** bordes verticales ni sombras.

### 9.2 Versión mobile (< 700)

```dart
Widget _buildMobileCards(List<Dato> items) {
  return Column(
    children: items.map((d) => MobileCardContainer(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(d.nombre,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => onEdit(d),
                color: AppColors.brandGreen, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
            IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => onDelete(d),
                color: AppColors.negativeRed, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
          ]),
        ]),
        const SizedBox(height: 8),
        _buildInfoRow('Email', d.email ?? '-'),
        _buildInfoRow('Teléfono', d.tel ?? '-'),
      ]),
    )).toList(),
  );
}

Widget _buildInfoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$label: ', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
    ]),
  );
}
```

Claves mobile:
- El **nombre principal** en 16px `w600` a la izquierda + acciones a la derecha.
- El resto de columnas se convierten en **pares `label: valor`** de 13px.
- `Expanded` en el valor ⇒ nunca desborda aunque el texto sea largo.
- Chips de estado con fondo a 10% de opacidad:
  `AppColors.positiveGreen.withValues(alpha: 0.1)` / `negativeRed.withValues(alpha: 0.1)`.

---

## 10. Grids de KPIs responsive

```dart
LayoutBuilder(
  builder: (context, boxConstraints) {
    final width = boxConstraints.maxWidth;
    int crossAxisCount;
    if (width >= 1100) {
      crossAxisCount = 4;
    } else if (width >= 700) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 2;
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(), // el scroll lo da la raíz
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      children: [ /* ...cards... */ ],
    );
  },
)
```

**Nunca** olvidar `shrinkWrap: true` + `NeverScrollableScrollPhysics()`:
el `ResponsiveLayout` ya provee el `SingleChildScrollView` y un `GridView`
scrolleable dentro rompería el layout (o duplicaría el scroll).

Card de KPI:

```dart
Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: AppColors.cardBg,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: AppColors.cardBorder),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Icon(icon, color: color, size: 32),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: AppColors.textSecondary)),
      ]),
    ],
  ),
)
```

---

## 11. Filtros y chips

**Siempre `Wrap`, nunca `Row`** — así los filtros saltan de línea en mobile en
vez de desbordar:

```dart
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    _chip('Ventas', 'ventas'),
    _chip('Productos', 'productos'),
    _chip('Resumen', 'resumen'),
  ],
)

Widget _chip(String label, String valor) {
  final sel = _tipoActual == valor;
  return FilterChip(
    label: Text(label),
    selected: sel,
    onSelected: (_) => setState(() => _tipoActual = valor),
    selectedColor: AppColors.brandGreen,
    checkmarkColor: Colors.white,
    labelStyle: TextStyle(
      color: sel ? Colors.white : AppColors.textSecondary,
      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
    ),
  );
}
```

---

## 12. Formularios (bottom sheet)

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,                 // obligatorio para teclado
  backgroundColor: AppColors.cardBg,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => MiForm(onSubmit: (dato) async { ... }),
);
```

Dentro del form:

```dart
Padding(
  padding: EdgeInsets.only(
    left: 24, right: 24, top: 24,
    bottom: MediaQuery.of(context).viewInsets.bottom + 24, // teclado
  ),
  child: Form(
    key: _formKey,
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nuevo Cliente', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 20),
        TextFormField(decoration: _inputDecoration('Nombre *'), ...),
        const SizedBox(height: 12),
        // ... más campos con gap 12
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(              // Cancelar
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.cardBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textSecondary)),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(              // Crear / Actualizar
            onPressed: _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_esEdicion ? 'Actualizar' : 'Crear'),
          )),
        ]),
      ]),
    ),
  ),
)
```

Decoración de input estándar:

```dart
InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(color: AppColors.textSecondary),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.cardBorder)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.brandGreen)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
)
```

Los dos botones van **en `Row` de `Expanded`** ⇒ se adaptan solos a cualquier
ancho de sheet.

### Vista de detalle (solo lectura)

`RecursoTabla` tiene el botón 👁 (`onVer`) para abrir la ficha de un registro.
Hay dos sabores:

1. **Ficha genérica** — `RecursoForm(soloLectura: true)`: mismos campos y
   etiquetas que la edición, deshabilitados y con un único botón «Cerrar».
   La abre `RecursoContenido._verDetalle` con `campos`/`valores` de la
   pantalla; no toca el controller ni envía nada (ver
   `test/vista_detalle_test.dart`).

2. **Ficha con sub-recursos** — cuando el listado no basta (Ventas), el módulo
   tiene su propia hoja: `lib/presentation/widgets/detalle_venta.dart` con
   `mostrarDetalleOrden(...)` / `mostrarDetalleBoleta(...)`. Añade lo que la
   tabla no muestra: **ids traducidos a nombres** (cliente/empleado salen de
   las listas ya cargadas, sin llamada extra), fechas en local y las **líneas
   de la orden** (producto, `cantidad × precio`, monto), con los estados del
   patrón (`VistaCargando` → `VistaError` → `VistaVacia` → lista).

```dart
// ventas_page.dart
Future<void> _verOrden(Recurso orden) => mostrarDetalleOrden(
  context,
  orden: orden,
  clientes: _clientes.items,          // sin pedirlos otra vez
  empleados: _empleados.items,
  onCargarDetalles: _ordenes.detalles, // el único viaje a la API
);
```

Para leer **un** registro (y sus sub-recursos) existe
`RecursoRepository.obtener(ruta)` → `GET /api/v1/{ruta}`; `GET /ordenes/1`
devuelve la cabecera más `detalles`. Ojo: los listados exigen `id` en cada
item y las líneas de orden **no lo traen** (su clave natural es el producto),
por eso `OrdenesController.detalles` construye el `Recurso` a mano con
`productoId`. La hoja no lee providers: recibe todo por parámetro, así se pinta
aislada en tests.

### Vendedor por defecto (la cuenta conectada)

El formulario «Nueva Orden» (Ventas) y la caja del carrito (catálogo)
preseleccionan el **vendedor de la sesión** en su desplegable, y la persona
puede cambiarlo —o volver a «— Sin asignar —»— antes de guardar:

```dart
// Se lee en la PÁGINA y se pasa al widget: el bottom sheet queda montado
// fuera del `SesionScope`, allí no habría sesión que leer.
empleadoPorDefecto: SesionScope.de(context)?.usuario.empleadoId,
```

- El id solo se aplica si existe en la lista de empleados: los desplegables
  exigen que su valor esté entre sus opciones, así que si no aparece se
  arranca en «— Sin asignar —».
- Si la lista llega vacía (hoja abierta recién, API lenta) **se espera la
  carga antes de abrir**: `if (empleados.items.isEmpty) await empleados.cargar();`
  Sin eso el select solo tendría «Sin asignar»: ni saldría el de la sesión ni
  se podría elegir otro.
- `CatalogoPage` precarga `EmpleadosController` en su `initState`, igual que
  `ClientesController` (ver `precargarDespuesDelPrimerFrame`).
- En el cuerpo de `POST /ordenes` viaja `empleadoId`, y solo si hay uno
  elegido.

### Desplegables con buscador

Todos los selectores del proyecto (formularios, catálogo, carrito) usan
`DesplegableBuscable` (`presentation/widgets/desplegable_buscable.dart`):
se pinta igual que un `DropdownButtonFormField` —rótulo, auxiliar, borde y
`validator`— y al pulsarlo abre una hoja con **la lista completa** y un campo
para escribir y filtrar con el teclado (`normalizarTexto`: sin tildes ni
mayúsculas). `Intro` elige la primera coincidencia; si no queda ninguna,
avisa con «Sin coincidencias para «texto»».

- Es un `FormField<String>` de verdad: la validación, el `errorText` y el
  modo detalle (`habilitado: false`) siguen intactos.
- **Alta de la opción desde el campo**: un desplegable que sabe crear su
  propio registro recibe `etiquetaCrear` + `onCrear` en su `CampoFormulario`
  (los tres del formulario de producto: categoría, presentación y proveedor).
  Entonces `RecursoForm` pinta un botón **«+» al lado del campo** —sin abrir
  la hoja— y la hoja de opciones muestra su botón al pie («busco y no está →
  la creo aquí»). Las dos vías llaman a `pedirNombreAlta`, que pide el nombre,
  ejecuta `onCrear` (`RecursoController.crear` ya recarga el listado) y deja
  el registro nuevo seleccionado en el campo.
  Truco interno: un `FormField` solo toma `initialValue` al montarse, así que
  al crear se sube la **clave** del campo (`_revisiones`) para que se pinte
  con el id nuevo.
- **Alta completa con diálogo propio (`onAlta`)**: cuando el registro no se
  resume en un nombre —cliente y empleado piden toda la ficha—, el
  `CampoFormulario` (o el `DesplegableBuscable` suelto) lleva `onAlta`
  (`Future<String?> Function()`) **en lugar de** `onCrear`: no se pide el
  nombre, el flujo abre su propia hoja y devuelve el valor a elegir, o `null`
  si se cancela. Ese diálogo y las fichas viven en
  `presentation/widgets/alta_persona.dart`: `camposCliente` / `camposEmpleado`
  son **la misma lista** que usan `ClientesPage` y `EmpleadosPage`, así que
  etiquetas, límites y validaciones no se descuelgan, y `altaCliente(...)` /
  `altaEmpleado(...)` montan un `RecursoForm` con `estado = ACTIVO` y
  devuelven el `Recurso` creado. Quien sabe de controladores (la página) es
  quien lo pasa como `onCrearCliente` / `onAlta`; el botón «+» y el del pie
  de la hoja siguen saliendo con `etiquetaCrear`.
- **Alta de cliente en la caja**: la hoja del carrito y «Nueva Orden» llevan
  `etiquetaCrear` + `onAlta` **directamente en el `DesplegableBuscable`**
  (no hay `CampoFormulario`): el botón «Nuevo cliente» sale al pie de la hoja
  de opciones y solo si la cuenta tiene `clientes.crear` (si no, la página no
  pasa `onCrearCliente` y no aparece). Detalle importante: esas hojas reciben
  sus listas **al abrirse**, mientras que `RecursoController.crear` recarga
  la copia del controlador, así que el panel guarda la suya en un campo
  (`_clientes`) y la reconstruye con el `Recurso` del alta (sin duplicar,
  por si la fuente compartía memoria). Al cambiar la identidad de la fuente
  se invalida la caché de opciones y el cliente nuevo queda listado, elegido
  y resoluble a nombre en el cuerpo de la orden.
- **«Nombre Apellido»**: `nombreCompletoDe(item)` (`recurso_tabla.dart`) une
  `apellido` (migración `011_apellido_personas`) al `nombre` **solo si
  existe**, así que los registros antiguos no cambian y el resto de recursos
  siguen con su etiqueta de siempre. Lo usan `opcionesDe` (todos los
  selectores), `nombreDe` (fichas, recibos y PDF) y las copias
  `nombreCliente` de la orden y de la cotización; las tablas de Clientes y
  Empleados, además, sacan su columna **Apellido**.
- El buscador pide foco solo si hay más de ocho opciones: en listas cortas
  no conviene lanzar el teclado.
- El selector de vendedor **solo lista empleados de cargo «Vendedor»**
  (`vendedoresDe` → `esVendedor`; el `cargo` es texto libre en la BD, se
  compara en minúsculas y por **contener**) **más el de la sesión**, por si
  su cargo es otro: el vendedor por defecto nunca puede quedar fuera de sus
  propias opciones. La ficha de detalle sigue recibiendo la lista completa
  (`empleados.items`), que traduce nombres de cualquier cargo.

### Diálogo de confirmación de eliminación

```dart
showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Eliminar Cliente'),
    content: Text('¿Eliminar a "${dato.nombre}"?'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
      TextButton(
        onPressed: () { Navigator.pop(ctx); onConfirm(); },
        child: const Text('Eliminar', style: TextStyle(color: AppColors.negativeRed)),
      ),
    ],
  ),
);
```

---

## 13. Widgets visuales de dashboard (opcionales)

En `lib/core/widgets/` hay componentes reutilizables de data-viz que puedes
copiar tal cual:

| Widget | Descripción |
|--------|-------------|
| `stat_card.dart` | KPI claro con valor, chip de variación ↑/↓ y mini gráfico |
| `mini_bar_chart.dart` | Barras normalizadas 0..1 para inserts en KPIs |
| `ring_gauge.dart` | Anillo de progreso con trazo redondeado (`value` 0..1) |
| `dark_metric_cards.dart` | Tiles oscuros (`darkCardBg`) con `RingGauge` a la izquierda |
| `waste_processing_card.dart` | Card clara con anillo grande |
| `sources_usage_card.dart` | Lista de fuentes con `LayoutBuilder` interno |
| `renewable_energy_card.dart` | Card con lista de energías y porcentajes |
| `community_banner.dart` | Banner con `LinearGradient` |

Convención de estos componentes: **cards oscuras sin borde y radio 18**,
**cards claras con borde `cardBorder` y radio 16–20**, texto secundario en
11.5–13.5px.

### 13.1 Gráficos reales del dashboard (`fl_chart`)

Lo que sí está en uso es `presentation/widgets/graficos_dashboard.dart` (6
tarjetas) + `presentation/widgets/graficos_ranking.dart` (barras
horizontales reutilizadas), montado en `dashboard_page.dart` entre los KPIs y
las tarjetas de estado/alertas, con la librería **`fl_chart`**:

| Gráfico | Tipo | Datos |
|---------|------|-------|
| «Ventas por día (Bs)» | `BarChart` con degradado `brandGreenDark → brandGreen` | suma de `total` por `fechaOrden` (solo `PAGADO` si las hay; si no, todas), últimos 7 días — 5 si la tarjeta baja de 420px para que las etiquetas X no se pisen |
| «Órdenes por estado» | `PieChart` con hueco central (`centerSpaceRadius` 40) y el total en el centro | conteo de `estado` ordenado de mayor a menor, leyenda de colores (máx. 5 filas + «+N más») |
| «Productos más vendidos» | `GraficoHorizontal` (barras) | `GET /reportes/productos-vendidos?orden=desc`, 6 filas: unidades en la barra, tooltip con «uds · Bs monto» |
| «Productos menos vendidos» | `GraficoHorizontal` | lo mismo con `orden=asc`: incluye los productos **con 0 ventas** (el riel gris de `backDrawRodData` los hace visibles) |
| «Productos por vencer» | `GraficoHorizontal` | `productos.fechaVencimiento` calculada contra hoy: ventana de `Ajustes.diasVencimiento` (90 por defecto, que llega como el parámetro `diasUmbral` de `GraficosDashboard`) + ya vencidos, ordenados por urgencia. Eje = días restantes (los vencidos, en 0, con el nombre en rojo); color por urgencia (`negativeRed` vencido · `warningOrange` ≤ 30 días · `infoBlue` el resto) |
| «Clientes con más compras» | `GraficoHorizontal` | agrupación por `clienteId` de `ordenes` **no anuladas** (`PENDIENTE`/`PAGADO`), de la que más tiene a la que menos: barra = nº de órdenes, tooltip con el monto |

**Barras horizontales.** `fl_chart` solo dibuja barras verticales, así que
`GraficoHorizontal` gira el gráfico entero con `rotationQuarterTurns: 1`.
En el sistema girado `bottomTitles` cae en la franja **izquierda** (nombres,
`reservedSize` 104px, 78 si la tarjeta baja de 340) y `rightTitles` en la
**inferior** (valores); los rótulos se contrarrotan solos (`SideTitleWidget`
aplica `-rotationQuarterTurns`), así que el texto queda en horizontal. La
franja de nombres corta cada rótulo a 22 caracteres con `…` para que un
producto largo no invada las barras, y el primer dato (`x = 0`) aparece
arriba: orden de ranking natural.

**Rejilla.** `LayoutBuilder` reparte las 6 tarjetas en **2 columnas por
encima de 800px** (mismo corte que el resto del dashboard) y en 1 columna
por debajo; las filas usan `crossAxisAlignment.start` para que una tarjeta
alta no estire a su pareja.

Reglas que sostienen el rendimiento:

- **Caché por identidad**: los grupos se recalculan en `initState` /
  `didUpdateWidget` solo cuando cambia la identidad de `ordenes.items` o de
  `productos.items` (el controlador asigna lista nueva en cada recarga),
  nunca en `build`. Los dos rankings llegan ya agregados del servidor, así
  que solo se mapean a `DatoRanking`.
- **Altura fija de 200px** en las seis tarjetas: el gráfico no mide texto en
  cada frame y las parejas del `Row` quedan alineadas.
- Sin datos se pinta un texto, **nunca un `BarChart` vacío** (evita el caso
  límite de `maxY = 0`), y el error del endpoint de reportes queda confinado
  en sus dos tarjetas: no bloquea el resto del dashboard.
- Las animaciones implícitas de `fl_chart` son de 250 ms y acotadas, así que
  `pumpAndSettle` de los tests sigue terminando.

**Fuente de datos de los rankings.** Los dos primeros gráficos salen del
endpoint nuevo `GET /api/v1/reportes/productos-vendidos` (capa `Reportes` en
el backend + `ReportesController` en el frontend, ambas peticiones en paralelo
con `Future.wait`); los de vencimientos y clientes se derivan en cliente de
`productos` y `ordenes`, que el dashboard ya carga.

---

## 14. Checklist para portar el diseño a otro proyecto

### Paso 1 — Archivos base (copiar sin modificar)

```text
lib/
├── core/
│   ├── theme/
│   │   └── app_colors.dart          ← paleta completa
│   └── widgets/
│       ├── responsive_layout.dart   ← ResponsiveLayout, PageHeader,
│       │                              MobileCardContainer, PaginationControls,
│       │                              PaginationMixin, ResponsiveTableWrapper
│       ├── sidebar.dart             ← NavItem, navItems, Sidebar,
│       │                              MobileBottomNav, FullDrawer
│       ├── dashboard_top_bar.dart   ← DashboardTopBar
│       ├── stat_card.dart           ← (opcional) KPI
│       ├── mini_bar_chart.dart      ← (opcional)
│       ├── ring_gauge.dart          ← (opcional)
│       └── ... resto de data-viz    ← (opcional)
```

Ajustar en `sidebar.dart`: lista `navItems`, `bottomNavItems`,
`bottomNavToScreen`, nombre de marca y avatar.

### Paso 2 — `main.dart`

- `ThemeData(useMaterial3: true, scaffoldBackgroundColor: AppColors.pageBg, ...)`.
- `MainScreen` con `ValueNotifier<int>` + `switch` que construye la pantalla
  según el índice, envuelto en un `NavScope`. Las pantallas se crean como
  widgets **`const`** (sin `selectedNav`/`onNavSelect`): así, al cambiar de
  módulo los elementos existentes comparan igual por identidad y **no se
  reconstruyen** —solo cambia el `index` del `IndexedStack` y se repinta la
  navegación—; antes, cada pantalla visitada se redibujaba entera (con su
  grid o tabla) en cada clic del sidebar. Pasar los parámetros sigue siendo
  válido (lo hacen los tests), pero entonces su página se reconstruye.

### Paso 3 — Una pantalla modelo

Copiar la plantilla de la §8 con sus 4 estados (`loading` / `error` / `vacío`
/ `datos`) y su `PageHeader`.

### Paso 4 — Una tabla modelo

Copiar el patrón doble de la §9 con `LayoutBuilder` + `PaginationMixin`.

### Paso 5 — Un form modelo

Copiar el bottom sheet de la §12.

### Paso 6 — Validar responsividad

Probar en estas 4 anchuras y verificar:

| Ancho | Debe verse |
|-------|------------|
| `>= 1100` | Sidebar 240px visible, **sin** bottom nav, sin hamburguesa, tabla completa, grid de 4 |
| `900` (tablet) | Sin sidebar, bottom nav visible, hamburguesa visible, tabla completa, grid de 3 |
| `600` (móvil) | Padding 16, **tarjetas** en vez de tabla, grid de 2, header apilado si < 500 |
| `360` (móvil pequeño) | Nada desborda: textos con `ellipsis`, filtros en `Wrap` que saltan de línea |

Comandos útiles:

```bash
flutter run -d chrome --web-port=8080        # redimensionar ventana a mano
flutter run -d windows                       # arrastrar bordes
flutter run -d "iPhone 15 Pro"               # 393pt
```

---

## 15. Reglas rápidas (resumen para no romper la responsividad)

1. **Medir con `LayoutBuilder`, no con `MediaQuery.of(context)`.**
2. **3 breakpoints fijos:** 1100 (desktop), 700 (tabla/tarjeta), 500 (header).
3. **Tablas → tarjetas** por debajo de 700px, nunca scroll horizontal forzado
   como única solución.
4. **`Wrap` para chips/filtros/botones** que puedan ocupar varias líneas.
5. **Nunca anchos fijos** en columnas de contenido: usar `Expanded(flex: n)`.
6. **Todo texto de celda/valor con `ellipsis`** y `Expanded` detrás.
7. **Grids con `shrinkWrap: true` + `NeverScrollableScrollPhysics()`** dentro
   del `SingleChildScrollView` raíz.
8. **Bottom nav máximo 5 ítems**, el último abre el `Drawer`.
9. **Padding 28 en desktop, 16 en mobile.**
10. **Un solo acento (`brandGreen`)** para selección, primarios y positivos;
    `negativeRed` solo para destructivos/errores.
11. **4 estados de pantalla siempre**: loading, error con "Reintentar", vacío, datos.
12. **Forms en bottom sheet** con `isScrollControlled: true` y
    `viewInsets.bottom`, botones en `Row` de `Expanded`.

---

## 16. Inventario de módulos (referencia)

En este proyecto el patrón se repite idéntico en 11 módulos:

```text
modules/
├── modulo_dashboard/     grid de KPIs responsive
├── modulo_usuarios/      tabla + form + acciones
├── modulo_producto/      tabla + form + acciones
├── modulo_cliente/       tabla + form + acciones   ← ejemplo modelo
├── modulo_venta/         tabla + form + acciones
├── modulo_citas/         tabla + filtros + form
├── modulo_inventario/    tabla + FilterChips + forms
├── modulo_reportes/      chips + contenedor de resultado
├── modulo_notificaciones/ tabla + form
├── modulo_configuracion/ tabla + form + acciones
└── modulo_pedidos/       tabla + form
```

Estructura interna recomendada por módulo:

```text
modulo_x/
├── frontend/
│   └── src/
│       ├── controllers/   ChangeNotifier (isLoading, error, datos, CRUD)
│       ├── screens/       XxxScreen → ResponsiveLayout + PageHeader
│       └── widgets/       xxx_table.dart (doble modo), xxx_form.dart, xxx_actions.dart
├── backend/               DTOs + datasource HTTP
├── database/              migraciones
└── shared/                dominio (entidades, repos, usecases)
```

## 17. Ajustes globales del sistema (`AjustesPage`)

Pantalla de **configuración por clave/valor** (último ítem del `navItems`,
índice 9): no lista registros, edita un puñado de preferencias que cambian el
comportamiento de la app. Su patrón es distinto al de los CRUD y ya está
montado en `frontend/lib/presentation/pages/ajustes_page.dart`.

### 17.1 Estructura de la pantalla

- `ResponsiveLayout` + `PageHeader(titulo: 'Ajustes del sistema')` con el
  botón **Guardar** solo para `ADMIN`.
- Cuerpo: `Wrap(spacing: 16, runSpacing: 16)` de tarjetas (una por bloque:
  «Ventas por defecto», «Catálogo y tablas», «Avisos del dashboard»,
  «Navegación»), cada una con un `Column` de campos de ancho fijo (~300–360).
  El `Wrap` se adapta solo: en desktop caben 2–3 por fila, en móvil una.
- Cada opción es un `DesplegableBuscable` con `labelText` + `helperText` y
  `habilitado: esAdmin`; los numéricos van con `sufijo` ('filas', 'unidades',
  'días') para que la etiqueta se lea sin mirar el rótulo.
- Sin `MediaQuery`: el número de columnas lo decide el propio `Wrap`.
- Quien no es `ADMIN` ve la misma pantalla con un banner de solo lectura y
  **sin** botón Guardar (los campos desactivados no abren su hoja).

### 17.2 Dónde vive el estado: `AjustesScope`

```dart
AjustesScope(              // ← en app.dart, FUERA de home:
  valores: ...,            //    por encima de MaterialApp
  child: MaterialApp(
    home: _AjustesRaiz(...)// ← ahí sí está SesionScope
```

- **Por encima de `MaterialApp`** porque las hojas modales (`showModalBottomSheet`,
  `showDialog`) se montan en el `Navigator` de la app y quedan **fuera** de
  `SesionScope`: si el scope estuviera más abajo, el formulario de «Nueva
  Orden» no leería ni la sesión ni los ajustes.
- `AjustesScope.de(context)` **no devuelve null**: devuelve un
  `AjustesValores` con `valor(clave)` / `numero(clave, defecto)` que caen en
  `Ajustes.defectos` cuando la clave no está guardada. Así las páginas y sus
  tests no cambian si la BD no tiene filas.
- La raíz (`_RaizDeSesion`) **no monta `MainScreen`** hasta que el controlador
  de ajustes esté en `loaded`/`error`: evita pintar la página inicial con los
  defectos y luego cambiar de golpe.
- Las páginas que lo aplican lo leen en **`didChangeDependencies`** (posterior
  a `initState`), y **solo si el valor está entre las opciones** del
  desplegable: un valor guardado a mano que ya no existe no rompe el combo.

### 17.3 Dónde se aplica cada clave

| Clave | Defecto | Se aplica en |
| --- | --- | --- |
| `vendedorPorDefecto` | `''` (cuenta conectada) | carrito y «Nueva Orden» |
| `tipoPagoPorDefecto` | `EFECTIVO` | carrito y «Nueva Orden» |
| `clientePorDefecto` | `''` (ocasional) | carrito y «Nueva Orden» |
| `ordenCatalogo` | `destacados` | orden inicial del catálogo |
| `paginaInicial` | `''` (Dashboard) | `MainScreen.didChangeDependencies` |
| `porPagina` | `10` | `PaginationMixin.porPagina` |
| `stockMinimo` | `5` | tarjeta «Alertas» del dashboard |
| `diasVencimiento` | `90` | «Productos por vencer» + `GraficosDashboard` |

### 17.4 Backend (tabla + endpoints)

- Tabla `ajustes` (`id`, `clave UNIQUE`, `valor`, timestamps + trigger), que
  crea la migración `005_ajustes` y refleja `sql/reset_farmacia.sql`.
- `GET /api/v1/ajustes` → `{total, items}` (cualquier sesión).
- `PUT /api/v1/ajustes` con `{"valores": {"clave": "valor"}}` →
  `{"id": 0, "actualizados": n}`. **Único endpoint con control de nivel**:
  `403 nivel_insuficiente` si la sesión no es `ADMIN`. Valida **todo el lote
  antes de escribir** (clave desconocida o rango inválido → `400`, nada se
  guarda), y solo admite valor vacío en `vendedorPorDefecto`,
  `clientePorDefecto` y `paginaInicial`.
- Registro de endpoints en `routes.dart` (`_endpoints`) y sección
  «Ajustes globales del sistema» del `README.md`.

Pruebas: `frontend/test/ajustes_page_test.dart` (pintado con defectos,
solo lectura sin `ADMIN`, guardado con el lote completo y los ajustes
mandando en «Nueva Orden»).
