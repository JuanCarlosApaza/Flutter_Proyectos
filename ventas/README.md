# Ventas — Clean Architecture (front y back separados)

Sistema de **ventas, inventario y facturación**: catálogo de productos,
órdenes con desglose de pagos, facturas, cotizaciones, clientes, proveedores,
empleados, RBAC con roles, auditoría, respaldos y asistente IA local.

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
> farmacia, del que conserva todos los módulos. Lo específico de farmacia
> (vencimientos, presentaciones, alertas de «por vencer») está **pendiente de
> retirar** módulo a módulo; los identificadores internos de migración
> (`001_esquema_farmacia`) también se mantienen sin tocar, porque las
> migraciones son inmutables una vez aplicadas.

## Arranque rápido

Requisitos: **Dart SDK ^3.13.3**, **Flutter**, **PostgreSQL 15+**.

```sh
# 1. Base de datos (una sola vez)
psql -U postgres -c "CREATE DATABASE ventas"

# 2. Backend
cd backend
copy .env.example .env        # pon DB_NAME=ventas y tu DB_PASSWORD real
dart pub get
dart run bin/server.dart      # aplica las 21 migraciones solo al arrancar

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
cd backend  && dart analyze && dart test     # 263 tests
cd frontend && flutter analyze && flutter test  # 201 tests
cd backend  && .\scripts\smoke_test.ps1 -Base http://localhost:8080 `
               -Usuario <usuario> -Contrasena '<clave>'
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

#### Endpoints (87 rutas sobre 19 tablas + reportes y asistente)

