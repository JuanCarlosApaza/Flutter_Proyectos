# Ventas — Clean Architecture (front y back separados)

Sistema de **ventas, inventario y facturación**: catálogo de prendas con
tallas, colores y variantes (stock real por combinación), órdenes con desglose
de pagos, facturas, cotizaciones, clientes, proveedores, empleados, RBAC con
roles, auditoría, respaldos y asistente IA local.

Monorepo con dos proyectos independientes, cada uno con su propio gestor de
paquetes y su propio ciclo de vida:

```
ventas/
├── frontend/          # Aplicación Flutter (Dart)
│   ├── lib/           # Clean Architecture
│   ├── test/
│   └── pubspec.yaml
├── backend/           # API REST (Dart + Shelf + PostgreSQL)
│   ├── bin/           # Punto de entrada del servidor
│   ├── lib/           # Clean Architecture
│   ├── doc/           # openapi.json (especificación de Swagger)
│   ├── scripts/       # smoke_test.ps1 (E2E de todos los endpoints)
│   ├── sql/           # reset_ventas.sql (esquema destructivo)
│   └── pubspec.yaml
├── instalador/        # Inno Setup: preparar.ps1 arma el .exe instalador
└── README.md
```

> **Origen:** este proyecto nació como copia independiente de un sistema de
> farmacia, del que conserva la arquitectura y los nombres internos de
> migración (`001_esquema_farmacia` se mantiene sin tocar, porque las
> migraciones son inmutables una vez aplicadas). Lo específico de farmacia
> (vencimientos, presentaciones, estado «por vencer» y unidades que no sean
> `UN`) ya **está retirado** en los datos y en el API por la migración
> `017_ropa`, que además crea `tallas`, `colores` y `producto_variantes`.

## Arranque rápido

Requisitos: **Dart SDK ^3.13.3**, **Flutter**, **PostgreSQL 15+**.

```sh
# 1. Base de datos (una sola vez)
psql -U postgres -c "CREATE DATABASE ventas"

# 2. Backend
cd backend
copy .env.example .env        # pon DB_NAME=ventas y tu DB_PASSWORD real
dart pub get
dart run bin/server.dart      # aplica las 17 migraciones solo al arrancar

# 3. Frontend (otra terminal)
cd frontend
flutter pub get
flutter run                   # web: http://localhost:8080
```

La API queda en `http://localhost:8080`, con **Swagger UI en `/docs`**.
El primer administrador se crea solo: `POST /api/v1/usuarios` es pública
únicamente mientras la BD no tiene ningún usuario, y además existe la cuenta
permanente `carlos_admin` (rol ADMIN) que se siembra al arrancar si falta.

Verificación completa:

```sh
cd backend  && dart analyze && dart test     # 287 tests
cd frontend && flutter analyze && flutter test  # 229 tests
cd backend  && .\scripts\smoke_test.ps1 -Base http://localhost:8080 `
               -Usuario <usuario> -Contrasena '<clave>'   # 214 OK / 0 FAIL
