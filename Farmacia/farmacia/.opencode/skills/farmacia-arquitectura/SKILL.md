---
name: Farmacia · Ritmo de construcción
description: Reglas para construir y optimizar en este proyecto (Flutter frontend + Dart Shelf backend + PostgreSQL) sin romper el estilo ni el rendimiento. Úsalo al añadir pantallas, tablas, catálogos, formularios, endpoints o migraciones, y al tocar rendimiento, navegación, imágenes, paginación, servidor web o cualquier cosa que "se note lenta". Resume arquitectura, checklist de fluidez, comandos de verificación y verdades ya medidas.
---

# Farmacia — ritmo de construcción

Este proyecto ya tiene un estilo y un nivel de rendimiento medido. Todo lo nuevo
se construye **encima de eso**, no al lado. Lee esto antes de tocar código.

## 0. Contexto y comandos

- Monorepo sin git: `frontend/` (Flutter) y `backend/` (Dart Shelf + PostgreSQL).
  La raíz `farmacia/` **no** tiene `pubspec.yaml`: los comandos se ejecutan
  **desde su carpeta** (`cd frontend`, `cd backend`).
- Backend en `http://localhost:8080` (`.env`: `DB_HOST=localhost`, `DB_PORT=5432`,
  `DB_SSL_MODE=disable`, `DB_POOL_MAX=10`). Web en `0.0.0.0:8081`.
- Verificación mínima de frontend:

  ```sh
  flutter analyze
  flutter test            # 158 tests; debe seguir en verde
  ```

- El proyecto **no es repo git**: nada queda commiteado. Si vas a borrar o
  reescribir algo grande, coméntalo antes.

## 1. Estilo (inamovible)

- Paleta `AppColors` (`core/theme/app_colors.dart`): fondo `pageBg`, cards
  `cardBg` + borde `cardBorder` (radio 16–20), acento único `brandGreen`.
- **UI y comentarios en español.**
- Breakpoints con `LayoutBuilder`, nunca `MediaQuery` para elegir layout:
  `Breakpoints` 1100 / 700 / 500.
- **Nada de `SnackBar`**: avisos con `core/widgets/alertas.dart`
  (`alertaExito`, `alertaError`, `alertaInfo`, `alertaAdvertencia`,
  `confirmarAccion`). La única excepción son diálogos con campos de datos
  (`showDialog`).
- `ResponsiveLayout` + `Breakpoints` para toda pantalla; dentro del
  `SingleChildScrollView`: `shrinkWrap: true` + `NeverScrollableScrollPhysics()`
  (`DISENO_RESPONSIVE.md` §10).
- Comentarios de cabecera explicando el **por qué**, no el qué.
- **Desplegables**: `DesplegableBuscable`
  (`presentation/widgets/desplegable_buscable.dart`), nunca
  `DropdownButtonFormField`. Se pinta igual (rótulo, auxiliar, borde,
  `validator`) y al pulsarlo abre una hoja con la lista completa y un campo
  para escribir y filtrar (`normalizarTexto`). Los de vendedor se alimentan
  con `vendedoresDe(empleados, sesion:)` → solo cargo «Vendedor» **+ la
  cuenta conectada**; la ficha de detalle sigue recibiendo la lista completa.
- **Alta desde el propio desplegable**: si al desplegable le faltan opciones,
  declara `etiquetaCrear` + `onCrear` en su `CampoFormulario` (ver los tres de
  `productos_page.dart`) y `RecursoForm` pinta un botón **«+» al lado del
  campo** (además del botón del pie de la hoja de opciones). Ambos llaman a
  `pedirNombreAlta`, que pide el nombre, ejecuta `onCrear` (el controller
  recarga solo) y el selector se queda con el registro nuevo ya elegido.
- **Alta completa (con ficha entera)**: cuando un nombre no basta, el campo
  lleva `onAlta` (`Future<String?> Function()`) **en lugar de** `onCrear`: no
  se pide el nombre, el flujo abre su propia hoja y devuelve el valor a
  elegir (`null` al cancelar). El diálogo y las fichas están en
  `presentation/widgets/alta_persona.dart`: `camposCliente` / `camposEmpleado`
  son la **misma** lista que usan `clientes_page.dart` y `empleados_page.dart`
  (no dupliques campos), y `altaCliente` / `altaEmpleado` devuelven el
  `Recurso` creado con `estado = ACTIVO`. Quien sabe de controladores (la
  página) pasa el callback; el botón «+» sigue apareciendo si hay
  `etiquetaCrear`.