| Recurso | Rutas |
|---------|-------|
| Sistema | `GET /` · `GET /api/v1/health` · `GET /api/v1/network` (IP para el QR) |
| Auth | `POST /api/v1/auth/login` (pública) · `POST /api/v1/auth/logout` · `GET /api/v1/auth/me` |
| Productos | `GET/POST /api/v1/products` · `GET/PUT/DELETE /api/v1/products/{id}` · `POST /api/v1/products/importar` (Excel) · alias en español `GET /api/v1/productos` |
| Categorías | `GET/POST /api/v1/categorias` · `GET/PUT/DELETE /api/v1/categorias/{id}` |
| Presentaciones | `GET/POST /api/v1/presentaciones` · `GET/PUT/DELETE /api/v1/presentaciones/{id}` |
| Clientes | `GET/POST /api/v1/clientes` · `GET/PUT/DELETE /api/v1/clientes/{id}` |
| Proveedores | `GET/POST /api/v1/proveedores` · `GET/PUT/DELETE /api/v1/proveedores/{id}` |
| Empleados | `GET/POST /api/v1/empleados` · `GET/PUT/DELETE /api/v1/empleados/{id}` |
| Usuarios | `GET/POST /api/v1/usuarios` · `GET/PUT/DELETE /api/v1/usuarios/{id}` |
| Roles (RBAC) | `GET/POST /api/v1/roles` · `GET/PUT/DELETE /api/v1/roles/{id}` · `PUT /api/v1/roles/{id}/permisos` |
| Órdenes | `GET/POST /api/v1/ordenes` · `GET/DELETE /api/v1/ordenes/{id}` · `PUT /api/v1/ordenes/{id}/estado` · `GET/POST /api/v1/ordenes/{id}/detalles` · `DELETE /api/v1/ordenes/{id}/detalles/{productoId}` |
| Facturas | `GET/POST /api/v1/facturas` · `GET/DELETE /api/v1/facturas/{id}` · `PUT /api/v1/facturas/{id}/estado` |
| Cotizaciones | `GET/POST /api/v1/cotizaciones` · `GET/DELETE /api/v1/cotizaciones/{id}` · `PUT /api/v1/cotizaciones/{id}/estado` |
| Ajustes | `GET/PUT /api/v1/ajustes` · `PUT /api/v1/ajustes/suscripcion` |
| Respaldos | `POST /api/v1/respaldos` · `GET /api/v1/respaldos` · `DELETE /api/v1/respaldos/{id}` |
| Auditoría | `GET /api/v1/auditoria` · `GET /api/v1/auditoria/{id}` · `DELETE /api/v1/auditoria/antes-de/{fecha}` |
| Archivos | `POST /api/v1/archivos/imagenes` · `GET /api/v1/archivos/imagenes/{nombre}` |
| Asistente IA | `GET/POST /api/v1/chat` (estado y conversación con Ollama local) |
| Reportes | `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc` · `GET /api/v1/reportes/ventas?desde=&hasta=&agrupacion=` · `GET /api/v1/reportes/ventas-productos?desde=&hasta=` (agregados, no CRUD) |

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
| `stock` fraccionado entre 0 y 999 999.999 (3 decimales) | `ensureNoNegativo` + `doubleOrNull` | `min`/`max` + filtro de 3 decimales |
| `unidad` de venta: forma del símbolo (`1-10` alfanuméricos) **y** que exista y esté activa en `unidades_medida` | `ensureUnidad` + `Unidades.asegurarUnidadVigente` → `400 unidad_invalida` | desplegable `UnidadesController` (catálogo `unidades`), con `unidadesVenta` de respaldo |
| `descripcion` opcional: recortada y hasta 255 caracteres | `ensureDescripcion` → `400 field_too_long` | `maxCaracteres: 255` + `maximasLineas: 4` |
| `fechaVencimiento` no anterior a hoy | `ensureFechaNoVencida` | `minFecha` (bloquea el calendario) |
| CI de 7 a 15 dígitos (carnet de identidad) | `ensureCi` | `ciValido` + tope de longitud |
| Teléfono: 6-15 dígitos (`+`, espacios, `-`, `()`) | `ensureTelefono` | `telefonoValido` |
| Edad entre 18 y 120 | `ensureEdad` | `min: 18` / `max: 120` |
| Usuario de 4-50 (`\w`, `.`, `-`) y contraseña de 8-255 | `_ensureNombreUsuario` / `_ensureContrasena` | `usuarioValido` + longitudes |
| Género `M/F/O` y estados de cada tabla | `ensureGenero` / `ensureEstado` | desplegables (solo opciones válidas) |
| Rebaja ≥ 0 y ≤ total y máx. de productos; IVA 14.94 % solo si es factura | `Ordenes` / `Facturas` | `Mín. 0.001`, límite de stock y tope del total |
| Máximo a rebajar por unidad ≥ 0 y ≤ precio de venta | `ensurePrecioRebaja` | `rebajaNoMayorQueVenta` |

Cobertura: `backend/scripts/smoke_test.ps1` (sección «Unidades de medida»
incluida; imprime al final `Correctos/Fallos`, y las de Ajustes y Respaldos
solo aplican con cuenta `ADMIN`) y
`frontend/test/validaciones_form_test.dart`.

#### Formularios: campos obligatorios y calculadora de porcentaje

Dos mecanismos de `RecursoForm` (`frontend/lib/presentation/widgets/recurso_form.dart`),
en espejo del patrón del proyecto de referencia:

**1. Campos obligatorios / opcionales.** Cada `CampoFormulario` declara tres
banderas independientes:

| Bandera | Efecto |
|---------|--------|
| `obligatorio: true` | requerido **siempre** (alta y edición) |
| `obligatorioSoloCreacion: true` | requerido solo al crear (`requerido = obligatorio \|\| (obligatorioSoloCreacion && !esEdicion)`) |
| `soloEnCreacion: true` | el campo no se muestra al editar (p. ej. la contraseña) |
| *sin banderas* | opcional puro |

- Orden de validación por campo: **1)** requerido y vacío → «Este campo es
  obligatorio» (error fijo y único); **2)** opcional y vacío → válido, se
  salta toda la validación posterior (no se exige formato a lo vacío);
  **3)** formato → **4)** rango `min`/`max` → **5)** `patron` → **6)**
  `validador` propio.