```

## Reglas de la Clean Architecture

| Capa | Contenido | Puede depender de |
|------|-----------|-------------------|
| `presentation` | HTTP/UI, controladores, widgets, rutas | domain |
| `domain` | Entidades, casos de uso, **contratos** (interfaces) | nada de fuera |
| `data` | SQL/HTTP, modelos, implementación de contratos | domain |
| `core` | Configuración, errores, utilidades | — |

**Flujo de datos:** `presentation → domain ← data`. El dominio nunca importa
`shelf`, `postgres`, `http` ni `flutter`.

```
frontend/lib                     backend/lib
├── app/            (DI y UI)    ├── src/app.dart   (DI y arranque)
├── core/                      ├── src/core/
├── domain/                    ├── src/domain/
├── data/                      ├── src/data/
└── presentation/              └── src/presentation/
```

## Puesta en marcha

### 1. Backend

```sh
cd backend
copy .env.example .env     # ⚠️ pon tu contraseña real en DB_PASSWORD
dart pub get
dart run bin/server.dart
```

- `GET /api/v1/health` → estado del servicio y de la base de datos
- `GET /` → índice con la lista de rutas
- **`GET /docs` → Swagger UI** (interfaz para probar los endpoints en el navegador)
- **`GET /openapi.json` → especificación OpenAPI** (para importar en Postman/Insomnia)

La especificación OpenAPI está en `backend/doc/openapi.json`; si añades un
endpoint, actualízala ahí. Se puede desactivar con `DOCS_ENABLED=false` en
`.env` (por defecto está activa en desarrollo y desactivada en producción).

#### Endpoints (96 rutas sobre 23 tablas, más `/docs` y `/openapi.json`)

| Recurso | Rutas |
|---------|-------|
| Sistema | `GET /` · `GET /api/v1/health` · `GET /api/v1/network` (IP para el QR) · `POST /api/v1/network/hotspot` |
| Auth | `POST /api/v1/auth/login` (pública) · `POST /api/v1/auth/logout` · `GET /api/v1/auth/me` |
| Productos | `GET/POST /api/v1/products` · `GET/PUT/DELETE /api/v1/products/{id}` · alias en español `GET/POST /api/v1/productos` y `GET/PUT/DELETE /api/v1/productos/{id}` |
| Variantes | `GET/POST /api/v1/productos/{id}/variantes` · `PUT/DELETE /api/v1/variantes/{id}` (aquí se escribe el `stock` real) |
| Categorías | `GET/POST /api/v1/categorias` · `GET/PUT/DELETE /api/v1/categorias/{id}` |
| Tallas | `GET/POST /api/v1/tallas` · `GET/PUT/DELETE /api/v1/tallas/{id}` |
| Colores | `GET/POST /api/v1/colores` · `GET/PUT/DELETE /api/v1/colores/{id}` |
| Clientes | `GET/POST /api/v1/clientes` · `GET/PUT/DELETE /api/v1/clientes/{id}` |
| Proveedores | `GET/POST /api/v1/proveedores` · `GET/PUT/DELETE /api/v1/proveedores/{id}` |
| Empleados | `GET/POST /api/v1/empleados` · `GET/PUT/DELETE /api/v1/empleados/{id}` |
| Usuarios | `GET/POST /api/v1/usuarios` · `GET/PUT/DELETE /api/v1/usuarios/{id}` |
| Roles (RBAC) | `GET/POST /api/v1/roles` · `GET/PUT/DELETE /api/v1/roles/{id}` (el `PUT` acepta `permisos`; no existe `/roles/{id}/permisos`) |
| Órdenes | `GET/POST /api/v1/ordenes` · `GET/DELETE /api/v1/ordenes/{id}` · `PUT /api/v1/ordenes/{id}/estado` · `GET/POST /api/v1/ordenes/{id}/detalles` · `DELETE /api/v1/ordenes/{id}/detalles/{varianteId}` |
| Facturas | `GET/POST /api/v1/facturas` · `GET/DELETE /api/v1/facturas/{id}` · `PUT /api/v1/facturas/{id}/estado` |
| Cotizaciones | `GET/POST /api/v1/cotizaciones` · `GET/DELETE /api/v1/cotizaciones/{id}` · `PUT /api/v1/cotizaciones/{id}/estado` |
| Ajustes | `GET/PUT /api/v1/ajustes` · `GET/PUT /api/v1/ajustes/suscripcion` (`PUT` es pública: clave maestra) |
| Respaldos | `POST/GET /api/v1/respaldos` · `GET /api/v1/respaldos/{nombre}/descarga` |
| Auditoría | `GET /api/v1/auditoria` (`?usuario=&desde=&hasta=&entidad=&accion=&q=`) · `DELETE /api/v1/auditoria/antes-de/{fecha}` · `DELETE /api/v1/auditoria/todo` |
| Archivos | `POST /api/v1/archivos/imagenes` · `GET /api/v1/archivos/imagenes/{nombre}` |
| Asistente IA | `GET /api/v1/chat/estado` · `POST /api/v1/chat` · `POST /api/v1/chat/modelo/descargar` · `GET /api/v1/chat/modelo/descarga` |
| Reportes | `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc` · `GET /api/v1/reportes/ventas?desde=&hasta=&agrupacion=dia|mes|anio` · `GET /api/v1/reportes/ventas-productos?desde=&hasta=` (agregados, no CRUD; los dos últimos exigen `reportes.ver`) |

El índice `GET /` y `backend/doc/openapi.json` enumeran **92 rutas de API** (más
`/docs` y `/openapi.json` = 94 entradas/operaciones); ahí no aparecen `GET /` ni
los 5 alias en español de la fila Productos, que sí existen y sí funcionan.

**Convenciones:** las listas responden `{"total": n, "items": [...]}` y se
paginan con `?limit=&offset=` (y se filtran con `?estado=`); `PUT` es
**actualización parcial** (solo escribe los campos enviados y `null` borra el
valor); los errores son
`{"error": {"code", "message"}}` con `400` validación, `404` no existe,
`409` conflicto de negocio/integridad y `503` base de datos caída.

**Borrado lógico (nunca se borra una fila):** `DELETE` en **todas** las
tablas responde `204` pero solo escribe `estado = ELIMINADO` en la tabla
correspondiente (la migración `002_borrado_logico` añadió ese valor a los
enums y la columna `estado` a `detalles_ordenes_pedidos`). El registro
conserva sus datos, fechas y referencias; los listados lo excluyen por
defecto, así que "desaparece" solo de la interfaz. Para consultarlo por API:
`GET /recurso?estado=ELIMINADO`; para restaurarlo: `PUT /recurso/{id}` con
cualquier otro estado. Repetir el `DELETE` sobre un registro ya oculto
responde `404`.

**Reglas de negocio de las ventas:** cada línea vende una **variante**
concreta (prenda + talla + color): `POST /ordenes` lleva `items:
[{productoId, varianteId?, cantidad}]` y, si el producto tiene una sola
variante, `varianteId` se resuelve solo; con varias y sin indicarla responde
`400 variante_requerida`. La misma variante no puede repetirse en un
documento (`400 item_duplicado`). La orden se crea en `PENDIENTE` (valida
stock sin descontarlo) y lleva su **desglose de pagos** (`POST /ordenes`
envía `pagos: [{metodoPago, monto, referencia?}]`): una venta puede
repartirse en varios métodos (efectivo + Yape…), y la suma de los montos
debe cuadrar con el total (si no, `400`). Al pasar a `PAGADO` se descuenta
de cada variante (y si no hay stock suficiente responde `409`), al salir de
`PAGADO` se repone; una orden `PAGADO` no se puede borrar; solo una factura
por orden y solo se emite desde una orden `PAGADO`; una factura solo se
elimina si está `ANULADA`. `contrasena` es de solo escritura: nunca se
devuelve en las respuestas.

#### Validaciones (backend y frontend en espejo)

El backend las aplica en `domain/rules/validaciones.dart` y en los casos de
uso → responde `400` con `{"error": {"code", "message"}}`. El frontend las
repite en `core/validation/reglas.dart` y en cada `CampoFormulario`, para
avisar **antes** de enviar (error bajo el campo + filtro de entrada):

| Regla | Backend | Frontend |
|-------|---------|----------|
| Nombre/etiqueta obligatorio de 2 a 150 caracteres | `ensureNombre` | `minCaracteres` / `maxCaracteres` |
| Apellido obligatorio de 2 a 100 caracteres (clientes y empleados) | `ensureApellido` | `minCaracteres: 2` / `maxCaracteres: 100` |
| Importe finito, `>= 0`, `<= 99 999 999.99`, redondeado a 2 decimales | `ensureImporteNoNegativo` | `min` / `max` + filtro de 2 decimales |
| `precioVenta > 0` y **nunca menor que `precioCompra`** | `ensurePrecioVenta` → `precio_venta_bajo_costo` | `min: 0.01` + `ventaNoMenorQueCoste` (SnackBar) |
| `% de ganancia` al lado del precio de venta (0-999, exige precio de compra) | — (no viaja al backend: es cálculo de la pantalla) | `TipoCampo.porcentaje`: `precioVenta = precioCompra × (1 + %)`; al escribir el precio a mano, el % refleja ese margen |
| `stock` entre 0 y 999 999.999 (3 decimales), en la variante y como agregado del producto | `ensureNoNegativo` + `doubleOrNull` | `min`/`max` + filtro de 3 decimales |
| `unidad` de venta: solo `UN` (ropa vendida por unidad) | `ensureUnidad` → `unidad_invalida` | desplegable `unidadesVenta` (una sola opción) |
| Talla de 1 a 30 caracteres y color con `codigoHex` `#RRGGBB` (nombre único en la BD) | `ensureNombreTalla` / `ensureCodigoHex` → `codigo_hex_invalido` | longitud del campo + filtro de color |
| CI de 7 a 15 dígitos (carnet de identidad) | `ensureCi` | `ciValido` + tope de longitud |
| Teléfono: 6-15 dígitos (`+`, espacios, `-`, `()`) | `ensureTelefono` | `telefonoValido` |
| Edad entre 18 y 120 | `ensureEdad` | `min: 18` / `max: 120` |
| Usuario de 4-50 (`\w`, `.`, `-`) y contraseña de 8-255 | `_ensureNombreUsuario` / `_ensureContrasena` | `usuarioValido` + longitudes |
| Género `M/F/O` y estados de cada tabla | `ensureGenero` / `ensureEstado` | desplegables (solo opciones válidas) |
| Rebaja ≥ 0 y ≤ total y máx. de productos; IVA 14.94 % solo si es factura | `Ordenes` / `Facturas` | `Mín. 0.001`, límite de stock y tope del total |
| Máximo a rebajar por unidad ≥ 0 y ≤ precio de venta | `ensurePrecioRebaja` | `rebajaNoMayorQueVenta` |

