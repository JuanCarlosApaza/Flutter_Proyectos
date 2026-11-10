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
| `GET` | `/api/v1/products` | Listar productos (con `?limit=&offset=&estado=`) |
| `GET` | `/api/v1/products/{id}` | Obtener un producto |
| `POST` | `/api/v1/products` | Crear producto |
| `PUT` | `/api/v1/products/{id}` | Actualizar producto (parcial) |
| `DELETE` | `/api/v1/products/{id}` | Eliminar (borrado lógico) |

Alias en español: `GET /api/v1/productos`.

### Categorías

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/categorias` | Listar / crear categorías |
| `GET/PUT/DELETE` | `/api/v1/categorias/{id}` | Operar una categoría |

### Presentaciones

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/presentaciones` | Listar / crear presentaciones |
| `GET/PUT/DELETE` | `/api/v1/presentaciones/{id}` | Operar una presentación |

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

**Nota:** `POST /api/v1/usuarios` es pública solo cuando la BD no tiene ningún usuario (bootstrap del primer administrador).

### Órdenes de venta

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/ordenes` | Listar / crear órdenes |
| `GET/DELETE` | `/api/v1/ordenes/{id}` | Obtener / eliminar orden |
| `PUT` | `/api/v1/ordenes/{id}/estado` | Cambiar estado de la orden |
| `GET/POST` | `/api/v1/ordenes/{id}/detalles` | Listar / agregar productos a la orden |
| `DELETE` | `/api/v1/ordenes/{id}/detalles/{productoId}` | Quitar producto de la orden |

### Facturas

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET/POST` | `/api/v1/facturas` | Listar / crear facturas |
| `GET/DELETE` | `/api/v1/facturas/{id}` | Obtener / eliminar factura |
| `PUT` | `/api/v1/facturas/{id}/estado` | Cambiar estado de la factura |

### Reportes

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/reportes/ventas` | Informe de ventas: `?desde=&hasta=&agrupacion=dia\|mes\|anio` → `{resumen, serie}` |
| `GET` | `/api/v1/reportes/ventas-productos` | Ranking de productos + reparto por categorías: `?desde=&hasta=` → `{productos, categorias}` |
| `GET` | `/api/v1/reportes/productos-vendidos` | Productos más/menos vendidos (`?limite=6&orden=desc`) |

**Notas (los tres):**

- Permiso propio **`reportes.ver`**. La migración `019_permiso_reportes` siembra los 4 permisos del módulo y concede `reportes.ver` a los roles que ya tenían `dashboard.ver`, así que el dashboard no pierde su ranking (que antes exigía `dashboard.ver`); `020_permisos_reportes_admin` da además las acciones de escritura a `ADMIN`, que así los tiene los 56 (los mismos que siembra `sql/reset_ventas.sql`).
- La agregación ocurre **siempre en el servidor** (`GROUP BY`); el cliente recibe periodos/productos/categorías ya sumados, nunca detalles.
- Solo se agregan órdenes **PAGADAS** y no anuladas; las líneas anuladas (`detalles_ordenes_pedidos.estado = 'ELIMINADO'`) tampoco cuentan.
- `desde` y `hasta` son fechas `yyyy-MM-dd` **ambas incluidas** (`400 fecha_invalida` si el formato no vale y `400 rango_invalido` si el rango está invertido).
- La etiqueta de cada periodo se genera en la **hora local del negocio**: `to_char(fecha_orden, …)` en PostgreSQL y `date(…, 'localtime')` en SQLite (filtro y etiqueta usan la misma convención, así que una orden de las 23:30 cae en un solo día).
- El servidor devuelve **solo los periodos con ventas** (los huecos los rellena el cliente con ceros) y el `resumen` se deriva de sumar la serie, de modo que los KPI siempre cuadran con la fila de total de la tabla. El ticket medio y los porcentajes por categoría los calcula el cliente.
- La **utilidad** (`resumen.utilidad` y `serie[].utilidad`) suma `monto_total − costo_unitario × cantidad` **solo de las líneas con `costo_unitario` conocido**: las líneas antiguas sin costo no aportan ni restan, para no inflar la cifra.
- El ranking de productos del rango está limitado a 500 filas (red de seguridad) y `limite` de `productos-vendidos` sigue en 1..50.

### Ajustes globales

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/api/v1/ajustes` | Listar ajustes |
| `PUT` | `/api/v1/ajustes` | Actualizar ajustes (`{"valores": {...}}`) |

