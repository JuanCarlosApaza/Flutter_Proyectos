# Importación masiva desde Excel (.xlsx) — Productos

Patrón replicado del proyecto de referencia. La **sección 1** está rellena con el
**formulario de ALTA de Productos** de este sistema
(`frontend/lib/presentation/pages/productos_page.dart`), para que las reglas de la
importación y las del formulario no diverjan nunca. Las secciones 2-6 son agnósticas.

> **Estado: IMPLEMENTADO.** Cómo encaja cada pieza:

| Pieza | Fichero |
|---|---|
| Lector del .xlsx (hoja `datos`, encabezados por nombre/alias, filas vacías fuera) | `frontend/lib/presentation/importar/lector_excel.dart` |
| Validador de filas (lee los límites de las propias `CampoFormulario`) | `frontend/lib/presentation/importar/validador_producto.dart` |
| Plantilla descargable (hojas `datos` y `Ayuda`) | `frontend/lib/presentation/importar/plantilla_excel.dart` |
| Diálogo de 3 pasos | `frontend/lib/presentation/widgets/importar_excel.dart` |
| Botón en la cabecera (permiso `productos.crear`) | `frontend/lib/presentation/pages/productos_page.dart` + `accionesCabecera` de `RecursoPage`/`PageHeader` |
| `POST /api/v1/products/importar` (y alias `/productos/importar`) | `backend/lib/src/presentation/routes/producto_routes.dart` |
| Duplicados (idempotencia) | `ProductRepository.existe` (contrato, SQL, fake y `Productos.existe`) |
| Tests | `frontend/test/importar_productos_test.dart` · `frontend/test/importar_dialogo_test.dart` · `backend/test/producto_importar_test.dart` |
| Documentación de la API | `backend/doc/openapi.json` (`/api/v1/products/importar`) |

**Dependencias:** el paquete `excel` de pub.dev **no se puede usar** aquí
(choque de versión de `xml` con `pdf`), así que la lectura y escritura del
`.xlsx` se hacen con `archive` + `xml`, que ya estaban en el proyecto.

---

## 1. Columnas del archivo

### 1.0 Fuente única de reglas

- Los límites salen de las propias declaraciones `CampoFormulario` de `ProductosPage`
  (`min`/`max`/`minCaracteres`/`maxCaracteres`/`decimales`/`minFecha`): el lector del
  Excel recorre **esas mismas** declaraciones, no una copia.
- Las reglas entre campos se validan con `frontend/lib/core/validation/reglas.dart`
  (espejo de `backend/lib/src/domain/rules/validaciones.dart`):
  `ventaNoMenorQueCoste`, `rebajaNoMayorQueVenta` y `redondearCantidad`.
- Las listas salen de `opciones_formulario.dart` (`estadosProducto`, `unidadesVenta`)
  y de los presets `_garantias` de `ProductosPage`.
- Las relaciones (categoría, presentación, marca, proveedor) se resuelven **por nombre
  contra el catálogo**, igual que hace el desplegable del formulario, y se crean si no
  existen (mismo comportamiento que el botón «+» del formulario).

### 1.1 Obligatorias (sin ellas la fila no se importa)

| Encabezado exacto | Alias normalizados | Tipo | Límites | Regla especial |
|---|---|---|---|---|
| `Nombre` | nombre, nombre producto, nombre_producto, producto | texto | 2–150 car. | — |
| `Precio de compra (Bs)` | precio compra, precio_compra, costo, coste | decimal | 0,01 – 99 999 999,99 | Ver 1.2 (cruce con precio de venta). |
| `Precio de venta (Bs)` | precio venta, precio_venta, precio | decimal | 0,01 – 99 999 999,99 | > 0 y ≥ precio de compra. |
| `Stock` | stock, cantidad, existencias | decimal | 0 – 999 999,999 · **3 decimales** | Si `Colores` viene relleno, esta celda se **ignora** (manda la suma). |
| `Unidad de venta` | unidad, unidad venta | lista (catálogo `unidades_medida` activo) | código de 1–10 car. mayúsculas | El formulario **no crea** unidades: código inexistente o inactivo → error de fila. |
| `Estado` | estado, estado producto | lista `DISPONIBLE`, `AGOTADO`, `POR_VENCER`, `DESCONTINUADO` | — | Mayúsculas/minúsculas y acentos indistintos (`disponible`, `por vencer`…). |
| `Categoría` | categoria, categoria producto | relación (catálogo `categorias`) | 1–100 car. | Por nombre normalizado (minúsculas, sin acentos, espacios recortados). **Si no existe → se crea** (igual que «Nueva categoría»). |
| `Presentación` | presentacion | relación (catálogo `presentaciones`) | 1–100 car. | Se crea si no existe («Nueva presentación»). |
| `Marca` | marca, marca producto | relación (catálogo `marcas`) | 1–100 car. | Se crea si no existe («Nueva marca»). |