Cobertura: `backend/scripts/smoke_test.ps1` (**214 comprobaciones, 0
fallos**; con una cuenta que no sea ADMIN, las 13 de Ajustes y Respaldos se
sustituyen por 2 comprobaciones de `403`) y
`frontend/test/validaciones_form_test.dart`.

#### Migraciones (esquema de la tienda)

- **Aplicación automática al arrancar:** `lib/src/data/database/migrations.dart`
  → 17 migraciones inmutables, registradas en `schema_migrations`:

  | # | Migración | Aporta |
  |---|-----------|--------|
  | 001 | `001_esquema_farmacia` | tipos enum, función de auditoría, tablas base y triggers |
  | 002 | `002_borrado_logico` | valor `ELIMINADO` en los enums + columna `estado` |
  | 003 | `003_sesiones` | tabla `sesiones` (tokens Bearer) |
  | 004 | `004_indices_rendimiento` | índices de FK, estados, fechas y `ORDER BY` |
  | 005 | `005_ajustes` | tabla `ajustes` (clave/valor de la vista Ajustes) |
  | 006 | `006_pagos` | desglose de pagos por orden |
  | 007 | `007_productos_version` | guardia de versión en productos |
  | 008 | `008_cotizaciones` | cotizaciones y sus detalles |
  | 009 | `009_roles_permisos` | `Roles`, `Permisos`, `Rol_Permisos` (RBAC) |
  | 010 | `010_auditoria` | tabla `auditoria` + renombra `boletas` → `facturas` |
  | 011 | `011_apellido_personas` | `apellido` en personas |
  | 012 | `012_ci_clientes` | `ci` en clientes |
  | 013 | `013_empleados_sin_cargo` | empleados sin cargo obligatorio |
  | 014 | `014_facturas_rebaja_iva` | rebaja e IVA en facturas |
  | 015 | `015_productos_precio_rebaja` | precio con rebaja en productos |
  | 016 | `016_ventas_fraccionadas` | `unidad`, `codigo`, `stock_minimo`, `stock` y `cantidad` fraccionados, `costo_unitario` y la tabla `movimientos_stock` (kardex) |
  | 017 | `017_ropa` | **esquema de ropa**: quita `fecha_vencimiento`, `presentacion_id` y el estado `POR_VENCER`, restringe `unidad` a `UN`, borra la tabla `presentaciones` y crea `tallas`, `colores` y `producto_variantes` (stock real por combinación); el detalle de órdenes y cotizaciones pasa a clave `(variante_id, ...)` |
  | 018 | `018_catalogo_tallas_colores_propio` | los catálogos de `tallas` y `colores` nacen vacíos: se borran las semillas de ejemplo que ningún producto usa (cada tienda los llena desde la app) |
  | 019 | `019_precio_por_variante` | crea la columna `precio` de `producto_variantes` (precio propio de cada combinación) |
  | 020 | `020_quitar_precio_por_variante` | la retira: **un único precio por producto**, el de `productos.precio_venta`, usado igual por todas sus tallas y colores |
  | 021 | `021_permisos_reportes` | módulo **`reportes`**: sus 4 permisos solo para ADMIN y `paginaInicial` de `11` a `12` (Ajustes queda la última entrada del menú) |
  | 022 | `022_proveedores_email_nit` | columnas opcionales `email` y `nit` en `proveedores` |
  | 023 | `023_descripcion_producto` | columna opcional `descripcion` en `productos` (texto libre de la ficha, máx. 2000 caracteres lo valida la API) |

  Las 001–015 viven en `migrations.dart`; la **016, la 017 y las que
  vengan** se definen una sola vez en `migraciones_compartidas.dart` (fuente
  única que el `Migrator` renderiza a PostgreSQL y a SQLite). Hay variantes
  paralelas para SQLite en `migrations_sqlite.dart` (las usa la APK con
  servidor embebido).

