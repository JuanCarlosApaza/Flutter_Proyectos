# Plan: carga masiva de productos con Excel

> Objetivo: cargar decenas de productos de una sola vez desde un archivo `.xlsx`,
> sin pasar uno por uno por el formulario. Mismas reglas que el formulario
> (precios, tallas, «Única» si no hay variantes, stock obligatorio).

---

## 1. Formato del archivo `.xlsx`

- **Hoja:** la primera, llamada `productos` (la plantilla también trae una hoja
  `Ayuda` con estas reglas).
- **Fila 1 = encabezados.** Se reconocen **por nombre**, sin importar el orden,
  mayúsculas ni acentos; las columnas de más se ignoran (puede dejar sus notas).
- **Una fila = un producto** (con todas sus variantes en la misma fila).

### Columnas, una por una

| # | Columna (encabezado) | Obligatorio | Ejemplo | Regla |
|---|----------------------|-------------|---------|-------|
| 1 | **Nombre** | Sí | `Pantalón mezclillo` | Texto de 2 a 150 caracteres. |
| 2 | **Categoría** | Sí | `Ropa` | Texto; si no existe, se crea automáticamente (igual que «Nueva categoría» del formulario). |
| 3 | **Proveedor** | Sí | `Textil Andina` | Texto; si no existe, se crea automáticamente. |
| 4 | **Precio de compra (Bs)** | Sí | `59.90` | Número > 0, máximo 2 decimales. Acepta celda numérica o texto, con **punto o coma** (`59,90` = `59.90`). |
| 5 | **Precio de venta (Bs)** | Sí | `89.90` | Número > 0 y **≥ precio de compra**. Igual que el formulario: avisa si es menor. |
| 6 | **Variantes (talla\|color\|stock)** | Uno de los dos* | `S\|Negro\|5;M\|Negro\|3` | Combos `talla\|color\|unidades` separados por `;`. *Si queda vacía, el producto es «sin tallas». |
| 7 | **Stock inicial** | Uno de los dos* | `10` | Solo se usa si **Variantes** está vacío (medias, gorros…). Número ≥ 0, máx. 3 decimales. Con variantes se ignora (el stock lo da cada fila). |
| 8 | **Código** | No | `PANT-001` | Texto libre. |
| 9 | **Estado** | No | `DISPONIBLE` | `DISPONIBLE` / `AGOTADO` / `DESCONTINUADO`. Vacío = DISPONIBLE. Acepta «Disponible» (mayúsculas/acentos indistintos). |

\* **Al menos una de las dos**: si las dos vienen vacías → error de fila
(«Falta el stock o las variantes»), igual que en el formulario.

### Ejemplos de fila

```text
Pantalón mezclillo | Ropa    | Textil Andina | 59.90 | 89.90 | S|Negro|5;M|Negro|3        |      | PANT-001 | DISPONIBLE
Medias clásicas    | Medias  | Textil Andina | 15.00 | 25.00 |                            | 24   | MED-001  |
Gorro tejido       | Gorros  | Textil Andina | 20.00 | 35.00 | 39-41|Negro|6;S/M|Rojo|4   |      | GOR-001  |
Zapatilla running  | Zapatos | Deportes Sur  | 150   | 240   | 38|Blanco|4;40/41|Negro|6  |      | ZAP-001  | AGOTADO
```

### La celda «Variantes» paso a paso

- Combo = `talla` **`|`** `color` **`|`** `unidades` → `S|Negro|5`
- Varios combos separados por `;` → `S|Negro|5;M|Negro|3;L|Rojo|2`
- Se permiten **rangos** igual que en el formulario: `39-41`, `40/41`, `S/M`, `40.5-41.5`
- Tallas y colores que no existan en los catálogos **se crean** automáticamente
- Combinación repetida dentro de la misma fila → error
- Se usan `|` y `;` (y no `/` ni `-`) porque esas marcas las traen las tallas
  de calzado (`40/41`) y los rangos (`39-41`).

---

## 2. Validación por fila (espejo formulario FE + backend)

1. **Encabezados:** se normalizan (minúsculas, sin acentos) y se mapean a las
   etiquetas del formulario y a las claves técnicas (`precioCompra`, `variantes`…).
   Falta una columna obligatoria → aviso antes de continuar.
2. **Fila vacía** → se ignora.
3. **Nombre** 2-150 caracteres.
4. **Precio de compra / venta:** número > 0, compra máx 2 decimales,
   venta ≥ compra.
5. **Variantes:** cada combo con talla válida (`tallaValida`, la misma del
   formulario: `S`, `XL`, `38`, `39-41`, `S/M`, `Única`…), color no vacío,
   unidades enteras ≥ 0, sin combinación repetida.
6. **Stock inicial** (solo sin variantes): ≥ 0, máx 3 decimales.
7. **Estado** en la lista permitida (con normalización de acento/mayúsculas).
8. Máximo **1000 productos por archivo** (límite del endpoint).

---

## 3. Flujo en la app (diálogo «Importar Excel»)

Botón **«Importar Excel»** en la página Productos, al lado de «Nuevo Producto»,
visible con el mismo permiso que el alta (`productos.crear`).

**Paso 1 — Archivo**
- Botón *Descargar plantilla (.xlsx)* → genera el archivo con los encabezados,
  2 filas de ejemplo y la hoja `Ayuda`.
- Botón *Elegir archivo* (`.xlsx`) → se lee en el navegador.