- La etiqueta lleva el `*` como **texto** cuando el campo es obligatorio
  (p. ej. «Precio de compra (Bs) \*»).
- El formulario puede agruparse en dos pestañas con `pestanas:` y el reparto
  de cada campo en `pestana:` (Productos usa «Obligatorio» con icono
  `Icons.star` y «Opcional»). **Regla de oro:** al guardar se validan
  **todos** los campos de **todas** las pestañas, aunque solo una se vea; si
  el error está en una oculta, el formulario salta a ella y pinta el error.

**2. Calculadora de porcentaje (`TipoCampo.porcentaje`).** Campo de pantalla
con dos referencias: `porcentajeSobre` (base, p. ej. `precioCompra`) y
`porcentajeDestino` (p. ej. `precioVenta`):

- Al escribir el % → `destino = base × (1 + %/100)` (costo 80 y 25 % → 100).
- Al escribir el destino a mano → `% = (destino − base) ÷ base × 100`
  (costo 80 y precio 100 → 25).
- Al editar, se precarga el % con el margen real **solo si** destino > base.
- Bandera anti-bucle (`_recalculando`): mientras un listener escribe en otro
  campo, los demás ignoran su evento.
- Solo calcula con base **> 0**; si no, la validación del % dice «Escribe el
  precio de compra: sobre él se calcula este %».
- Rango `min: 0` / `max: 999`, redondeo a 2 decimales, parser con coma o
  punto decimal.
- El % **no viaja al backend**: el payload solo lleva base y destino; el
  destino es obligatorio por su cuenta.
- Se pinta en la **misma fila** que su destino, con el auxiliar
  «Precio de compra + %».

Cobertura: `frontend/test/formularios_pestanas_porcentaje_test.dart`.

#### Importación masiva desde Excel (productos)

- **Botón «Importar Excel»** en la cabecera de Productos, al lado de «Nuevo» y
  con el **mismo permiso** que el alta (`productos.crear`). Diálogo de 3 pasos:
  **archivo** (descargar plantilla + elegir .xlsx) → **vista previa** (resumen
  `✓ 47 válidas · ✖ 3 con error · 12 repetidas` con fila verde/roja y su
  motivo) → **resultado** («Se crearon 47» + detalle).
- **Todo se lee y se genera en el equipo**: el `.xlsx` lo abre el navegador
  (`file_selector`) y solo viaja JSON a `POST /api/v1/products/importar`
  (máx. 1000 filas). La plantilla (hoja `datos` + hoja `Ayuda`) la genera el
  propio cliente.
- **Una sola fuente de reglas:** el validador de filas recorre las mismas
  declaraciones `CampoFormulario` que el formulario (mismos límites, mismos
  mensajes: «Este campo es obligatorio», «Debe ser mayor o igual a 0.01»…) y
  usa las mismas reglas de `reglas.dart` (venta ≥ coste, rebaja ≤ precio).
- **Mejor esfuerzo por fila** en el backend: reutiliza `Productos.crear` sin
  cambios; una fila mala no detiene las demás y responde
  `{creados, omitidos, errores}` con el **número real de fila del Excel**.
  Los duplicados (mismo código, o nombre + categoría + presentación) se
  **saltan con aviso**, así que re-subir el archivo no duplica nada.
- Las relaciones por nombre que no existan (categoría, marca, presentación,
  proveedor) **se crean al importar**, igual que el botón «+» del formulario.
- Detalle completo en [`IMPORTAR_EXCEL.md`](IMPORTAR_EXCEL.md).

#### Unidades de medida y cantidades fraccionadas

El desplegable «Unidad de venta» dejó de ser una lista fija: lo decide la tabla
**`unidades_medida`** (migración **`017_unidades_medida`**), que es el **13º
módulo** de la app (`Modulos.unidades`, índice 11; Ajustes pasa a 12).

**Esquema y reglas (backend):**