- **Recreeación completa / destructiva (manual):** `sql/reset_ventas.sql`
  → `psql -U postgres -d ventas -f sql/reset_ventas.sql` (incluye los
  mismos índices y tablas que las migraciones).

- **Respaldos**: la vista «Ajustes» tiene un botón «Respaldar ahora» y un
  respaldo automático (solo manual / cada día / cada semana / cada mes) que
  ejecutan `pg_dump -Fc` y guardan `respaldo_aaaa-MM-dd_HHmmss.dump` en
  `backend/backups/` (se conservan los 30 más recientes; se restauran con
  `pg_restore -d ventas <fichero>`). El automático solo corre mientras el
  servidor está en marcha.

Tablas (22 + `schema_migrations` de control = 23): `categorias`, `tallas`,
`colores`, `producto_variantes`, `clientes`, `proveedores`, `empleados`,
`usuarios`, `productos`, `ordenes_pedidos`, `pagos`, `facturas`,
`detalles_ordenes_pedidos`, `cotizaciones`, `detalles_cotizaciones`, `roles`,
`permisos`, `rol_permisos`, `sesiones`, `ajustes`, `auditoria`,
`movimientos_stock`.

Al añadir una tabla o columna, crea una **migración nueva** en
`migraciones_compartidas.dart` (las existentes nunca se editan) y actualiza
`doc/openapi.json`; `sql/reset_ventas.sql` debe recoger el mismo esquema para
que el recreate coincida.

