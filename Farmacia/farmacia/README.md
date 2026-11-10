# Farmacia — Clean Architecture (front y back separados)

Monorepo con dos proyectos independientes, cada uno con su propio gestor de
paquetes y su propio ciclo de vida:

```
farmacia/
├── frontend/          # Aplicación Flutter (Dart)
│   ├── lib/           # Clean Architecture
│   ├── test/
│   └── pubspec.yaml
├── backend/           # API REST (Dart + Shelf + PostgreSQL)
│   ├── bin/           # Punto de entrada del servidor
│   ├── lib/           # Clean Architecture
│   ├── doc/           # openapi.json (especificación de Swagger)
│   ├── scripts/       # smoke_test.ps1 (E2E de todos los endpoints)
│   ├── sql/           # reset_farmacia.sql (esquema destructivo)
│   └── pubspec.yaml
└── README.md
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

#### Endpoints (58 operaciones sobre las 15 tablas + reportes)

| Recurso | Rutas |
|---------|-------|
| Auth | `POST /api/v1/auth/login` (pública) · `POST /api/v1/auth/logout` · `GET /api/v1/auth/me` |
|---------|-------|
| Productos | `GET/POST /api/v1/products` · `GET/PUT/DELETE /api/v1/products/{id}` · alias en español `GET /api/v1/productos` |
| Categorías | `GET/POST /api/v1/categorias` · `GET/PUT/DELETE /api/v1/categorias/{id}` |
| Presentaciones | `GET/POST /api/v1/presentaciones` · `GET/PUT/DELETE /api/v1/presentaciones/{id}` |
| Clientes | `GET/POST /api/v1/clientes` · `GET/PUT/DELETE /api/v1/clientes/{id}` |
| Proveedores | `GET/POST /api/v1/proveedores` · `GET/PUT/DELETE /api/v1/proveedores/{id}` |
| Empleados | `GET/POST /api/v1/empleados` · `GET/PUT/DELETE /api/v1/empleados/{id}` |
| Usuarios | `GET/POST /api/v1/usuarios` · `GET/PUT/DELETE /api/v1/usuarios/{id}` |
| Órdenes | `GET/POST /api/v1/ordenes` · `GET/DELETE /api/v1/ordenes/{id}` · `PUT /api/v1/ordenes/{id}/estado` · `GET/POST /api/v1/ordenes/{id}/detalles` · `DELETE /api/v1/ordenes/{id}/detalles/{productoId}` |
| Facturas | `GET/POST /api/v1/facturas` · `GET/DELETE /api/v1/facturas/{id}` · `PUT /api/v1/facturas/{id}/estado` |
| Cotizaciones | `GET/POST /api/v1/cotizaciones` · `GET/DELETE /api/v1/cotizaciones/{id}` · `PUT /api/v1/cotizaciones/{id}/estado` |
| Reportes | `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc` (agregado, no CRUD) |

**Convenciones:** las listas responden `{"total": n, "items": [...]}` y se
paginan con `?limit=&offset=` (y se filtran con `?estado=`); `PUT` es
**actualización parcial** (solo escribe los campos enviados y `null` borra el
valor); los errores son
`{"error": {"code", "message"}}` con `400` validación, `404` no existe,
`409` conflicto de negocio/integridad y `503` base de datos caída.

**Borrado lógico (nunca se borra una fila):** `DELETE` en **todas** las
tablas responde `204` pero solo escribe `estado = ELIMINADO` en la tabla
correspondiente (la migración `002_borrado_logico` añadió ese valor a los
cinco enums y la columna `estado` a `detalles_ordenes_pedidos`). El registro
conserva sus datos, fechas y referencias; los listados lo excluyen por
defecto, así que "desaparece" solo de la interfaz. Para consultarlo por API:
`GET /recurso?estado=ELIMINADO`; para restaurarlo: `PUT /recurso/{id}` con
cualquier otro estado. Repetir el `DELETE` sobre un registro ya oculto
responde `404`.

**Reglas de negocio de las ventas:** la orden se crea en `PENDIENTE` (valida
stock sin descontarlo) y lleva su **desglose de pagos** (`POST /ordenes` envía
`pagos: [{metodoPago, monto, referencia?}]`): una venta puede repartirse en
varios métodos (efectivo + Yape…), y la suma de los montos debe cuadrar con el
total (si no, `400`). Al pasar a `PAGADO` se descuenta (y si no hay stock
suficiente responde `409`), al salir de `PAGADO` se repone; una orden `PAGADO`
no se puede borrar; solo una factura por orden y solo se emite desde una orden
`PAGADO`; una factura solo se elimina si está `ANULADA`. `contrasena` es de
solo escritura: nunca se devuelve en las respuestas.

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
| `stock` entero entre 0 y 1 000 000 | `ensureNoNegativo` + `intOrNull` | `min`/`max` + solo dígitos |
| `fechaVencimiento` no anterior a hoy | `ensureFechaNoVencida` | `minFecha` (bloquea el calendario) |
| CI de 7 a 15 dígitos (carnet de identidad) | `ensureCi` | `ciValido` + tope de longitud |
| Teléfono: 6-15 dígitos (`+`, espacios, `-`, `()`) | `ensureTelefono` | `telefonoValido` |
| Edad entre 18 y 120 | `ensureEdad` | `min: 18` / `max: 120` |
| Usuario de 4-50 (`\w`, `.`, `-`) y contraseña de 8-255 | `_ensureNombreUsuario` / `_ensureContrasena` | `usuarioValido` + longitudes |
| Género `M/F/O` y estados de cada tabla | `ensureGenero` / `ensureEstado` | desplegables (solo opciones válidas) |
| Rebaja ≥ 0 y ≤ total y máx. de productos; IVA 14.94 % solo si es factura | `Ordenes` / `Facturas` | `Mín. 1`, límite de stock y tope del total |
| Máximo a rebajar por unidad ≥ 0 y ≤ precio de venta | `ensurePrecioRebaja` | `rebajaNoMayorQueVenta` |

Cobertura: `backend/scripts/smoke_test.ps1` (**157 comprobaciones** en el
script: **155** con cuenta `ADMIN` y **147** con cualquier otra — Ajustes y
Respaldos añaden 10 solo para `ADMIN` y 2 de `403` para el resto—;
incluidas las reglas nuevas y las de autenticación) y
`frontend/test/validaciones_form_test.dart`.

#### Migraciones (esquema de la farmacia)

- Aplicación automática al arrancar: `lib/src/data/database/migrations.dart`
  → `001_esquema_farmacia` crea los tipos enum, la función de auditoría,
  las 10 tablas y los 9 triggers, y deja constancia en `schema_migrations`;
  le siguen `002_borrado_logico`, `003_sesiones`,
  `004_indices_rendimiento` (índices de las claves foráneas, estados, fechas
  y del `ORDER BY` de productos: los listados del catálogo, Ventas y el
  dashboard dejan de recorrer las tablas enteras) y
  `005_ajustes` (tabla `ajustes` de la vista «Ajustes»: clave/valor, sin
  claves foráneas, así que no toca ningún dato existente).
- Recreeación completa / destructiva (manual): `sql/reset_farmacia.sql`
  → `psql -U postgres -d farmacia -f sql/reset_farmacia.sql` (incluye los
  mismos índices que la migración `004` y la tabla `ajustes`).
- **Respaldos**: la vista «Ajustes» tiene un botón «Respaldar ahora» y un
  respaldo automático (solo manual / cada día / cada semana / cada mes) que
  ejecutan `pg_dump -Fc` y guardan `respaldo_aaaa-MM-dd_HHmmss.dump` en
  `backend/backups/` (se conservan los 30 más recientes; se restauran con
  `pg_restore -d farmacia <fichero>`). El automático solo corre mientras el
  servidor está en marcha.

Tablas: `categorias`, `presentaciones`, `clientes`, `proveedores`,
`empleados`, `usuarios`, `productos`, `ordenes_pedidos`, `facturas`,
`detalles_ordenes_pedidos` y `ajustes` (+ `schema_migrations` de control).

Al añadir una tabla, crea una **migración nueva** en `migrations.dart`
(las existentes nunca se editan) y actualiza `doc/openapi.json`.

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

## Ajustes globales del sistema

La vista **Ajustes** (`presentation/pages/ajustes_page.dart`, última entrada
del sidebar) personaliza el comportamiento de la aplicación. Todo se guarda en
la tabla `ajustes` (migración `005_ajustes`), así que los valores son
**los mismos en web, en el `.exe` y en la APK**, y en cualquier equipo que
entre contra la misma base de datos.

- **Claves y valores por defecto** (`core/widgets/ajustes_scope.dart`):
  `vendedorPorDefecto` (vacío = cuenta conectada), `tipoPagoPorDefecto`
  (`EFECTIVO`), `clientePorDefecto` (vacío = ocasional), `ordenCatalogo`
  (`destacados`), `paginaInicial` (vacío = Dashboard), `porPagina` (`10`),
  `stockMinimo` (`5`) y `diasVencimiento` (`90`). Si la fila no existe, manda
  el defecto: el sistema se comporta igual que antes de existir la pantalla.
- **Lectura**: `AjustesScope` vive en la raíz de `app.dart`, **por encima de
  `MaterialApp`** (las hojas modales quedan fuera del `SesionScope`, que
  envuelve a `MainScreen` dentro de `home:`). Se aplica en el carrito y en
  «Nueva Orden» (vendedor, cliente y tipo de pago), en el orden inicial del
  catálogo, en `PaginationMixin.porPagina`, en la tarjeta «Alertas» del
  dashboard (stock mínimo y días de aviso) y en la página inicial de
  `MainScreen`.
- **Escritura**: `PUT /api/v1/ajustes` con `{"valores": {clave: valor}}`. Es
  el **único endpoint que exige nivel `ADMIN`** (`403 nivel_insuficiente` para
  el resto) y valida claves y rangos antes de escribir (`400
  ajuste_desconocido` / `valor_fuera_de_rango`); la pantalla se pinta en solo
  lectura para quien no es administrador.
- La raíz no monta `MainScreen` hasta que los ajustes estén leídos (o fallen),
  para que la página inicial y los desplegables no parpadeen con los defectos.

## Cómo añadir un módulo (ej. ventas)

1. **domain/**: entidad `Sale`, contrato `SaleRepository`, caso de uso `CreateSale`.
2. **data/**: `SaleRepositoryImpl` con SQL + migración nueva en `migrations.dart`.
3. **presentation/**: ruta `POST /api/v1/sales` (backend) / controlador + página
   (frontend), y su entrada en `backend/doc/openapi.json`.
4. **tests**: doble en memoria del repositorio para los casos de uso y UI.

El módulo de `products` está completo en ambos proyectos y sirve de plantilla.

## Tests

```sh
cd frontend && flutter test   # widgets con dobles en memoria (ya incluidos)
cd backend  && dart analyze   # el dominio se prueba sin levantar la API
```

Añade pruebas del backend en `backend/test/` (agrega `test:` a
`dev_dependencies` cuando lo hagas).

### Smoke test end-to-end

Con el servidor levantado (`dart run bin/server.dart`), recorre **todos** los
endpoints — autenticación (login, token, logout), creaciones, validaciones,
errores 400/404/409 y limpieza final:

```sh
cd backend
$env:SMOKE_USUARIO='tu.usuario'; $env:SMOKE_CONTRASENA='tu contraseña'
.\scripts\smoke_test.ps1            # o con -Usuario/-Contrasena y -Base <url>
```

**Hay que pasar credenciales de un usuario existente** (salen en la sección
`Usuarios`); sin ellas el script avisa y el resto de pruebas falla con 401.

Solo crea y borra filas marcadas con `[smoke]`; los datos reales de la base
no se tocan. Cualquier `FAIL` señala una ruta rota o una regla de negocio
regresionada.
