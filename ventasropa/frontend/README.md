# Ventas Frontend

Aplicación Flutter para la gestión de la tienda. Diseño responsive (desktop/tablet/mobile) con Clean Architecture.

## Arquitectura

```
lib/
├── app/
│   ├── app.dart               # Raíz de la UI (tema, DI, rutas)
│   └── dependencies.dart      # Composition root (cableado de capas)
├── core/
│   ├── config/                # API_BASE_URL
│   ├── errors/                # Failure
│   ├── network/               # ApiClient (HTTP)
│   ├── theme/                 # AppColors
│   ├── utils/                 # Utilidades
│   ├── validation/            # Reglas de validación
│   └── widgets/               # Componentes compartidos (sidebar, layout, etc.)
├── domain/
│   ├── entities/              # Objetos de valor puros
│   ├── repositories/          # Contratos (interfaces)
│   └── usecases/              # Casos de uso (Crud, Auth, Reportes)
├── data/
│   ├── datasources/           # Fuentes de datos (HTTP, SharedPreferences)
│   ├── models/                # Serialización JSON ↔ entidad
│   └── repositories/          # Implementaciones de contratos
└── presentation/
    ├── controllers/           # ChangeNotifier (estado observable)
    ├── pages/                 # Pantallas principales
    └── widgets/               # Componentes de UI específicos
```

**Flujo:** `presentation (UI) → domain (casos de uso) → data (API)`. El dominio nunca importa `flutter`, `http` ni `provider`.

## Requisitos

- Flutter SDK `^3.13.3`
- Backend corriendo en `http://localhost:8080` (ver `backend/README.md`)

## Instalación

```sh
cd frontend
flutter pub get
flutter run
```

## Configuración de la API

Por defecto apunta a `http://localhost:8080`. Para dispositivos físicos:

```sh
# Usar la IP de la PC en la red local
flutter run --dart-define=API_BASE_URL=http://192.168.1.4:8080
```

En **web** no hace falta: la URL se deriva del host que sirve la página (`Uri.base`).

## Plataformas soportadas

| Plataforma | Comando |
|------------|---------|
| Chrome (web) | `flutter run -d chrome` |
| Windows | `flutter run -d windows` |
| macOS | `flutter run -d macos` |
| Linux | `flutter run -d linux` |
| iOS | `flutter run` (requiere Xcode) |
| Android | `flutter run` (requiere emulador/dispositivo) |

### Build de release para web

```sh
flutter build web --release
dart run tool/serve_web.dart    # 0.0.0.0:8081 con gzip + ETag
```

### Acceso desde el celular (QR)

El icono QR en la esquina superior derecha abre un diálogo con la URL de acceso. Requiere:
- PC y celular en la **misma red Wi-Fi**
- Firewall con entrada TCP 8080 (API) y TCP 8081 (web)
- Backend escuchando en `0.0.0.0:8080`

## Módulos

| Módulo | Página | Descripción |
|--------|--------|-------------|
| Dashboard | `dashboard_page.dart` | KPIs, gráficos de ventas, alertas |
| Catálogo | `catalogo_page.dart` | Tarjetas de productos con carrito integrado |
| Ventas | `ventas_page.dart` | Órdenes y boletas |
| Productos | `productos_page.dart` | CRUD de productos |
| Categorías | `categorias_page.dart` | CRUD de categorías |
| Clientes | `clientes_page.dart` | CRUD de clientes |
| Proveedores | `proveedores_page.dart` | CRUD de proveedores |
| Empleados | `empleados_page.dart` | CRUD de empleados |
| Usuarios | `usuarios_page.dart` | CRUD de usuarios (solo ADMIN) |
| Ajustes | `ajustes_page.dart` | Configuración global del sistema |

## Componentes principales

### Layout responsive

- `ResponsiveLayout` — Contenedor base que cambia según el ancho:
  - `≥ 1100px`: Sidebar fijo de 240px, grids de 4 columnas
  - `≥ 700px`: Drawer + bottom nav, grids de 3 columnas
  - `< 700px`: Tarjetas en vez de tablas, grids de 2 columnas

### Navegación

- `Sidebar` — Navegación lateral (desktop)
- `MobileBottomNav` — Barra inferior (máximo 5 ítems)
- `FullDrawer` — Menú completo (tablet/mobile)

### Formularios

- `RecursoForm` — Formulario genérico reutilizable
- `DesplegableBuscable` — Select con búsqueda (reemplaza DropdownButtonFormField)
- `CampoFormulario` — Campo con validación en cliente
- `pedirNombreAlta` — Diálogo «crear opción ahora»: el «+» al lado del
  desplegable y el botón del pie de su hoja (categorías, presentaciones,
  proveedores del formulario de producto)

### Tablas

- `BuscadorTabla` — Búsqueda por cliente (filtra por id, columnas visibles y campos)
- `RecursoTabla` — Tabla desktop/tarjetas mobile (patrón dual)
- `PaginationMixin` — Paginación con 10 ítems por página

### Dashboard

- `GraficosDashboard` — 6 tarjetas con fl_chart:
  - Ventas por día (barras)
  - Órdenes por estado (pie)
  - Productos más/menos vendidos (barras horizontales)
  - Productos por vencer (barras horizontales)
  - Clientes con más compras (barras horizontales)
- `Alertas` — Stock mínimo y productos vencidos
- `GraficosRanking` — Barras horizontales reutilizables

## Patrón de pantalla

Todas las páginas siguen esta estructura:

```dart
class MiPagina extends StatefulWidget {
  @override
  State<MiPagina> createState() => _MiPaginaState();
}

class _MiPaginaState extends State<MiPagina> {
  final _controller = MiController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _controller.cargar();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      title: 'Mi Módulo',
      contentBuilder: (context, constraints) => _buildContent(),
    );
  }

  Widget _buildContent() {
    // 4 estados siempre: loading → error → vacío → datos
  }
}
```

## Paleta de colores

| Color | Uso |
|-------|-----|
| `brandGreen` (#2FBE7A) | Acento primario, selección, botones |
| `sidebarBg` (#0B2E24) | Sidebar, bottom nav, drawer |
| `pageBg` (#EDEEEA) | Fondo de página (hueso, no blanco puro) |
| `cardBg` (#FFFFFF) | Cards claras |
| `negativeRed` (#E8604C) | Errores, acciones destructivas |
| `textPrimary` (#16241F) | Texto principal |
| `textSecondary` (#7C8983) | Labels, metadatos |

## Tests

```sh
flutter test
```

16 archivos de test cubriendo:
- Login y persistencia de sesión
- CRUD de recursos (tabla, formulario, vista detalle)
- Búsqueda y filtros
- Validaciones de formulario
- Layout responsive
- Dashboard y gráficos
- Ajustes del sistema
- Carrito de compras
- Imágenes y compresión

## Añadir un módulo nuevo

1. **`domain/entities/`** — entidad del objeto
2. **`domain/repositories/`** — contrato
3. **`domain/usecases/`** — reutilizar `Crud` o crear caso propio
4. **`data/datasources/`** — implementación HTTP
5. **`data/repositories/`** — implementación del contrato
6. **`presentation/controllers/`** — `ChangeNotifier` con `isLoading`, `error`, `datos`
7. **`presentation/pages/`** — pantalla con `ResponsiveLayout`
8. **`presentation/widgets/`** — tabla, formulario, acciones
9. **`app/dependencies.dart`** — cablear el controller
10. **`core/widgets/sidebar.dart`** — añadir a `navItems`

El módulo `clientes` sirve de plantilla completa.