### 2. Frontend

```sh
cd frontend
flutter pub get
flutter run
```

Apunta a `http://localhost:8080` por defecto, que **solo funciona en el
emulador/dispositivo donde corre el backend**. En un celular físico,
`localhost` es el propio teléfono: hay que pasar la IP de la PC en la LAN
(`ipconfig` → IPv4, p. ej. `192.168.1.4`):

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.1.4:8080
```

En **web** no hace falta el `--dart-define`: la URL del API se deriva del
host que sirve la página (`Uri.base`), así que funciona igual en la PC
(`localhost`) y en el celular (IP de la PC).

#### Acceso desde el celular (QR en la esquina superior derecha)

Para usar el sistema en el celular por la misma red Wi-Fi:

```sh
# 1. Backend (escucha en 0.0.0.0:8080)
cd backend && dart run bin/server.dart

# 2. Web escuchando en todas las interfaces
cd frontend && flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8081
```

En la PC, el icono de QR de la **esquina superior derecha** de la barra
superior abre un diálogo con el QR y la URL. Escanéalo con la cámara del
celular (o Google Lens): el celular abre el sistema con la IP de la PC y
habla con la API en `<misma-ip>:8080`.

- Si la página se abrió en `localhost`, la IP real la reporta
  `GET /api/v1/network` (IPv4 de la PC, redes privadas primero); si hay
  varias, el diálogo deja elegir con chips.
- El QR solo aparece en web y con ancho ≥ tablet; en el APK no aporta.

**Modo release (recomendado para el celular):** el build debug carga
`dart_sdk.js` + módulos y es lento/frágil desde el teléfono (pantalla en
blanco, errores de WebSocket del debug service). Sirve el release:

```sh
cd frontend
flutter build web --release
dart run tool/serve_web.dart          # 0.0.0.0:8081 -> build/web (MIME wasm ok)
```

El servidor incluido comprime con **gzip** lo que admite (el `main.dart.js`
+ `canvaskit.wasm` de la primera carga pasan de ~8,7 MB a ~3 MB) y manda
`ETag`, de modo que las recargas revalidan con `304` en lugar de volver a
bajar el fichero entero. Si sirves `build/web` con otro programa, conviene
activar gzip allí también.

Alternativas al servidor incluido:

```sh
python -m http.server 8081 --bind 0.0.0.0 -d build\web
flutter run --release -d web-server --web-hostname 0.0.0.0 --web-port 8081  # recompila
```

Si el celular ya había cargado la versión debug, ábrelo en **pestaña
incógnita** (o vacía la caché) para descartar recursos cacheados.

Requisitos para que el celular conecte con el backend:

- PC y celular en la **misma red Wi-Fi**.
- Firewall de Windows con entrada de **TCP 8080** (API) y **TCP 8081** (web)
  para la red privada.
- El backend escucha en `0.0.0.0:8080` (ya es el valor por defecto de
  `HOST` en `backend/.env`).
- `android:usesCleartextTraffic="true"` (añadido al manifest) porque la API
  corre por `http://`; en iOS se permitió con `NSAllowsArbitraryLoads`.