> Son los nueve campos con `obligatorio: true` en el formulario (los tres catálogos —
> categoría, presentación y marca — más nombre, precios de compra y venta, stock,
> unidad de venta y estado); la API (`POST /api/v1/products`) también exige nombre,
> precio de venta y los tres catálogos. **Solo `Colores` es opcional**: no todos los
> productos llevan variaciones (va en 1.3).

### 1.2 Condicionalmente obligatorias y reglas entre campos

| Regla | Condición | Si se incumple |
|---|---|---|
| Precio de venta ≥ precio de compra | Ambos vienen rellenos (siempre, porque los dos son obligatorios) | Error de fila «no puede ser menor al precio de compra» (`precio_venta_bajo_costo`). |
| Stock ⇄ Colores | `Stock` obligatorio; `Colores` opcional | Si viene `Colores` relleno, **la celda `Stock` se ignora**: el stock se calcula como la suma de las cantidades de las filas de colores (misma regla que el formulario). Con `Colores` vacío, manda el valor de `Stock`. |
| Ganancia % ⟶ Precio de venta | Viene `Ganancia %` y `Precio de venta (Bs)` vacío (solo posible si la plantilla se edita a mano) | Se calcula `precioVenta = precioCompra × (1 + %/100)` (la calculadora del formulario); con precio escrito, `Ganancia %` se ignora con aviso. |
| Máximo a rebajar ≤ precio de venta | Viene `Máximo a rebajar (Bs)` | Error de fila si supera el precio de venta (`precio_rebaja_excesivo`). |
| Fecha de vencimiento ≥ hoy | Viene la fecha | Error de fila (mismo `minFecha` que el formulario). |

### 1.3 Opcionales (vacío = valor por defecto del formulario)

| Encabezado exacto | Alias normalizados | Tipo | Límites | Vacío = | Regla especial |
|---|---|---|---|---|---|
| `Código` | codigo, codigo de barras, barras | texto | ≤ 60 car. | sin código | Único cuando no está vacío → clave de duplicado (ver 1.5). |
| `Descripción` | descripcion, desc, detalle | texto | ≤ 255 car. | sin descripción | — |
| `Ganancia %` | ganancia, porcentaje, margen | decimal | 0 – 999 | — | Solo calculadora: no viaja al backend. |
| `Máximo a rebajar (Bs)` | rebaja, precio rebaja, precio_rebaja, tope rebaja | decimal | 0 – 99 999 999,99 | sin límite | ≤ precio de venta (1.2). |
| `Stock mínimo` | stock minimo, stock_minimo, minimo | decimal | 0 – 999 999,999 · 3 decimales | umbral global de «Ajustes» | — |
| `Colores` | variantes, colores stock, variante | multi-valor | ver 1.4 | unidad simple (variante «Único») | Suma de cantidades = stock. |
| `Proveedor` | proveedor | relación (catálogo `proveedores`) | 1–100 car. | sin proveedor | Se crea si no existe («Nuevo proveedor»). |
| `Garantía (meses)` | garantia, garantia meses, garantia mes | lista | 3, 6, 12, 18, 24, 36, 48, 60 | sin garantía | Solo los presets del formulario; otro número → error de fila. |
| `Fecha de vencimiento` | vencimiento, fecha vencimiento, fecha venc | fecha | `dd/mm/aaaa` o `aaaa-mm-dd` | sin fecha | ≥ hoy (1.2). |

### 1.4 Celda multi-valor: `Colores`

- Formato: `Color|cantidad` dentro de cada fila y `;` entre filas:
  `Rojo|2;Azul|0,5;Negro|12`
- Separadores elegidos `|` (campo) y `;` (lista): no aparecen en nombres de color
  reales ni en las cantidades (que son numéricas con `,` o `.` decimal).
- Si un nombre de color contiene `|` o `;` → **error de fila** con mensaje explícito
  (no se documenta a medias ni se parte el valor en dos).
- Cantidad: decimal 0–999 999,999, 3 decimales, coma o punto decimal.
- Un mismo color dos veces en la fila → error (`variante_duplicada`, igual que la API).

### 1.5 Duplicados (idempotencia)

Clave de duplicado, en este orden:

1. `Código` no vacío → normalizado y comparado contra la BD **y** contra los ya vistos
   en el archivo.
2. Sin `Código` → `Nombre` + `Categoría` + `Presentación` normalizados juntos.

Repetido → **se omite con aviso** (no es error): el archivo se puede re-subir completo
sin duplicar nada.

### 1.6 Fuera de la v1

- `Imagen` (binario): no se declara como columna; si aparece en el archivo se ignora
  como cualquier columna sobrante (decisión 3). En una v2, URL.