**Paso 2 — Vista previa**
- Resumen: `✓ 47 productos` · `112 variantes` · `3 categorías nuevas` · `✖ 3 filas con error`.
- Tabla con las filas (paginada), cada fila en verde o roja con su mensaje:
  `Fila 12 – Precio de venta menor al de compra`.
- Botón **«Importar 47 productos válidos»** (las filas con error se omiten y
  se pueden volver a corregir en el archivo).

**Paso 3 — Resultado**
- «Se crearon 47 productos. 3 filas omitidas» + detalle de las omitidas.
- Se recarga la lista de productos.

---

## 4. Cambios técnicos

### Frontend

| Archivo | Qué |
|---|---|
| `frontend/pubspec.yaml` | + dependencia `excel` (lectura/escritura .xlsx en Dart puro, funciona en web). |
| `frontend/lib/core/excel/plantilla_excel.dart` | Genera y descarga la plantilla (hoja `productos` + hoja `Ayuda`), con `guardar_fichero` ya existente. |
| `frontend/lib/core/excel/leer_excel.dart` | `.xlsx` → filas crudas (`Map<encabezado, texto>`). |
| `frontend/lib/core/excel/importar_productos.dart` | Valida filas → `List<FilaImportada>` con `errores` por fila (reutiliza `tallaValida`, reglas de precios…). |
| `frontend/lib/presentation/widgets/importar_excel_dialog.dart` | Diálogo de 3 pasos (archivo → previa → resultado). |
| `frontend/lib/presentation/pages/productos_page.dart` | Botón «Importar Excel» junto a «Nuevo Producto». |
| Repositorio/controlador de productos | Método `importar(filas)` → `POST /api/v1/productos/importar`. |
| `frontend/test/…` | Tests: cabeceras, números con coma, variantes OK/erróneas, talla inválida, stock obligatorio, plantilla. |

### Backend

| Archivo | Qué |
|---|---|
| `producto_routes.dart` | `POST /api/v1/productos/importar` → `asegurarPermiso(request, 'productos', 'crear')`. |
| `producto_usecases.dart` | `importar(filas)`: recorre llamando a `crear()` (reutiliza variantes/«Única», `ensureNombreTalla`, alta de catálogos) con **mejor esfuerzo por fila** → `{creados: n, errores: [{fila, mensaje}]}`. |
| `backend/test/…` | Tests: permiso, crea válidas, reporta errores, rechaza >1000. |

- El cuerpo de cada fila es **igual al del alta normal** (nombres de catálogo ya
  resueltos por el frontend, igual que hace el formulario), así el backend no
  cambia su lógica de creación.
- Sin endpoint de subida de archivos: el `.xlsx` se parsea en el navegador.

---

## 5. Orden de implementación

1. Dependencia `excel` + generador de plantilla (probar: descargar y abrir en Excel).
2. Lector + validador de filas con sus tests.
3. Endpoint backend `importar` + tests.
4. Diálogo de 3 pasos + botón en Productos.
5. Build web + prueba manual con un archivo real (con y sin variantes).

---

## 6. Decisiones (cerradas)

1. **Filas con error:** se importan **solo las válidas**; las fallidas se listan
   en la vista previa con su mensaje para corregirlas después.
2. **Producto repetido** (mismo nombre ya en la BD o repetido en el archivo):
   **se salta con aviso** (así se puede re-subir el mismo archivo sin duplicar).
3. **Imágenes:** fuera de la v1; se añadirá después (columna con URL) si hace falta.

---

## 7. Estado de implementación (hecho)

Todo implementado y verificado; solo queda la prueba manual con un archivo real.

| Pieza | Archivo |
|---|---|
| Plantilla descargable (hojas «productos» + «Ayuda») | `frontend/lib/core/excel/plantilla_excel.dart` |
| Lector `.xlsx` (encabezados en cualquier orden/alias, filas numeradas como en el archivo) | `frontend/lib/core/excel/leer_excel.dart` |
| Validador por fila (espejo del formulario) + `ProductoExcel`/`FilaImportacion` | `frontend/lib/core/excel/importar_productos.dart` |
| Diálogo de 3 pasos (elegir → previa → resultado) | `frontend/lib/presentation/widgets/importar_excel_dialog.dart` |
| Botón «Importar Excel» (permiso `productos.crear`) | `frontend/lib/presentation/pages/productos_page.dart` |
| `POST /api/v1/productos/importar` (mejor esfuerzo por fila, omite repetidos) | `backend/lib/src/presentation/routes/producto_routes.dart` |
| Tests (15 lectura/validación + 4 diálogo + 6 backend) | `frontend/test/importar_excel_test.dart`, `importar_excel_dialog_test.dart`, `backend/test/producto_importar_rutas_test.dart` |

Detalles que se salieron del plan:

- La dependencia es **`excel_plus 2.27.1`** (el `excel` original choca con `pdf`
  por la versión de `xml`).
- Las variantes con nombres de talla/color **las resuelve el backend** (mismo
  `_variantesDesdeBody` que el alta normal): el diálogo solo resuelve categoría
  y proveedor.
- Cada fila envía su `fila` real de Excel para que los mensajes del backend
  apunten a lo que se ve en el archivo.
- `normalizarTexto` se mudó a `frontend/lib/core/utils/normalizacion.dart`
  (una sola copia para buscador, variantes e importación) y `buscador_tabla.dart`
  lo reexporta.