Todas las tablas llevan un **buscador** que filtra en el cliente sin
distinguir mayúsculas ni acentos (busca por id, por las columnas visibles y
por el resto de campos del registro). Cuando no hay coincidencias se muestra
el estado "Sin resultados para …" con un botón **Limpiar búsqueda**. El campo
y los chips de filtro van juntos en un `Wrap`, así que en móvil saltan de
línea en vez de desbordar (ver `BuscadorTabla` y `filtrarPorBusqueda` en
`presentation/widgets/buscador_tabla.dart`).

## Autenticación y sesión

Todas las rutas de la API exigen `Authorization: Bearer <token>`; sin él se
responde `401` con `error.code = sesion_requerida`. Excepciones **públicas**:
`GET /api/v1/health`, `GET /api/v1/network`, `POST /api/v1/auth/login`,
`GET /docs`, `GET /openapi.json`, `GET /` y las imágenes de
`/api/v1/archivos/imagenes/*` (el `Image.network` de Flutter no envía
cabeceras).

**Backend** (`lib/src/presentation/http/auth_middleware.dart` +
`routes/auth_routes.dart`):

- `POST /api/v1/auth/login` → `{"nombreUsuario", "contrasena", "recuerdame?"}`;
  devuelve `{token, usuario, expiraEn}`. Token aleatorio de 64 hex guardado en
  la tabla `sesiones` (migración `003_sesiones`): caduca a los **30 días** con
  `recuerdame` y a las **24 h** sin él.
- `GET /api/v1/auth/me` → usuario de la sesión y su expiración.
- `POST /api/v1/auth/logout` → borra la fila de `sesiones` e invalida el token
  **en el servidor** (ya no sirve de nada copiarlo).
- `POST /api/v1/usuarios` es pública solo cuando la BD no tiene ningún
  usuario (bootstrap del primer administrador); después exige sesión.
- CORS permite la cabecera `authorization` (imprescindible en web).

**Frontend** (`presentation/controllers/auth_controller.dart`, un
`ChangeNotifier` global con Provider):

- Al arrancar, `AuthController` restaura la sesión guardada y decide entre
  *splash* → *login* → *dashboard* (`app/app.dart`); la sesión se expone a los
  widgets con `SesionScope`.
- El check **"Recordar mi usuario y contraseña"** del login guarda token,
  usuario y contraseña en `shared_preferences` (`SesionLocalDataSource`) y
  rellena el formulario la próxima vez; sin el check no se persiste nada y
  solo vale la sesión temporal. Así la sesión sigue abierta al reabrir la app
  (web o exe) hasta pulsar **"Cerrar sesión"**.
- Cerrar sesión borra lo local y llama a `POST /auth/logout`; además, un
  `401` del `ApiClient` devuelve automáticamente al login (token caducado).
- ⚠️ Con "Recordarme" la contraseña queda en claro en el almacenamiento
  local del navegador/ejecutable. En la BD **ya se guarda como hash bcrypt**
  (cost 10) y cada cambio exige `claveAdmin` con la clave de quien lo hace;
  en producción convendrían además refresh tokens cifrados y HTTPS.

### Roles y permisos (RBAC)

`Roles`, `Permisos` y `Rol_Permisos` nacen en la migración `009`, con el rol
`ADMIN` sembrado (es de sistema: no se editan ni se borran sus permisos ni su
fila). `asegurarPermiso(request, modulo, accion)` se invoca al inicio de cada
ruta y devuelve `403` si la sesión no tiene ese permiso. El sidebar y las
acciones de cada página se pintan con la misma información
(`core/permisos.dart` en el frontend), así que un usuario sin permiso ni ve
la entrada del menú.