| Columna | Regla |
|---------|-------|
| `unidad_id` (PK) | clave sustituta; `codigo` es la clave **natural** que viaja en `productos.unidad` |
| `codigo` | `1-10` alfanuméricos en mayúsculas, **único** e **inmutable**: `400 codigo_inmutable` al cambiarlo (los productos y las líneas emitidas ya lo llevan escrito) |
| `nombre` | `2-50` caracteres |
| `tipo` | `PESO` / `VOLUMEN` / `UNIDAD` → `400 tipo_unidad_invalido` |
| `decimales` | `0..3` → `400 decimales_invalidos`: cuántos decimales admite la **cantidad** en esa unidad |
| `estado` | estado general (`ACTIVO` / `INACTIVO` / `ELIMINADO`) |

- Semilla de **15 unidades** (`KG`, `GR`, `LB`, `ONZA`, `LT`, `ML`, `GALON`,
  `UN`, `DOCENA`, `PAQUETE`, `CAJA`, `BLISTER`, `FRASCO`, `SOBRE`, `ROLLO`);
  los listados ordenan por `tipo, codigo`.
- Rutas: `GET/POST /api/v1/unidades` y `GET/PUT/DELETE /api/v1/unidades/{id}`
  (`409` en código repetido, `404 unidad_no_encontrada`). Actualización
  **parcial**: lo que no venga no se toca; sin campos, `400 fields_required`.
- `DELETE` es **borrado lógico**: la fila queda `ELIMINADO` (los productos que
  ya la usan siguen vendiéndose) y desaparece del catálogo, así que ya no se
  puede elegir de nuevo.
- `Productos` valida contra la BD con
  `Unidades.asegurarUnidadVigente` (`400 unidad_invalida` si el código no
  existe o no está activo) y, si la unidad viene vacía, guarda `UN`.
- Permisos `unidades.ver/crear/editar/eliminar` (migración 017): `ADMIN` los
  cuatro, `CAJERO` solo `unidades.ver`.

**Pantalla (frontend):** `presentation/pages/unidades_page.dart` sigue el
patrón `RecursoPage` (tabla con código, nombre, tipo, decimales y estado, en
chips; filtros ACTIVO/INACTIVO; alta/edición en hoja modal). El campo `codigo`
declara `soloEnCreacion: true`: no se muestra al editar, porque cambiarlo
respondería `400 codigo_inmutable`.

**Catálogo y carrito:** `UnidadesController` (con `porCodigo`, `decimalesDe`)
es la fuente de la que se llena el desplegable «Unidad de venta» de Productos
(`unidadesDe(...)` etiqueta como `Kilogramo (KG)` y ordena por tipo/código);
`unidadesVenta` sigue en `opciones_formulario.dart` **solo como respaldo**, para
cuando el catálogo aún no está cargado. El carrito trabaja con **cantidades en
`double`**:

- La fila `LineaCarrito` lleva `unidad`, `decimales` y `stock` en `double`, y
  su `paso` es `1` si `decimales == 0` y `0.25` si no: los botones ± se mueven
  a ese paso y el tope es el **stock fraccionado exacto** (12.750 KG).
- La línea de la hoja del carrito tiene un **campo de cantidad decimal**
  (filtro de `decimales`, recorte al stock al perder el foco). Escribir `0` no
  retira la línea mientras se teclea (teclear «0.75» pasaría antes por «0»);
  quién la retira es el botón −, `definirCantidad(0)` por código y «Vaciar».
- El total y el badge del carrito se pintan con `cantidadTexto` / `redondearCantidad`
  (`core/validation/reglas.dart`), sin error binario.
- Sin catálogo cargado manda el **respaldo de decimales**: los códigos que se
  fraccionan (`KG`, `GR`, `LB`, `ONZA`, `LT`, `ML`, `GALON`) admiten 3 y el
  resto se cuenta por envase (`0`).