- **Alta de cliente en la caja**: `carrito_panel.dart` y «Nueva Orden»
  (`ventas_page.dart`) pasan `etiquetaCrear: 'Nuevo cliente'` + `onAlta`
  **directamente al `DesplegableBuscable`** (no hay `CampoFormulario`), y solo
  si la sesión tiene `clientes.crear`. Como esas hojas reciben sus listas al
  abrirse y `crear` recarga la copia del controlador, el panel guarda la suya
  en un campo `_clientes` y la reconstruye con el `Recurso` devuelto (sin
  duplicar): cambia la identidad de la fuente, se invalida la caché de
  opciones y el cliente nuevo queda listado y elegido.
- **Nombres**: `nombreCompletoDe(item)` (`recurso_tabla.dart`) pinta
  «Nombre Apellido» cuando hay `apellido` (migración
  `011_apellido_personas`) y solo el nombre si no lo hay. Lo usan
  `opcionesDe`, `nombreDe` y las copias `nombreCliente`; las tablas de
  Clientes y Empleados tienen su columna **Apellido**.

## 2. Arquitectura (cómo se monta una pantalla nueva)

Capas: `Recurso` (entidad) → `RecursoRepository`/`RecursoDataSource` →
`RecursoController` (`ChangeNotifier`) → Provider en `app.dart` → página.

- Reutiliza `RecursoPage` + `RecursoContenido` + `RecursoForm` (patrón doble
  tabla `LayoutBuilder` + `PaginationMixin` de la §9, y plantilla de pantalla
  de la §8 de `DISENO_RESPONSIVE.md`).
- La página nueva se registra en `main_screen.dart` como widget **`const`**.
- **Ajustes globales** (`AjustesScope` en `app.dart`, **por encima de
  `MaterialApp`** porque las hojas modales quedan fuera de `SesionScope`):
  deciden vendedor/cliente/tipo de pago por defecto, orden del catálogo,
  página inicial, `porPagina`, `stockMinimo` y `diasVencimiento`. Para añadir
  uno nuevo hacen falta **tres** piezas: su clave y defecto en
  `Ajustes.defectos` (frontend), su entrada en la whitelist de
  `domain/usecases/ajuste_usecases.dart` (backend) y su desplegable en
  `ajustes_page.dart`. Solo `ADMIN` guarda (`PUT /api/v1/ajustes` → 403
  `nivel_insuficiente` para el resto); quien no lo es ve la pantalla en solo
  lectura.

## 3. Navegación (no la toques a lo viejo)

- `MainScreen` tiene un `ValueNotifier<int>` envuelto en `NavScope`
  (`core/widgets/nav_scope.dart`) + `IndexedStack`.
- Las páginas **no** reciben `selectedNav`/`onNavSelect` (son parámetros
  opcionales; los usa los tests). El índice lo leen las hojas `_NavSidebar`,
  `_NavDrawer` y `_NavBottomNav` dentro de `responsive_layout.dart`.
- **Regla**: la dependencia del índice se lee en la hoja, nunca en la página ni
  en `ResponsiveLayout.build`. Si la lees arriba, cada clic del sidebar
  reconstruye el contenido de la página y se pierde lo ganado.
- Garantía testable: `test/main_screen_test.dart` comprueba que una página
  visitada es `identical(...)` al volver. Si rompe esto, has regresado el
  rendimiento de la navegación.

## 4. Checklist de fluidez (el ritmo)

Aplicar cada punto que aplique al terminar cualquier pantalla o widget:

1. **Sin `watch` amplio en páginas con mucho contenido**: usa `context.select`
   / `Selector` para lo que cambia poco (carrito, contadores, badges).
2. **Caches por identidad + huella de filtros**: no recalcules listas
   normalizadas ni índices en `build`. Ejemplo: `_IndiceCatalogo`, `_visibles`
   en `catalogo_page.dart`.
3. **Listas largas → paginación de 24** con `PaginationMixin` +
   `PaginationControls`, rango «Mostrando X–Y de Z», controles ocultos con una
   sola página, reset a página 1 en cualquier cambio de filtro y
   `Scrollable.ensureVisible` al cambiar de página.
4. **`RepaintBoundary` por elemento repetido** (tarjetas del catálogo): capas
   reutilizables durante el scroll.
5. **Imágenes**: `cacheWidth`/`cacheHeight` = tamaño pintado ×
   `MediaQuery.devicePixelRatioOf(context)`. Nunca decodificar a tamaño
   original.
6. **Carga sin spinner**: precarga controladores en `initState` con
   `context.read(...)` — nunca con `watch`/`late` que dependa de
   `didChangeDependencies` si puedes evitarlo.
7. **Coste por frame**: si un widget se reconstruye en cada frame, que sea
   barato (texto/contenedor), no grid, tabla ni imagen.
8. **Animaciones**: se respetan las del paquete (QuickAlert 200 ms + GIF de
   cabecera). No "optimices" quitando animaciones; si algo va lento, mide.