- Facturas/órdenes con detalle: se importan en una fila con la celda de líneas; cuando
  se amplíe a esa entidad se reutiliza el mismo separador `|` / `;`.

---

## 2. Formato del archivo (universal)

- Hoja primera llamada `datos` (la plantilla añade una hoja `Ayuda` con estas reglas).
- Fila 1 = encabezados reconocidos **POR NOMBRE**: normalizar (minúsculas, sin acentos,
  espacios recortados) antes de comparar; el orden no importa; sobran columnas → se
  ignoran.
- Una fila = un registro (con sus líneas/detalle en la misma fila si el registro los
  tiene).
- Celdas multi-valor: separador de campo `|` y de lista `;`
  (`Color|cantidad;Color2|cantidad2`). Si un valor puede contener el separador, se
  cambia de separador, no se documenta a medias.
- Valores numéricos: aceptar celda numérica o texto y **punto o coma decimal**
  (`59,90` = 59.90).
- Listas/estados: aceptar mayúsculas/minúsculas y acentos indistintos; vacío = valor
  por defecto **solo en los campos opcionales** (los obligatorios de 1.1 dan error).
- Reglas de validación por fila = EXACTAMENTE las del formulario de alta (mismos
  límites, mismas funciones de `reglas.dart`, límites leídos de las propias
  declaraciones `CampoFormulario`).
- Fila completamente vacía → se ignora sin error.
- Límite de **1000 filas** por archivo, rechazado por el endpoint.

## 3. Flujo en la app: botón + diálogo de 3 pasos

- Botón «Importar Excel» en la página de Productos, al lado de «Nuevo», con el **mismo
  permiso** que el alta (`productos.crear`).
- **Paso 1 — Archivo:** «Descargar plantilla (.xlsx)» (encabezados + 2 filas de ejemplo
  + hoja `Ayuda`) y «Elegir archivo» que se **lee en el navegador** (sin endpoint de
  subida de ficheros; el backend solo recibe JSON). Paquete: `excel` en el `pubspec`
  del frontend (lectura del .xlsx y escritura de la plantilla).
- **Paso 2 — Vista previa:** resumen de una línea
  (`✓ 47 válidas · ✖ 3 con error · 12 ya existen (se omiten)`), tabla paginada con fila
  verde/roja y su mensaje (`Fila 12 – <motivo>`), botón «Importar 47 válidas».
- **Paso 3 — Resultado:** «Se crearon 47. 3 omitidas» + detalle; al cerrar, recarga la
  lista.

## 4. Backend

- `POST /api/v1/products/importar` (alias `/api/v1/productos/importar`) con el **mismo
  permiso** que el alta (`productos.crear`).
- Cuerpo = filas JSON ya validadas y con relaciones (categoría, presentación, marca,
  proveedor, unidades) resueltas por el frontend **igual que las resuelve el formulario**
  (IDs); el backend reutiliza SU lógica de creación normal
  (`Productos.crear` + `producto_routes.create`) sin cambios.
- **Mejor esfuerzo por fila**: una fila que falle no detiene las demás.
- Respuesta `{creados: n, omitidos: [{fila, mensaje}], errores: [{fila, mensaje}]}`,
  donde `fila` es el **número real de fila del Excel** (con la fila 1 de encabezados
  incluida) para que el usuario lo encuentre en su archivo.
  (`omitidos` es la ampliación necesaria de la sección 4 para poder cumplir la
  decisión 2: los duplicados no son errores.)
- Duplicados (mismo `Código`/`Nombre+Categoría+Presentación` ya en BD o repetido en el
  archivo) → **se saltan con aviso**: el archivo se puede re-subir completo sin duplicar
  (importación idempotente).
- Límite: > 1000 filas → `400` `importar_demasiadas_filas`.

## 5. Decisiones cerradas

1. Solo se importan las filas **VÁLIDAS**; las fallidas se listan en la vista previa
   para corregirlas en el archivo.
2. Duplicados → se saltan con aviso (idempotencia).
3. Campos pesados (imágenes binarias, adjuntos) → fuera de la v1; más adelante con URL
   si hace falta.

## 6. Tests

- **Lector/validador** (`frontend/test/importar_productos_test.dart`): encabezados en
  otro orden y con alias, números con coma, fila vacía, límites de cada campo
  (nombre 1 car., precio fuera de rango o por debajo del coste, stock con 4 decimales,
  fecha anterior a hoy, garantía fuera de presets, unidad inexistente), reglas
  condicionales (colores vs stock, rebaja > precio), relaciones inexistentes/creadas,
  duplicados por código y por nombre+categoría.
- **Diálogo** (`frontend/test/importar_dialogo_test.dart`): los 3 pasos y los conteos
  del resumen.
- **Backend** (`backend/test/producto_importar_test.dart`): permiso, crea válidas y
  reporta fallidas, omite duplicados, rechaza N > 1000.
