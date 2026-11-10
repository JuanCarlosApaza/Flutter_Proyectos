# Ventas Backend

API REST para el sistema de gestión de la tienda. Construida con **Dart + Shelf + PostgreSQL** siguiendo Clean Architecture.

## Arquitectura

```
bin/server.dart            # Punto de entrada
lib/src/
├── app.dart               # Composición de dependencias (DI)
├── core/
│   ├── config/            # AppConfig, .env
│   ├── errors/            # AppException
│   └── utils/             # Result<T>
├── domain/
│   ├── entities/          # Objetos de valor puros (sin dependencias externas)
│   ├── repositories/      # Contratos (interfaces abstractas)
│   ├── rules/             # Validaciones y estados
│   └── usecases/          # Lógica de negocio
├── data/
│   ├── database/          # Pool PostgreSQL, migraciones
│   ├── models/            # Serialización DB ↔ entidad
│   ├── repositories/      # Implementaciones concreta (SQL)
│   └── storage/           # Almacenamiento de imágenes
└── presentation/
    ├── docs/              # Swagger UI + OpenAPI
    ├── http/              # Auth middleware, JSON response, CORS
    └── routes/            # Enrutador por módulo
```

**Flujo de datos:** `presentation (HTTP) → domain (casos de uso) ← data (SQL)`. El dominio nunca importa `shelf`, `postgres` ni `http`.

## Requisitos

- Dart SDK `^3.13.3`
- PostgreSQL 14+ corriendo en `localhost:5432`

## Instalación

```sh
cd backend
copy .env.example .env     # ⚠️ Pon tu contraseña real en DB_PASSWORD
dart pub get
dart run bin/server.dart
```

El servidor arranca en `http://localhost:8080` y aplica las migraciones automáticamente al iniciar. Si la BD no está disponible, arranca en modo degradado (health reportará `database: down`).

## Variables de entorno

| Variable | Defecto | Descripción |
|----------|---------|-------------|
| `HOST` | `0.0.0.0` | Dirección de escucha |
| `PORT` | `8080` | Puerto |
| `APP_ENV` | `development` | `development` o `production` |
| `DOCS_ENABLED` | `true` | Swagger UI en `/docs` |
| `DB_HOST` | `localhost` | Host de PostgreSQL |
| `DB_PORT` | `5432` | Puerto de PostgreSQL |
| `DB_NAME` | `ventas` | Nombre de la base de datos |
| `DB_USER` | `postgres` | Usuario de PostgreSQL |
| `DB_PASSWORD` | `postgres` | Contraseña de PostgreSQL |
| `DB_SSL_MODE` | `disable` | `disable`, `prefer` o `require` |
| `DB_POOL_MAX` | `10` | Tamaño del pool de conexiones |
| `UPLOADS_DIR` | `uploads` | Carpeta de imágenes subidas (relativa al CWD) |
| `BACKUPS_DIR` | `backups` | Carpeta de los respaldos `.dump` (relativa al CWD) |
| `PG_DUMP_BIN` | `pg_dump` | Ejecutable de `pg_dump`; si no está en el PATH, su ruta completa |

## Documentación de la API