## 5. Verificación obligatoria

Antes de dar por terminado un cambio:

```sh
cd frontend
flutter analyze           # sin incidencias
flutter test              # 158 en verde
```

Si el cambio toca el backend:

```sh
cd backend
dart analyze              # sin incidencias
dart test                 # 75 en verde
```

Si el cambio afecta a web o a escritorio, reconstruye el binario correspondiente
— **el usuario no nota nada si el build está desactualizado**:

```sh
flutter build web --release        # web: serve_web sirve build/web
flutter build windows --release    # exe: build\windows\x64\runner\Release\farmacia.exe
```

Web: tras cada rebuild, `Ctrl+Shift+R`. El servidor
`dart run tool/serve_web.dart` (8081) tiene **gzip + ETag**: primera carga
~3 MB (no 8,7 MB) y recargas en `304`.

## 6. Verdades ya medidas (no las re-investigues)

- API: mediana **1,8 ms**. PostgreSQL, pool y cliente Dart **no** tienen
  bloqueos: tras 120–180 s de reposo responde en 0–5 ms.
- Un "bloqueo de ~2 s" medido con `HttpClient` de **.NET desde PowerShell** es
  artefacto de esa medición (proxy/WPAD), no del sistema. Para medir, usa una
  sonda **Dart** con `package:http` y `package:postgres`.
- **Debug ≠ release**: `flutter run -d windows` es JIT e va 10-50× más lento.
  El rendimiento real se mide con `--release` o con el `Release\farmacia.exe`.
- El pool del backend **no** necesita keep-alive: descartado con datos.
- Migraciones en `backend/lib/src/data/database/migrations.dart` (la 004 es
  `004_indices_rendimiento` y la 005 `005_ajustes`, ambas inmutables) +
  `sql/reset_farmacia.sql` + sección «Migraciones» del README.

## 7. Trampas conocidas

- `pumpAndSettle` se atasca con `VistaCargando` (indeterminado) y con las
  alertas QuickAlert (GIF). Usa `pump(Duration)` acotado.
- Tras `alertaExito` no uses `pumpAndSettle` (QuickAlert).
- `didChangeDependencies` corre después de `initState`: `ventas_page` y
  `dashboard_page` usan campos `late` inicializados ahí. Las páginas que
  **aplican ajustes** (carrito, «Nueva Orden», catálogo, dashboard) también
  lo hacen en `didChangeDependencies`, nunca en `initState` (el scope todavía
  no se puede leer ahí).
- Error `accessibility_bridge.cc` en Windows: bug del motor con lector de
  pantalla; el `RangeSlider` de `filtros_catalogo.dart` es el trigger. No es
  código del proyecto.
- El backend **sí** tiene `test/` (`dart analyze` + `dart test` en `backend/`)
  además de `scripts/smoke_test.ps1`.
- Al abrir un `DesplegableBuscable` hay **dos** `BottomSheet` en el árbol (la
  hoja del formulario y la del selector): en tests usa
  `find.byType(BottomSheet).last` o baja por un `descendant`. Con un flujo
  `onAlta` (alta de cliente o empleado) se apilan **tres** y la de arriba es
  siempre la `.last`. Y `DropdownButtonFormField` ya no existe en el proyecto.
- Un `FormField` solo lee `initialValue` **al montarse**: no lo sincroniza
  después. Si cambias el valor de un desplegable desde fuera (alta en línea),
  sube su clave (los `_revisiones` de `recurso_form.dart`) o el campo se
  quedará mostrando el valor anterior.
- Un `TextEditingController` de un diálogo se suelta en `dispose` del widget
  del diálogo, **no** al volver de `showDialog`: la ruta sigue repintándose
  durante su animación de salida y reventaría con «used after being disposed».

## 8. Límites: qué no tocar sin preguntar

- **Backend** (`backend/lib/**`): solo con su visto bueno.
- Paginación en servidor (`limit`/`offset`, cap actual 200 en
  `api_request.dart`), debounce de búsqueda y refetch local tras mutaciones:
  pendientes, implementar solo si lo pide. Los agregados del dashboard **ya
  tienen endpoint** (`GET /api/v1/reportes/productos-vendidos`, módulo
  `reporte_*`): cualquier gráfico nuevo se añade ahí, no se calcula en el
  cliente ni se consulta `detalles_ordenes_pedidos` desde el frontend.
- No cambies el patrón de navegación, la paginación de 24 ni el estilo de
  `AppColors` sin comentarlo.

## 9. Documentación

Si cambia un patrón (navegación, paginación, servidor, migraciones), actualiza
en la misma sesión `README.md` y `DISENO_RESPONSIVE.md`. La guía es la fuente
de verdad de "cómo se construye aquí": si miente, la próxima sesión hará lo
contrario.