**Nota:** Solo usuarios `ADMIN` pueden escribir ajustes (`403 nivel_insuficiente` para el resto).

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

Las siguientes (16–23) viven en `migraciones_compartidas.dart` y corren en **ambos motores** (PostgreSQL y SQLite):

16. `016_ventas_fraccionadas` — `codigo`/`unidad`/`stock_minimo` en `productos`, `unidad` en la línea de orden y kardex
17. `017_unidades_medida` — Catálogo `unidades_medida` y sus permisos (`unidades.*`)
18. `018_producto_descripcion` — Columna opcional `productos.descripcion`
19. `019_permiso_reportes` — Módulo `reportes` (4 permisos) y `reportes.ver` concedido a los roles con `dashboard.ver`
20. `020_permisos_reportes_admin` — `reportes.crear/editar/eliminar` para `ADMIN` (los 56 permisos, como en `reset_ventas.sql`)
21. `021_unicidad_filas_vivas` — `roles.nombre`, `productos.codigo` y `unidades_medida.codigo` pasan a índice único **parcial** (`WHERE estado <> 'ELIMINADO'`): entre filas vivas siguen siendo únicas y las ocultas liberan la clave. En SQLite solo cambian `productos.codigo` y `unidades_medida.codigo` (`roles.nombre` es `UNIQUE` incrustado y su tabla tiene hijos referenciados dentro de la transacción)
22. `022_colores_variantes` — Catálogo `colores` (nombre único entre vivos sobre `LOWER(nombre)`), `producto_variantes` (stock por color; `color_id` NULL = variante «Único», con backfill para los productos existentes) y `variante_id` en las líneas de orden/cotización **sumado a su clave primaria** (misma orden, dos colores = dos líneas). En SQLite las dos tablas de detalle se reconstruyen; `movimientos_stock.variante_id` queda opcional y sin FK
23. `023_marcas_garantia` — Catálogo `marcas` (texto puro, vacío, nombre único entre vivos sobre `LOWER(nombre)`), `productos.marca_id` (nullable; columna/filtro/búsqueda de la tabla de productos y línea del Recibo 1 de la orden) y `productos.garantia_meses` (nullable; 1..120 validados en `ensureGarantiaMeses`, visible solo en la ficha del producto)

### Reset completo (destructivo)

```sh
psql -U postgres -d ventas -f sql/reset_ventas.sql
```

### Tablas

| Tabla | Descripción |
|-------|-------------|
| `categorias` | Categorías de productos |
| `presentaciones` | Formas de presentación (tabletas, jarabe, etc.) |
| `clientes` | Clientes de la tienda |
| `proveedores` | Proveedores |
| `empleados` | Empleados (vendedores, administradores, etc.) |
| `usuarios` | Usuarios del sistema (credenciales de acceso) |
| `productos` | Productos de la tienda |
| `ordenes_pedidos` | Órdenes de venta |
| `facturas` | Comprobantes de venta (con rebaja e IVA) |
| `detalles_ordenes_pedidos` | Líneas de producto de cada orden |
| `pagos` | Desglose de pagos de cada orden (efectivo + Yape…) |
| `ajustes` | Configuración global del sistema (clave/valor) |

## Reglas de negocio

### Autenticación

- Token de 64 hex, almacenado en tabla `sesiones`
- Caduca a los **30 días** con "Recordarme" y a las **24 h** sin él
- `contrasena` es de solo escritura: nunca se devuelve en respuestas
- CORS permite la cabecera `authorization` (necesario en web)

### Ventas

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
| Stock | Entero entre 0 y 1,000,000 |
| Fecha vencimiento | No anterior a hoy |
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

El script recorre **todos los endpoints** con 157 comprobaciones (155 con cuenta `ADMIN` y 147 con cualquier otra: Ajustes y Respaldos añaden 10 solo para `ADMIN` y 2 de `403` para el resto). Solo crea filas marcadas con `[smoke]` y las borra **en lógico** (quedan `ELIMINADO`, invisibles en la app; las claves únicas llevan el sello de la corrida para no chocar entre corridas) y deja el `.dump` de su prueba de respaldo, que la poda de 30 se encarga de reciclar).

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