## Ajustes globales del sistema

La vista **Ajustes** (`presentation/pages/ajustes_page.dart`, última entrada
del sidebar) personaliza el comportamiento de la aplicación. Todo se guarda en
la tabla `ajustes` (migración `005_ajustes`), así que los valores son
**los mismos en web, en el `.exe` y en la APK**, y en cualquier equipo que
entre contra la misma base de datos.

- **Claves y valores por defecto** (`core/widgets/ajustes_scope.dart`):
  `nombreTienda` («Mi Tienda»), `vendedorPorDefecto` (vacío = cuenta
  conectada), `tipoPagoPorDefecto` (`EFECTIVO`), `clientePorDefecto` (vacío =
  ocasional), `ordenCatalogo` (`destacados`), `paginaInicial` (vacío =
  Dashboard), `porPagina` (`10`), `stockMinimo` (`5`), `iaRoles` (vacío =
  todos los roles pueden usar el asistente), `burbujaIA` (`1`), `qrPago`
  (imagen del QR con la que se cobra), `respaldoIntervalo` (`0` = solo
  manual) y los `defecto.<entidad><campo>` de cada desplegable. Si la fila no
  existe, manda el defecto: el sistema se comporta igual que antes de existir
  la pantalla.
- **Lectura**: `AjustesScope` vive en la raíz de `app.dart`, **por encima de
  `MaterialApp`** (las hojas modales quedan fuera del `SesionScope`, que
  envuelve a `MainScreen` dentro de `home:`). Se aplica en el carrito y en
  «Nueva Orden» (vendedor, cliente y tipo de pago), en el orden inicial del
  catálogo, en `PaginationMixin.porPagina`, en la tarjeta «Alertas» del
  dashboard (stock mínimo) y en la página inicial de `MainScreen`.
- **Escritura**: `PUT /api/v1/ajustes` con `{"valores": {clave: valor}}`. Es
  el **único endpoint que exige el permiso `ajustes.editar`** (por defecto
  solo el rol ADMIN lo tiene; `403 permiso_denegado` para el resto) y valida
  claves y rangos antes de escribir (`400 ajuste_desconocido` /
  `valor_fuera_de_rango`); la pantalla se pinta en solo lectura para quien no
  es administrador. La licencia se aparta: `PUT /api/v1/ajustes/suscripcion`
  es **pública** (clave maestra) y `GET /api/v1/ajustes/suscripcion` devuelve
  `libre` / `activa` / `bloqueada`.
- La raíz no monta `MainScreen` hasta que los ajustes estén leídos (o fallen),
  para que la página inicial y los desplegables no parpadeen con los defectos.

## Reportes

La vista **Reportes** (`presentation/pages/reportes_page.dart`, entrada
«Reportes» del menú, justo antes de Ajustes) resume las ventas de un rango de
fechas y las exporta. Es el módulo con permiso propio **`reportes`** (alta en
la migración `021`, solo para ADMIN): sin ese permiso no aparece en el menú y
la API responde `403 permiso_denegado`.

- **Dos informes con los mismos filtros:**
  - *Ventas por día / mes / año*: gráfico de barras + tabla con el **total,
    las órdenes pagadas, las unidades y el ticket medio** del rango y el
    desglose por periodo. Los periodos sin ventas se rellenan con **ceros**
    (`InformeVentas.serieCompleta`), así que un día vacío se distingue de un
    dato que falta.
  - *Productos más vendidos* y *reparto por categoría*: ranking en Bs y en
    unidades con su porcentaje sobre el total.
- **Filtros**: atajos **Hoy / Ayer / Esta semana / Este mes / Este año**, los
  botones **Desde / Hasta** con calendario (si se cruza el rango se arrastra
  el extremo contrario para no dejarlo invertido) y el selector de agrupación
  **Día / Mes / Año**. Por defecto, del día 1 del mes a hoy. El rango y la
  agrupación viven en `InformeController`, no en la página, de modo que
  volver al módulo desde otra pantalla repite la consulta con lo que estaba
  puesto (`MainScreen._refrescar` → `InformeController.recargar()`).
- **Exportación**: botón `CSV` (`core/exportar/informe_csv.dart`, separador
  `;`, coma decimal, millares con `.` y BOM UTF-8: se abre en Excel en
  español sin arruinar los números ni los acentos) y botón `PDF`
  (`presentation/widgets/informe_pdf.dart`, A4 con resumen, serie, productos,
  categorías y la nota de criterios). Ambos usan la hoja nativa del equipo
  (`guardarFichero` / `mostrarVistaPdf`).
