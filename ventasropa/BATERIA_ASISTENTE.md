# Batería de preguntas del asistente IA

> ⚠️ **OBSOLETO — batería del sistema de farmacia.** Este listado se escribió
> cuando el sistema era de farmacia: muchas preguntas hablan de medicamentos,
> vencimientos y «presentaciones» (entidad eliminada por la migración
> `017_ropa`; ver `backend/README.md`). Sirve como histórico del formato
> `esperada|pregunta` de `tool/bateria_asistente.dart`, no como referencia
> de las capacidades actuales del asistente.

Listado de las preguntas con las que se probó el asistente (Ollama +
Qwen2.5-1.5B) contra la BD real. Resultado final: **177/177 con
enrutado correcto, 0 fallos** (246 tests en verde), confirmado en
corridas seguidas.

> **Moneda**: todas las respuestas del chat usan **Bs** (igual que el
> resto de la app), nunca dólares.

## Cómo volver a ejecutarla

```bash
cd backend
dart run tool/bateria_asistente.dart "%COMMANDCODE_SCRATCHPAD%\bateria.txt"
```

Cada línea del fichero es `esperada|pregunta` (nombre de la función,
`conversacional`, `falta_info` o `ninguna`). La herramienta imprime
`[OK]`/`[FALLO]` con la respuesta y un resumen. Simula además
conversación real: las preguntas que empiezan por «y …» se clasifican
con la pregunta anterior como historial (para probar anáforas).

Diagnóstico de una pregunta suelta (decisión + datos crudos + respuesta):

```bash
dart run tool/diag_asistente.dart "pregunta"
```

---

## Cobertura por tabla