Cobertura: `backend/test/unidad_medida_test.dart` (reglas y productos),
`backend/test/unidad_medida_routes_test.dart` (HTTP, permisos y códigos) y
`frontend/test/unidades_test.dart` (catálogo, pantalla, carrito fraccionado y
desplegable de producto).

#### Descripción del producto

`productos.descripcion` (migración **`018_producto_descripcion`**) añade al
producto un texto libre **opcional** de hasta **255 caracteres** que explica
qué es o para qué sirve («jarabe para la tos», «de venta suelta»…).

| Regla | Backend | Frontend |
|-------|---------|----------|
| Opcional, recortado y hasta 255 caracteres | `ensureDescripcion` → `400 field_too_long` | `maxCaracteres: 255` (filtro de entrada) + `maximasLineas: 4` |
| Vacío o `null` = sin descripción | guarda `NULL` | `CampoFormulario` de la pestaña «Opcional» |
| Edición parcial | lo que no venga no se toca; `descripcion: null` **borra** | el cuerpo lleva siempre la clave |

- Entra en el buscador `?q=` de productos (`columnasBusqueda['productos']`,
  que en PostgreSQL ya volcaba la fila entera con `to_jsonb`) y en
  `doc/openapi.json` (`Product`, `ProductInput` y `ProductPatch`).
- Se pinta en la ficha de detalle (👁) del listado, que recorre los mismos
  `campos` que el formulario.

Cobertura: `backend/test/producto_routes_test.dart` (alta, edición parcial,
borrado y tope de longitud) y `frontend/test/producto_descripcion_test.dart`
(pestaña, límite de 255 y envío en alta/edición).

#### Pantalla «Reportes» (informe de ventas por rango)

Módulo nuevo **`reportes`** (índice 13 del sidebar, última entrada; migración
**`019_permiso_reportes`**, que siembra los 4 permisos del módulo y concede
`reportes.ver` a los roles que ya tenían `dashboard.ver`, así nadie pierde su
ranking, y **`020_permisos_reportes_admin`**, que deja a ADMIN con los 56
permisos, igual que siembra `sql/reset_ventas.sql`). La pantalla pide al
servidor un rango y pinta el informe entero con exportación a CSV y PDF.

| Regla | Backend | Frontend |
|-------|---------|----------|
| La agregación ocurre **siempre en el servidor** (`GROUP BY`) | `reporte_repository_impl.dart` por motor (PG / SQLite) | las entidades solo leen sumas, nunca detalles |
| Solo órdenes `PAGADO` y no anuladas | `o.estado = 'PAGADO'`, `d.estado <> 'ELIMINADO'` | — |
| Etiqueta del periodo en hora local del negocio | PG `to_char(fecha_orden, …)` · SQLite `date(…, 'localtime')` | llega hecha: `2026-10-01`, `2026-10` o `2026` |
| El servidor manda **solo los periodos con ventas** | filtros `>= desde` y `< hasta + 1 día` | `InformeVentas.conHuecos` rellena los huecos con ceros |
| Resumen que cuadra con la tabla | `InformeVentas.resumiendo(serie)` suma la propia serie | ticket medio y `%` por categoría se calculan aquí |
| Rango pedido con `desde`/`hasta` **incluidos** | `400 fecha_invalida` / `400 rango_invalido` / `400 agrupacion_invalida` | dos date pickers `yyyy-MM-dd`, nunca invertidos |

Endpoints (permiso propio **`reportes.ver`**, los tres):

- `GET /api/v1/reportes/ventas?desde=&hasta=&agrupacion=dia|mes|anio` → `{resumen, serie}`;
- `GET /api/v1/reportes/ventas-productos?desde=&hasta=` → `{productos, categorias}`;
- `GET /api/v1/reportes/productos-vendidos?limite=6&orden=desc` → ranking del dashboard.

**Pantalla** (`presentation/pages/reportes_page.dart` + `InformesController`):