- **Swagger UI**: [http://localhost:8080/docs](http://localhost:8080/docs)
- **OpenAPI JSON**: [http://localhost:8080/openapi.json](http://localhost:8080/openapi.json)
- **Índice de endpoints**: [http://localhost:8080/](http://localhost:8080/)

Desactivar con `DOCS_ENABLED=false` en `.env` (por defecto activa en desarrollo).

## Endpoints

### Autenticación

| Método | Ruta | Descripción | Acceso |
|--------|------|-------------|--------|
| `GET` | `/api/v1/health` | Estado del servicio y BD | Público |
| `GET` | `/api/v1/network` | IPs locales (QR de acceso móvil) | Público |
| `POST` | `/api/v1/auth/login` | Iniciar sesión | Público |
| `POST` | `/api/v1/auth/logout` | Cerrar sesión | Autenticado |
| `GET` | `/api/v1/auth/me` | Usuario de la sesión actual | Autenticado |

### Productos

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/products` | Listar productos (con `?limit=&offset=&estado=&q=`) |
| `GET` | `/api/v1/products/{id}` | Obtener un producto |
| `POST` | `/api/v1/products` | Crear producto (acepta `variantes: [{tallaId|talla, colorId|color, stock?}]`) |
| `PUT` | `/api/v1/products/{id}` | Actualizar producto (parcial; `stock` no es editable aquí) |
| `DELETE` | `/api/v1/products/{id}` | Eliminar (borrado lógico) |

Alias en español: `GET/POST /api/v1/productos` y `GET/PUT/DELETE /api/v1/productos/{id}`.

### Variantes (talla + color)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/productos/{id}/variantes` | Variantes del producto (visibles y ocultas) |
| `POST` | `/api/v1/productos/{id}/variantes` | Crear combinación (`409 variante_duplicada` si ya existe) |
| `PUT` | `/api/v1/variantes/{id}` | Actualizar (es aquí donde se escribe el `stock` real) |
| `DELETE` | `/api/v1/variantes/{id}` | Ocultar (`409 variante_con_stock` si queda stock) |

`productos.stock` es la **suma** de las variantes visibles y se recalcula en
la misma transacción. El stock real vive en `producto_variantes`.

Cada combinación se vende al **mismo precio**: `productos.precio_venta`, sin
importe propio por talla o color (una variante solo aporta talla, color y
stock). Las líneas de una orden o de una cotización congelan ese precio al
crearse.

Los lados de la combinación se envían por id (`tallaId`/`colorId`) o por
nombre (`talla`/`color`, texto libre): con nombre, el backend da de alta el
registro en el catálogo si no existía (o lo reactiva si estaba oculto),
siempre en la misma transacción.

### Categorías

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/categorias` | Listar / crear categorías |
| `GET/PUT/DELETE` | `/api/v1/categorias/{id}` | Operar una categoría |

### Tallas y colores

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/tallas` | Listar / crear tallas (`nombre` único) |
| `GET/PUT/DELETE` | `/api/v1/tallas/{id}` | Operar una talla (`orden` de exhibición) |
| `GET/POST` | `/api/v1/colores` | Listar / crear colores (`nombre` único) |
| `GET/PUT/DELETE` | `/api/v1/colores/{id}` | Operar un color (`codigoHex` `#RRGGBB`) |

### Personas (Clientes, Proveedores, Empleados)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/clientes` | Listar / crear clientes |
| `GET/PUT/DELETE` | `/api/v1/clientes/{id}` | Operar un cliente |
| `GET/POST` | `/api/v1/proveedores` | Listar / crear proveedores |
| `GET/PUT/DELETE` | `/api/v1/proveedores/{id}` | Operar un proveedor |
| `GET/POST` | `/api/v1/empleados` | Listar / crear empleados |
| `GET/PUT/DELETE` | `/api/v1/empleados/{id}` | Operar un empleado |

### Usuarios

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/usuarios` | Listar / crear usuarios |
| `GET/PUT/DELETE` | `/api/v1/usuarios/{id}` | Operar un usuario |

**Nota:** `POST /api/v1/usuarios` es pública solo cuando la BD no tiene ningún usuario (bootstrap del primer administrador). El cuerpo de `PUT /usuarios/{id}` con `contrasena` exige además `claveAdmin` (la clave de la cuenta en sesión).

### Roles y permisos (RBAC)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/roles` | Listar / crear roles |
| `GET/PUT/DELETE` | `/api/v1/roles/{id}` | Operar un rol; el `PUT` acepta `permisos: ["modulo.accion", …]` |

No existe `/api/v1/roles/{id}/permisos`: los permisos se reemplazan enteros
en el propio `PUT /roles/{id}`. El rol `ADMIN` es de sistema (no se edita ni
se borra).

### Órdenes de venta

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/ordenes` | Listar / crear órdenes (`items: [{productoId, varianteId?, cantidad}]`) |
| `GET/DELETE` | `/api/v1/ordenes/{id}` | Obtener / eliminar orden |
| `PUT` | `/api/v1/ordenes/{id}/estado` | Cambiar estado de la orden |
| `GET/POST` | `/api/v1/ordenes/{id}/detalles` | Listar / agregar (o reemplazar) una línea |
| `DELETE` | `/api/v1/ordenes/{id}/detalles/{varianteId}` | Quitar la línea de esa variante |

La clave de una línea es `(variante, orden)`: el mismo producto puede estar
dos veces con tallas distintas, y sin `varianteId` solo se acepta si el
producto tiene una única variante (`400 variante_requerida`).

### Facturas

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/facturas` | Listar / crear facturas (`POST` solo pide `ordenId`) |
| `GET/DELETE` | `/api/v1/facturas/{id}` | Obtener / eliminar factura |
| `PUT` | `/api/v1/facturas/{id}/estado` | Cambiar estado de la factura |

### Cotizaciones

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/cotizaciones` | Listar / crear cotizaciones (no toca stock) |
| `GET/DELETE` | `/api/v1/cotizaciones/{id}` | Obtener con sus líneas / eliminar |
| `PUT` | `/api/v1/cotizaciones/{id}/estado` | `VIGENTE`, `ACEPTADA`, `RECHAZADA` o `ELIMINADO` |

### Auditoría

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/auditoria` | Eventos con `?usuario=&desde=&hasta=&entidad=&accion=&q=&limit=&offset=` |
| `DELETE` | `/api/v1/auditoria/antes-de/{fecha}` | Purga lo anterior a una fecha |
| `DELETE` | `/api/v1/auditoria/todo` | Vacía la tabla |

No hay `GET /api/v1/auditoria/{id}`: para un evento concreto se filtra
(`?accion=LOGIN`, `?entidad=roles`…).

### Reportes

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/reportes/productos-vendidos` | Productos más/menos vendidos (`?limite=6&orden=desc`, permiso `dashboard.ver`) |
| `GET` | `/api/v1/reportes/ventas` | Serie de ventas por periodo: `?desde=yyyy-MM-dd&hasta=yyyy-MM-dd&agrupacion=dia\|mes\|anio` |
| `GET` | `/api/v1/reportes/ventas-productos` | Ranking por producto y reparto por categoría del mismo rango |

Los dos últimos son los de la pantalla **Reportes** y exigen `reportes.ver`
(permiso nuevo en la migración `021`, solo ADMIN). Respuestas:

- `GET /reportes/ventas` → `{desde, hasta, agrupacion, resumen: {total,
  ordenes, unidades, ticketMedio}, serie: [{etiqueta, ordenes, total,
  unidades}]}`. Las etiquetas son `yyyy-MM-dd` (día), `yyyy-MM` (mes) o
  `yyyy` (año), **en hora de Bolivia (UTC−4)**; la serie trae **solo los
  periodos con datos**, el frontend rellena los huecos con ceros.
- `GET /reportes/ventas-productos` → `{productos: [{productoId, nombre,
  categoria, unidades, monto}], categorias: [{nombre, unidades, monto}]}`,
  ordenados por monto descendente y acotados a 500.

Ambos comparten criterio con el resto de la app: solo órdenes `PAGADO`, sin
líneas `ELIMINADO`, **total bruto** (`SUM(o.total)` antes de rebajas e IVA) y
`hasta` inclusivo (pasa a `hasta + 1 día` por detrás). El rango se valida en
el caso de uso: fechas `yyyy-MM-dd`, `desde <= hasta`, `agrupacion` válida y
máximo 400 periodos (`Reportes.limiteGrupos`). La suma de la serie, la de
productos y la de categorías coinciden entre sí.

### Ajustes globales

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/ajustes` | Listar ajustes |
| `PUT` | `/api/v1/ajustes` | Actualizar ajustes (`{"valores": {...}}`) |
| `GET` | `/api/v1/ajustes/suscripcion` | Estado de la licencia: `libre`, `activa` o `bloqueada` |
| `PUT` | `/api/v1/ajustes/suscripcion` | Activarla con la clave maestra (`{"clave", "duracion"}`) |

**Nota:** escribir ajustes exige el permiso `ajustes.editar` (`403
permiso_denegado` para el resto; por defecto solo lo tiene ADMIN). El
`PUT /ajustes/suscripcion` es **público** (sin sesión): es por donde se
reactiva la app cuando la licencia está bloqueada.

### Respaldos de la BD

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/v1/respaldos` | Crear un `.dump` con `pg_dump -Fc` (permiso `ajustes.editar`) |
| `GET` | `/api/v1/respaldos` | Listar los respaldos de `BACKUPS_DIR` (permiso `ajustes.ver`) |
| `GET` | `/api/v1/respaldos/{nombre}/descarga` | Descargar el `.dump` (permiso `ajustes.editar`) |

**Cómo funciona:**

- Los ficheros quedan en `backend/backups/` con nombre `respaldo_aaaa-MM-dd_HHmmss.dump` y se conservan los **30 más recientes**. Se restauran con `pg_restore -d ventas <fichero>`.
- El **respaldo automático** lee el ajuste `respaldoIntervalo` (minutos: `0` manual, `1440` día, `10080` semana, `43200` mes) y se reprograma al arrancar, tras cada respaldo y al guardar ajustes. **Solo se ejecuta mientras el servidor está corriendo.**
- La contraseña de la BD viaja en el entorno del proceso `pg_dump` (`PGPASSWORD`), nunca en la línea de comandos.
- Si `pg_dump` no está en el PATH, define `PG_DUMP_BIN`; el error llega como `503` con `code = respaldo_fallido`.
- Las creaciones quedan en la auditoría (todo `POST` se audita).

### Archivos

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/api/v1/archivos/imagenes` | Subir imagen (base64) |
| `GET` | `/api/v1/archivos/imagenes/{nombre}` | Obtener imagen |

### Asistente IA (Ollama local)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/chat/estado` | Ollama activo, modelo instalado, `permitido` y progreso de descarga |
| `POST` | `/api/v1/chat` | Pregunta en lenguaje natural: `{"mensajes": [{role, content}]}` |
| `POST` | `/api/v1/chat/modelo/descargar` | Lanza la descarga del modelo (202) |
| `GET` | `/api/v1/chat/modelo/descarga` | Progreso (lo sondea la UI) |

Cualquier rol autenticado puede chatear salvo que el ajuste `iaRoles` lo
excluya (`403 ia_no_permitido`); si Ollama no corre, `503
ollama_no_disponible`.

## Convenciones

- **Listados**: `{"total": n, "items": [...]}` con paginación `?limit=&offset=`
- **Filtros**: `?estado=DISPONIBLE` filtra por estado
- **PUT parcial**: solo escribe los campos enviados; `null` borra el valor
- **Errores**: `{"error": {"code", "message"}}` con códigos `400` (validación), `404` (no existe), `409` (conflicto), `503` (BD caída)
- **Borrado lógico**: `DELETE` marca `estado = ELIMINADO`, nunca borra filas. Para ver eliminados: `?estado=ELIMINADO`

## Base de datos

### Migraciones (automáticas)

Al arrancar el servidor, `lib/src/data/database/migrator.dart` aplica:

1. `001_esquema_farmacia` — Enums, tablas, triggers de auditoría
2. `002_borrado_logico` — Valor `ELIMINADO` en estados + columna `estado` a detalles
3. `003_sesiones` — Tabla de sesiones para autenticación
4. `004_indices_rendimiento` — Índices de claves foráneas, estados, fechas
5. `005_ajustes` — Tabla `ajustes` (clave/valor)
6. `006_pagos` — Desglose de pagos de cada orden
7. `007_productos_version` — `version` de producto para el guardado optimista
8. `008_cotizaciones` — Cotizaciones y sus detalles
9. `009_roles_permisos` — RBAC: `roles`, `permisos` y `rol_permisos`
10. `010_auditoria` — Tabla `auditoria` y permisos del módulo
11. `011_apellido_personas` — Columna `apellido` en `clientes` y `empleados`
12. `012_ci_clientes` — Renombra `dni` → `ci` en `clientes` (si aún existe) y su clave única
13. `013_empleados_sin_cargo` — Elimina la columna `cargo` de `empleados` (la función la define el rol vinculado)
14. `014_facturas_rebaja_iva` — `rebaja`/`factura` en la orden y renombra `boletas` → `facturas` (con `iva`)
15. `015_productos_precio_rebaja` — Columna `precio_rebaja` en `productos` (máximo a rebajar por unidad)
16. `016_ventas_fraccionadas` — `unidad`, `codigo`, `stock_minimo`, `stock`/`cantidad` fraccionados, `costo_unitario` y la tabla `movimientos_stock` (kardex)
17. `017_ropa` — Esquema de ropa: quita `fecha_vencimiento`, `presentacion_id` y `POR_VENCER`, restringe `unidad` a `UN`, borra `presentaciones` y crea `tallas`, `colores` y `producto_variantes`; el detalle de órdenes y cotizaciones pasa a clave `(variante_id, …)`
18. `018_catalogo_tallas_colores_propio` — Los catálogos de tallas y colores nacen vacíos: borra las semillas de ejemplo que ningún producto usa (cada tienda los llena desde la app)
19. `019_precio_por_variante` — Columna `precio` en `producto_variantes` (precio propio de cada combinación)
20. `020_quitar_precio_por_variante` — Retira esa columna: un único precio por producto (`productos.precio_venta`), igual que en una base nueva en la que la 019 se crea y a continuación se borra
21. `021_permisos_reportes` — Módulo `reportes`: sus 4 permisos solo para ADMIN y `paginaInicial` de `11` a `12` (Ajustes pasa a ser la última entrada del menú)
22. `022_proveedores_email_nit` — Columnas opcionales `email` y `nit` en `proveedores`
23. `023_descripcion_producto` — Columna opcional `descripcion` en `productos` (texto libre de la ficha; el tope de 2000 caracteres lo pone la API)
24. `024_marcas` — Tabla `marcas` (nombre + estado, borrado lógico) y columna opcional `productos.marca_id`: la marca de la prenda es anulable

Las 001–015 están en `migrations.dart`; la 016 en adelante (las compartidas)
se definen en `migraciones_compartidas.dart`, la fuente única que el
`Migrator` renderiza a PostgreSQL y a SQLite.

### Reset completo (destructivo)

```sh
psql -U postgres -d ventas -f sql/reset_ventas.sql
```

### Tablas (22 + `schema_migrations` de control = 23)

| Tabla | Descripción |
|-------|-------------|
| `categorias` | Categorías de productos |
| `tallas` | Catálogo de tallas (`nombre` único, `orden` de exhibición) |
| `colores` | Catálogo de colores (`nombre` único, `codigo_hex`) |
| `producto_variantes` | Prenda + talla + color: **aquí vive el stock real de cada combinación** |
| `clientes` | Clientes de la tienda |
| `proveedores` | Proveedores |
| `empleados` | Empleados (vendedores, administradores, etc.) |
| `usuarios` | Usuarios del sistema (credenciales de acceso) |
| `productos` | Prendas; `stock` = suma de sus variantes visibles |
| `ordenes_pedidos` | Órdenes de venta |
| `facturas` | Comprobantes de venta (con rebaja e IVA) |
| `detalles_ordenes_pedidos` | Líneas de cada orden, clave `(variante_id, orden_id)` |
| `cotizaciones` | Propuestas de precio (no tocan stock) |
| `detalles_cotizaciones` | Líneas de cada cotización |
| `pagos` | Desglose de pagos de cada orden (efectivo + Yape…) |
| `roles`, `permisos`, `rol_permisos` | RBAC |
| `sesiones` | Tokens Bearer |
| `ajustes` | Configuración global del sistema (clave/valor) |
| `auditoria` | Quién hizo qué, cuándo y con qué resultado |
| `movimientos_stock` | Kardex de entradas y salidas por variante |

## Reglas de negocio

### Autenticación

- Token de 64 hex, almacenado en tabla `sesiones`
- Caduca a los **30 días** con "Recordarme" y a las **24 h** sin él
- `contrasena` es de solo escritura: nunca se devuelve en respuestas
- CORS permite la cabecera `authorization` (necesario en web)

### Ventas

- Cada línea vende una **variante** (prenda + talla + color): `items:
  [{productoId, varianteId?, cantidad}]`. Si el producto tiene una sola
  variante se resuelve sola; con varias y sin `varianteId` → `400
  variante_requerida`; repetir la misma variante → `400 item_duplicado`
- La orden se crea en estado `PENDIENTE` (valida stock sin descontarlo) y lleva
  su **desglose de pagos**: `POST /ordenes` envía `pagos: [{metodoPago, monto,
  referencia?}]`, una orden puede repartirse en varios métodos (efectivo + Yape…)
  y la suma de montos debe cuadrar con el **total a pagar**
  (`total − rebaja + IVA` si es factura) → `400 pago_no_cuadra`
- Al cobrar se aplica la **rebaja** (`rebaja`, no puede superar el total →
  `400 rebaja_excesiva`) y, si la venta es factura (`factura: true`), el
  **IVA boliviano del 14.94 %** sobre `(total − rebaja)`
- Al pasar a `PAGADO` se descuenta el stock (si no hay suficiente → `409`)
- Al salir de `PAGADO` se repone el stock
- Una orden `PAGADO` no se puede borrar
- Solo una factura por orden, emitida desde una orden `PAGADO`; la factura
  **copia** los importes ya cobrados (`subtotal`, `rebaja`, `iva`) y no pide
  nada al emitir
- Una factura solo se elimina si está `ANULADA`

### Validaciones

| Campo | Regla |
|-------|-------|
| Nombre | 2-150 caracteres, obligatorio |
| Apellido | 2-100 caracteres, obligatorio en clientes y empleados |
| Importe | Finito, ≥ 0, ≤ 99,999,999.99, 2 decimales |
| Precio venta | > 0, nunca menor que precio compra |
| Unidad | Solo `UN` (`unidad_invalida` en caso contrario) |
| Stock | ≥ 0 y ≤ 999,999.999 (3 decimales); se escribe por variante y el producto guarda la suma |
| Talla / color | Talla de 1-30 caracteres; `codigoHex` con formato `#RRGGBB`; los nombres son únicos en la BD (`409`) |
| Variante | Pareja `(producto, talla, color)` única (`409 variante_duplicada`); borrar con stock → `409 variante_con_stock` |
| CI | 7-15 dígitos (carnet de identidad) |
| Teléfono | 6-15 dígitos (admite +, espacios, guiones, paréntesis) |
| Edad | Entre 18 y 120 |
| Rebaja | ≥ 0 y ≤ total de la orden y ≤ el máximo de sus productos |
| IVA | 14.94 % (Bolivia) sobre `total − rebaja`, solo con factura |
| Precio rebaja (producto) | ≥ 0 y ≤ precio de venta (`null` = sin límite) |

## Testing

### Análisis estático

```sh
dart analyze
```

### Smoke test (E2E)

Con el servidor levantado:

```sh
cd backend
$env:SMOKE_USUARIO='tu.usuario'; $env:SMOKE_CONTRASENA='tu.contrasena'
.\scripts\smoke_test.ps1
```

El script recorre **todos los endpoints** con **214 comprobaciones y 0
fallos**: creaciones, validaciones `400`, `404`/`409` de negocio,
variantes (alta, duplicada, con stock, `variante_requerida`), concurrencia,
auditoría y limpieza final. Con una cuenta que no sea ADMIN, las 13
comprobaciones de Ajustes y Respaldos se sustituyen por 2 de `403` (203 en
total). Solo crea y borra filas marcadas con `[smoke]` (y deja el `.dump` de
su prueba de respaldo, que la poda de 30 se encarga de reciclar).

Resultado de la última corrida completa (servidor en `http://localhost:8090`,
cuenta `carlos_admin`): **214 OK / 0 FAIL**.

## Añadir un módulo nuevo

1. **`domain/entities/`** — entidad del objeto
2. **`domain/repositories/`** — contrato (interfaz abstracta)
3. **`domain/usecases/`** — casos de uso
4. **`data/models/`** — serialización DB ↔ entidad
5. **`data/repositories/`** — implementación con SQL
6. **`presentation/routes/`** — rutas HTTP
7. **`doc/openapi.json`** — documentar los nuevos endpoints
8. **`data/database/migrations.dart`** — nueva migración si se crea tabla

El módulo `products` está completo y sirve de plantilla.