| Tabla | Funciones del catálogo |
|---|---|
| productos | producto_stock (con presentación y proveedor), productos_extremo, productos_buscar, productos_categoria, productos_presentacion, alertas_stock, inventario_resumen, ventas_producto |
| categorias | productos_categoria, ventas_categoria (más/menos/**sin** ventas), conteo |
| presentaciones | productos_presentacion (y lista las disponibles), conteo, dato en producto_stock |
| proveedores | conteo, proveedor en producto_stock («¿quién me provee X?»), **proveedor_buscar** (nombre/ciudad; sin término lista) |
| clientes | cliente_buscar, cliente_top (más/menos/**sin** compras), conteo |
| empleados | conteo, nombre en usuario_buscar, **vendedor_top** (quién vende más/menos); buscar/datos de empleado → usuario_buscar |
| usuarios | usuario_buscar (login, nombre o rol), conteo; sin nombre lista los primeros («lista de usuarios») |
| roles | usuario_buscar (rol), conteo |
| ordenes_pedidos | ventas_totales, cliente_top, vendedor_top, pedidos_pendientes, conteo |
| detalles_ordenes_pedidos | ventas_detalle, ventas_producto |
| pagos | pagos_resumen (periodo + método: EFECTIVO, QR, TARJETA…), conteo |
| facturas | facturas_resumen (subtotal, rebajas, IVA), conteo |
| cotizaciones | cotizaciones_vigentes, conteo |
| ajustes | ajustes_listar |
| auditoría / sesiones / permisos / detalles_cotizaciones | **no expuestas** (ver nota) |

**Nota**: `auditoría` y `permisos` no se consultan por chat a propósito:
la API los protege por RBAC y el chat no valida permisos por rol — exponerlos
rompería ese control. `sesiones` es interno y `detalles_cotizaciones` se
responde con «cotización N» (función pendiente si algún día la pides).

## Las 177 preguntas

### Cortesía (respondidas por el back, sin IA)
`hola` · `gracias` · `buenas noches` · `que puedes hacer` · `ayuda` ·
`adios` · `buenas` · `quien eres tu` · `que eres`

### Inventario y conteos
| Pregunta | Esperado |
|---|---|
| cuantos medicamentos tengo | inventario_resumen |
| cuantos productos tengo disponibles | inventario_resumen |
| cuanto stock tengo en total | inventario_resumen |
| como esta mi inventario | inventario_resumen |
| que productos tengo en total | inventario_resumen |
| resumen general del stock | inventario_resumen |
| cuanto stock tengo y cuanto vendi | inventario_resumen |
| cuantos clientes tengo | conteo |
| cuantos proveedores tenemos | conteo |
| cuantos empleados hay | conteo |
| cuantas categorias tenemos | conteo |
| cuantas facturas hay | conteo |
| cuantos usuarios estan registrados | conteo |
| cuantas cotizaciones tengo | conteo |
| cuantas ordenes hemos hecho | conteo |
| cuanta gente trabajamos aqui | conteo |
| cuantos clientes activos tenemos | conteo |
| cuanta clientela tenemos | conteo |

### Stock y productos
| Pregunta | Esperado |
|---|---|
| cuanto tengo de ibuprofeno / q tengo… / ibuprofeno cuanto tenemos | producto_stock |
| precio del paracetamol · precio ibuprofeno · cuanto cuesta el ibuprofeno | producto_stock |
| tengo ibuprofeno · donde tengo ibuprofeno | producto_stock |
| cuanto stock hay de paracetamol · paracetamol stock | producto_stock |
| me falta stock de ibuprofeno · cuanta ibuprofeno me queda | producto_stock |
| cuanto tengo de eso / cuanto queda de eso / y eso cuanto vale | falta_info |
| cuanto tengo de pracetamol (typo) · quimetina (inexistente) | falta_info |
| cual es el producto con mas stock · el medicoamento con mas stock | productos_extremo |
| el mas caro · el mas barato que tienes · el de mas unidades | productos_extremo |
| que producto tiene menos stock | productos_extremo |
| que esta por vencer · productos por vencer este mes | alertas_stock |
| que productos estan agotados · que se agoto · sin existencias | alertas_stock |
| hay algo con stock bajo · productos con menos de 10 unidades | alertas_stock |
| que me caduca pronto · algo se me esta caducando · vencimientos proximos | alertas_stock |
| que vence en 30 dias (dias=30) · productos al limite para reponer | alertas_stock |
| buscar paracetamol · existe el complejo b · que productos hay de vitaminas | productos_buscar |
| necesito ver las gasas · buscar producto xyz no existe | productos_buscar |
| productos de la categoria analgesicos · hay en la categoria antibioticos | productos_categoria |

### Ventas
| Pregunta | Esperado |
|---|---|
| cuanto vendi hoy / ayer · facturacion de hoy · VENTAS DE HOY | ventas_totales |
| que tal la venta de esta semana · cuanto vendi la semana pasada | ventas_totales |
| cuanto facture este mes · facturacion del mes · como me ha ido este ano | ventas_totales |
| cuanto ingrese el mes pasado · como vamos en ventas · hoy como vamos | ventas_totales |
| cuanto ganamos este mes · cuanto cobramos este mes | ventas_totales |
| como fue el dia de ayer en ventas · oee cuanto vendi hoy | ventas_totales |
| y del mes pasado · y de la semana pasada? (anáfora) | ventas_totales |
| que vendiste mas este mes · cual es el mas vendido · top de ventas | ventas_detalle |
| de todos cual producto vendi mas · que procto he vendido mas | ventas_detalle |
| k vendi ayer · que vendio hoy · que se vende mejor · los mas vendidos | ventas_detalle |
| top de ventas del mes pasado · los 3 mas vendidos · el mas vendido de ayer | ventas_detalle |
| que vendio mas en dermatologicos · que se vendio en octubre | ventas_detalle |
| cuanto vendi de ibuprofeno este mes · de paracetamol cuanto vendi | ventas_producto |
| que tal se vendio el paracetamol · cuanto vendi de producto inventado | ventas_producto |
| ventas por categoria · como van las categorias · en que categoria gano mas | ventas_categoria |

### Pedidos, cotizaciones y clientes
| Pregunta | Esperado |
|---|---|
| hay pedidos pendientes · que ordenes sin cobrar tengo · que me deben | pedidos_pendientes |
| tengo cotizaciones · que cotizaciones abiertas · que propuestas abiertas | cotizaciones_vigentes |
| buscar cliente garcia · datos del cliente rodriguez · telefono de maria | cliente_buscar |
| tienes a maria · cliente garcia | cliente_buscar |
| datos del cliente que no existe | falta_info |
| que cliente compra mas · mejor cliente · gasto mas este mes | cliente_top |

### Usuarios, roles, pagos, facturas, presentaciones y ajustes
| Pregunta | Esperado |
|---|---|
| que rol tiene carlos_admin | usuario_buscar |
| usuarios con rol cajero | usuario_buscar |
| cuantos roles hay | conteo |
| cuantas presentaciones tenemos | conteo |
| cuantos pagos hay | conteo |
| cuanto cobre en qr hoy · ventas en efectivo de hoy · resumen de pagos | pagos_resumen |
| cuanto iva lleve hoy · facturas del mes pasado | facturas_resumen |
| productos en blister · que presentaciones hay | productos_presentacion |
| quien me provee ibuprofeno · presentacion de ibuprofeno | producto_stock |
| que ajustes hay | ajustes_listar |

### Vendedores
| Pregunta | Esperado |
|---|---|
| que vendedor vende mas | vendedor_top (mas_vendido) |
| que vendedor es el que menos vende | vendedor_top (menos_vendido) |
| cual es el mejor vendedor | vendedor_top |

### Combinaciones de parámetros
| Pregunta | Qué prueba |
|---|---|
| el mas caro de la categoria analgesicos | criterio + categoría (swap de función) |
| el producto mas barato de antibioticos | criterio + categoría sin «de la» |
| que por vencer hay en vitaminas | alertas filtradas por categoría |
| que vendio mas en dermatologicos | top + categoría |
| top de ventas del mes pasado | ranking + periodo (pismo de claves) |
| facturacion de la semana pasada | periodo semana_pasada |
| agotados con stock de 0 | subtipo + umbral |
| productos con menos de 10 unidades | umbral numérico (umbral=10) |
| cuantos productos de la categoria analgesicos | conteo de la categoría, no general |
| que se vendio en octubre | mes con nombre |

### Acciones y predicciones (fuera de alcance → ninguna)
`cuanto venderemos manana` · `reponer stock` · `creame un cliente nuevo` ·
`cuanto costaba ayer el ibuprofeno` · `recomiendame que medicamento tomar` ·
`escribe un resumen de tu vida` · `juega conmigo` · `traduce hola al frances` ·
`puedes borrar un producto` · `como me siento hoy` · `cuanto es la raiz de 144`

### Ruido, typos, voz informal e inglés
`oee cuanto vendi hoy` · `iba a preguntarte cuantos tengo de ibuprofeno` ·
`buenas, me puedes decir que productos estan por vencer?` ·
`paracetamol stock` · `cuanto stock tengo y cuanto vendi` ·
`what is the stock` (→ ninguna)

### Fuera del catálogo clásico
`que tiempo hara manana` · `inventa una receta para la gripe` ·
`chiste de la tienda` · `cuanto es 2 mas 2` · `escribeme un poema` ·
`como curar la diabetes` · `dime un secreto`

### Anáfora (historial = la pregunta anterior)
`cuanto vendi ayer` → **`y del mes pasado`** · **`y de la semana pasada?`**
`cuanto tengo de ibuprofeno` → **`y la paracetamol?`**
`y que pasa con las cotizaciones` (sin setter: la caza el resolvedor)

### Correcciones y negaciones (captura real del usuario)
| Pregunta | Esperado |
|---|---|
| que producto tengo mas | productos_extremo (mas_stock) |
| que prodycto tengo mas (typo) | productos_extremo |
| el que tengo mas no el vendido | productos_extremo |
| que producto tengo ma no cual vendido mas | productos_extremo |

---

## Fase PENSO (la IA piensa antes de responder)

La respuesta de `POST /api/v1/chat` puede incluir `pensamiento`: la línea
**«PENSO: …»** que el modelo escribe ANTES de elegir función, donde
reformula la pregunta **corrigiendo typos y aclarando negaciones**:

```
P: que prodycto tengo ma no cual vendido mas
PENSO: Quiere saber qué producto tiene con más STOCK, no el más vendido.
→ respuesta…
```

- El frontend lo muestra como un mensaje propio **«Pienso: …»** antes de
  la respuesta.
- Se pasa además al narrador («Lo que el usuario quiere decir: …») para
  que redacte según lo entendido, no según la frase con errores.
- Si la decisión por palabras clave y la de la IA **no coinciden**, no se
  muestra el pensamiento (mejor no enseñar un razonamiento que no se
  siguió); la decisión ejecutada sigue siendo la de las palabras clave.

## Bugs que destapó la batería (todos corregidos)

1. **Acentos**: `ILIKE` no casaba «analgesicos» con «Analgésicos» →
   `translate(lower(...))` en todas las búsquedas.
2. **`cliente_buscar` buscaba en `productos`** → «garcia» acababa en
   falta_info; ahora busca en `clientes` (nombre o apellido).
3. **Claves que faltaban**: «cuanto vale/ganamos/cobramos», «me queda»,
   «se agoto», «sin existencias», «para reponer», «top de ventas»,
   «me deben», «resumen», «dia de ayer», «mes pasado», etc.
4. **Aritmética** («2 más 2») iba a `ventas_totales` → guard → `ninguna`.
5. **«vence en 30 días» ejecutaba `stock_bajo`** → `_tipoAlertaDe`.
6. **El modelo se inventaba sumas y elegía filas al azar en listas** →
   listados y vacíos los responde el back directo (respuesta en la
   primera línea); la IA solo narra escalares de una línea. Totales
   siempre precalculados.
7. **Errata `ELIMINIDO`** (3 veces) → test `erratas_test.dart`.
8. **Combinaciones**: «el más caro de la categoría» → swap de función
   (gana la que admite criterio); «cuántos productos de la categoría» →
   cuenta la categoría; «de paracetamol cuanto vendi» → ventas_producto.
9. **Historial dañino**: con respuestas previas el modelo respondía
   «ninguna» a medio catálogo → historial SOLO para preguntas que
   empiezan por «y …» y solo las preguntas del usuario.
10. **Fuera de alcance con forma fija** (acciones, predicciones, inglés,
    chit-chat personal, precios históricos) → guard determinista sin IA.
11. **Negaciones y correcciones**: «no cual vendido mas» acababa en
    ventas_detalle (justo lo negado) → el puntuador ignora claves tras un
    «no» cercano; «que producto tengo mas» → clave `tengo mas` (stock);
    las correcciones («no, el que…», «me refiero…») pasan con historial.
12. **Moneda**: las respuestas usaban `$` → todas en **Bs** (14 sitios),
    igual que el resto de la app.
13. **Pregunta de negocio sin función**: «qué cliente compra más» →
    función nueva `cliente_top` (top de clientes por importe, con
    periodo).
14. **PENSO sin JSON**: el 1.5B a veces se quedaba en la línea de
    pensamiento y olvidaba el JSON → reintento automático + regla dura
    en el prompt.
15. **Fallback por menciones**: sin claves, si la frase nombra un
    producto o cliente REAL de la BD («tengo ibuprofeno», «cliente
    garcia») se resuelve sin IA.
16. **Esquema real vs supuesto**: `empleados` no tiene `nombre`/`apellido`
    (es `nombre_empleado`) — las consultas de usuario fallaban en la BD
    real; el test de erratas cazó además otra aparición de `ELIMINIDO`.
17. **Ranking de personas → productos**: «que vendedor/usuario ha vendido
    más productos» acababa en `ventas_detalle` («vendido mas» puntuaba más
    que «vendedor») y se listaban productos → swap a `vendedor_top` si la
    frase nombra persona + verbo de venta + superlativo
    (`_esRankingDePersonas`).
18. **Buscar en la tabla equivocada**: «buscar empleado/rol/proveedor» y
    «datos del empleado» caían en `productos_buscar`/`cliente_buscar` →
    claves nuevas en `usuario_buscar`, función nueva `proveedor_buscar` y
    «usuario/empleado/proveedor(s)» como muletillas (nunca son nombres de
    producto). `usuario_buscar` sin nombre obligatorio lista los primeros
    («lista de usuarios»).
19. **Negación de ventas**: «¿qué producto no se vende?» respondía con el
    top de los MÁS vendidos → criterio nuevo `sin_vender` en
    `ventas_detalle` (claves «no se vende/sin ventas…» + SQL `NOT EXISTS`
    que lista los productos sin ventas en el periodo).
20. **Patrón «más / menos / nada» generalizado**: el mismo esquema de
    criterio ahora cubre todas las tablas de ranking — `cliente_top`
    (`mas_compra`/`menos_compra`/`sin_compras`) y `ventas_categoria`
    (`mas_vendido`/`menos_vendido`/`sin_vender`), con las mismas claves
    («peor cliente», «categoria que menos», «sin compras»…) y detección de
    negación en `_criterioDe`. Al final es la misma SQL con otro `ORDER
    BY` o un `NOT EXISTS`.

## Limitaciones conocidas

- El 1.5B a veces redacta un escalar de forma rara («por cada orden»,
  omite la CI) — nunca inventa cifras.
- Anáfora solo en la forma «y …»; «¿cómo fue eso?» no se resuelve.
- «vitamina z» con un producto real «Vitamina C» puede casar por
  coincidencia parcial de palabras.
- Listas largas se muestran en crudo (formato del back), sin narración.