- **Los filtros viven en el controlador** y por eso se conservan al volver de
  otro módulo: atajos *Hoy / Ayer / Esta semana (lunes) / Este mes / Este año*
  con el activo resaltado, dos botones «Desde/Hasta fecha» (cambiar **un**
  extremo pide el informe **una sola vez**) y `SegmentedButton` Día|Mes|Año
  (cualquier cambio reconsulta). El pull-to-refresh repite la consulta con los
  mismos filtros y la pantalla, al volver, repinta sin recargar.
- **Contenido:** 5 tarjetas KPI —Total vendido `Bs 1234.50`, Órdenes pagadas,
  Utilidad, Ticket medio y Unidades— en grid de 5 columnas si el ancho ≥1000 y
  de 2 si no; la serie con gráfico de área (`GraficoSerie`, fl_chart) y su
  tabla `Periodo|Órdenes|Unidades|Total|Utilidad` con el pie «Total del
  rango», que cuadra con el KPI por construcción; «Productos más vendidos» con
  el TOP 8 en barras (`Bs X · N uds`) y la tabla numerada con **todos**; y
  «Reparto por categorías» con `pct = monto / total * 100`. La utilidad es
  `monto_total − costo × cantidad` **solo de las líneas con costo conocido**
  (las líneas antiguas sin `costo_unitario` no aportan ni restan).
- **Estados:** carga inicial → `VistaCargando`; error sin datos →
  `VistaError` + «Reintentar»; un fallo **al actualizar con datos previos no
  vacía nada**, publica `avisoRefresco` y la página pinta un banner naranja
  «No se pudo actualizar: …» con su «Reintentar»; y cada tabla vacía escribe
  su propio texto («Sin ventas en este rango»,
  «Sin ventas de productos en este rango», …).
- **Exportación:** `informe_ventas_<desde>_<hasta>.csv` (UTF-8 con BOM, con
  resumen, serie, productos y categorías) y `.pdf` (cabecera con rango y
  agrupación, los 5 KPI, la serie, el ranking y el reparto), ambos por
  `guardarFichero`. Éxito con `alertaExito` y fallo con `alertaError` y el
  motivo — **no SnackBar**, que es regla de la casa —; los botones salen
  deshabilitados si no hay ventas que exportar.
- **Formatos:** dinero `Bs 1234.50` (`core/formatos.dart`), unidades enteras
  sin decimales (`3`) y fraccionadas con hasta tres (`12.75`) y porcentajes
  con un decimal (`75.0%`).

Cobertura: `backend/test/reporte_sqlite_test.dart` (SQL real sobre SQLite:
serie, etiquetas en hora local, ranking y categorías) y
`backend/test/reporte_routes_test.dart` (permisos `reportes.ver` y las tres
validaciones de 400); en el frontend,
`frontend/test/informes_controller_test.dart` (una sola petición por cambio
de filtro, rango nunca invertido, relleno de huecos y banner de refresco),
`frontend/test/reportes_page_test.dart` (KPI, carga, error, vacío y banner),
`frontend/test/informes_export_test.dart` (contenido del CSV y del PDF, con
acentos) y `frontend/test/responsivo_test.dart` (la pantalla a los 4 anchos de
la guía).

#### Migraciones (esquema de la tienda)