- **Criterios** (iguales en pantalla, CSV y PDF): solo órdenes `PAGADO`, sin
  líneas `ELIMINADO`, **total bruto** (`SUM(o.total)`, antes de rebajas e
  IVA) y fechas en **hora de Bolivia (UTC−4)**, no en la UTC del servidor.
  El `hasta` es inclusivo (día completo). Como la serie, los productos y las
  categorías salen del mismo bruto, las tres sumas coinciden siempre.
- **Endpoints**: `GET /api/v1/reportes/ventas?desde=…&hasta=…&agrupacion=dia|mes|anio`
  y `GET /api/v1/reportes/ventas-productos?desde=…&hasta=…`, ambos con
  `asegurarPermiso(request, 'reportes', 'ver')` y acotados (400 periodos y
  500 productos). El antiguo `GET /reportes/productos-vendidos`, que alimenta
  el dashboard, sigue exigiendo `dashboard.ver`.

## Instalador y APK

- **Instalador Windows** (`instalador/`): `preparar.ps1` comprueba las
  compilaciones, descarga PostgreSQL y Ollama a `deps/`, arma
  `staging/servidor/` (`.env` de producción, web, contexto, `iniciar.ps1`,
  `crear_bd.ps1`) y compila `Ventas.iss` con Inno Setup →
  `salida/Ventas-Setup-<versión>.exe`.
- **APK**: se construye con servidor embebido (SQLite, sin PostgreSQL):

  ```sh
  cd frontend
  flutter build apk --release --dart-define=SERVIDOR_EMBEBIDO=1
  ```

  El binario del backend se empaqueta en la APK; `servidor_embebido_io.dart`
  lo arranca en `main.dart` solo cuando ese `dart-define` está activo. El
  escritorio y la web siguen contra el backend externo de PostgreSQL.

## Cómo añadir un módulo

1. **domain/**: entidad `Sale`, contrato `SaleRepository`, caso de uso `CreateSale`.
2. **data/**: `SaleRepositoryImpl` con SQL + migración nueva en `migrations.dart`.
3. **presentation/**: ruta `POST /api/v1/sales` (backend) / controlador + página
   (frontend), y su entrada en `backend/doc/openapi.json`.
4. **Permisos**: añade el módulo a `Modulos.todos` (`core/permisos.dart`) y a
   la migración de roles, y su entrada al `navItems` del sidebar.
5. **tests**: doble en memoria del repositorio para los casos de uso y UI.

El módulo de `products` está completo en ambos proyectos y sirve de plantilla.

## Tests

```sh
cd backend  && dart analyze && dart test     # 287 tests en 27 ficheros
cd frontend && flutter analyze && flutter test  # 229 tests en 29 ficheros
```

Añade pruebas del backend en `backend/test/`.

### Smoke test end-to-end

Con el servidor levantado (`dart run bin/server.dart`), recorre **todos** los
endpoints — autenticación (login, token, logout), creaciones, validaciones,
errores 400/404/409, concurrencia, auditoría y limpieza final:

```sh
cd backend
$env:SMOKE_USUARIO='tu.usuario'; $env:SMOKE_CONTRASENA='tu contraseña'
.\scripts\smoke_test.ps1            # o con -Usuario/-Contrasena y -Base <url>
```

**Hay que pasar credenciales de un usuario existente** (salen en la sección
`Usuarios`); sin ellas el script avisa y el resto de pruebas falla con 401.

Solo crea y borra filas marcadas con `[smoke]`; los datos reales de la base
no se tocan.

**Resultado actual: 214 comprobaciones OK / 0 fallos** contra
`http://localhost:8090` con cuenta `ADMIN`. El guion quedó actualizado al
esquema `017_ropa`: ya no prueba `presentaciones`, `fechaVencimiento`,
`POR_VENCER` ni unidades que no sean `UN`, y en su lugar cubre las variantes
(alta, `409 variante_duplicada`, `409 variante_con_stock`, `400
variante_requerida`, suma de stock), el detalle de orden por `varianteId`, el
guardia de versión con `precioVenta`, la auditoría con filtros (`?accion=`,
`?entidad=`) y las facturas en lugar de las boletas.