- **Aplicación automática al arrancar:** `lib/src/data/database/migrations.dart`
  → 21 migraciones inmutables, registradas en `schema_migrations`:

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
  | 016 | `016_ventas_fraccionadas` | venta por unidad/peso: `unidad`, `codigo`, `stock_minimo`, `stock` y `cantidad` fraccionados, `costo_unitario` y la tabla `movimientos_stock` (kardex) |
  | 017 | `017_unidades_medida` | tabla `unidades_medida` (catálogo de unidades con `decimales`), módulo/permisos `unidades` y levantado del CHECK de `productos.unidad` |
  | 018 | `018_producto_descripcion` | columna `productos.descripcion` (texto libre opcional de 255 caracteres) |
  | 019 | `019_permiso_reportes` | módulo `reportes` (4 permisos) y `reportes.ver` concedido a los roles que ya tenían `dashboard.ver` |
  | 020 | `020_permisos_reportes_admin` | `reportes.crear`, `reportes.editar` y `reportes.eliminar` para `ADMIN` (los 56, igual que `sql/reset_ventas.sql`) |
  | 021 | `021_unicidad_filas_vivas` | índice único **parcial** en `roles.nombre`, `productos.codigo` y `unidades_medida.codigo` (`WHERE estado <> 'ELIMINADO'`): entre filas vivas siguen siendo únicas y las ocultas liberan la clave |

  Las 001–015 viven en `migrations.dart`; las **016 a la 021 y las que vengan**
  se definen una sola vez en `migraciones_compartidas.dart`
  (fuente única que el `Migrator` renderiza a PostgreSQL y a SQLite). Hay
  variantes paralelas para SQLite en `migrations_sqlite.dart` (las usa la APK
  con servidor embebido).

- **Recreeación completa / destructiva (manual):** `sql/reset_ventas.sql`
  → `psql -U postgres -d ventas -f sql/reset_ventas.sql` (incluye los
  mismos índices y tablas que las migraciones).

- **Respaldos**: la vista «Ajustes» tiene un botón «Respaldar ahora» y un
  respaldo automático (solo manual / cada día / cada semana / cada mes) que
  ejecutan `pg_dump -Fc` y guardan `respaldo_aaaa-MM-dd_HHmmss.dump` en
  `backend/backups/` (se conservan los 30 más recientes; se restauran con
  `pg_restore -d ventas <fichero>`). El automático solo corre mientras el
  servidor está en marcha.

Tablas (21): `categorias`, `presentaciones`, `clientes`, `proveedores`,
`empleados`, `usuarios`, `productos`, `ordenes_pedidos`, `pagos`, `facturas`,
`detalles_ordenes_pedidos`, `cotizaciones`, `detalles_cotizaciones`, `roles`,
`permisos`, `rol_permisos`, `sesiones`, `ajustes`, `auditoria`,
`movimientos_stock`, `unidades_medida`
(+ `schema_migrations` de control).

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

Hay **14 módulos × 4 acciones = 56 permisos** (`Modulos.todos` y `navItems`
van siempre en el mismo orden; `017_unidades_medida` añadió el módulo
`unidades`, `019_permiso_reportes` el de `reportes` y
`020_permisos_reportes_admin` las tres acciones de escritura que faltaban
para que `ADMIN` los tenga todos). Cada módulo nuevo
lleva su migración, su entrada en el menú y sus comprobaciones en
`smoke_test.ps1`.

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
  Dashboard), `porPagina` (`10`), `stockMinimo` (`5`) y `diasVencimiento`
  (`90`). Si la fila no existe, manda el defecto: el sistema se comporta igual
  que antes de existir la pantalla.
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
cd backend  && dart analyze && dart test     # 333 tests en 29 ficheros
cd frontend && flutter analyze && flutter test  # 259 tests en 30 ficheros
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

Solo crea filas marcadas con `[smoke]` y las borra **en lógico** (quedan como
`ELIMINADO`, invisibles en la app), así que los datos reales de la base no se
tocan. Sus claves únicas —nombre del rol de prueba, código de producto y
código de unidad— llevan el sello de la corrida, porque la fila anterior
seguiría ocupándolas.

**Fallo conocido (heredado, no regresivo):** el script prueba
`/api/v1/boletas`, una ruta que ya no existe — la migración `010_auditoria`
renombró `boletas` → `facturas` y el script no se actualizó. Son 7
comprobaciones `404`, más 3 de auditoría dependientes del orden de los
eventos y 2 `400` de `PUT` (`cargo` no es editable y cambiar contraseña
exige `claveAdmin`). El resto (≈167) pasa; ocurre igual en el proyecto del
que procede este.
