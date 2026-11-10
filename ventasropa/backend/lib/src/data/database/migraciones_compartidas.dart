/// Migraciones con **fuente única**: se definen una sola vez y corren en
/// ambos motores (PostgreSQL para escritorio/web, SQLite para la APK).
///
/// Cómo se usa (regla para futuros cambios de esquema):
///
/// 1. Añade una entrada a [migracionesCompartidas] con el siguiente nombre
///    incremental (`016_...`, `017_...`...).
/// 2. Expresa cada paso con una operación estructurada ([AgregarColumna],
///    [AgregarIndice] o [SqlCompartido]): el `Migrator` la renderiza al
///    dialecto que corresponda según `DB_ENGINE`.
/// 3. Solo si algo no se puede expresar de forma estructurada, usa
///    [SqlPorMotor] — es el **único** sitio donde se escribe SQL por motor.
///
/// El registro `schema_migrations` garantiza que cada migración corre una
/// sola vez en cada base de datos, igual que las 15 clásicas de
/// `migrations.dart` (que no se tocan: ya están aplicadas en producción).
library;

/// Una migración: pasos estructurados con nombre incremental.
final class Migracion {
  const Migracion(this.nombre, this.operaciones);

  /// Nombre incremental único (`016_agrega_columna_x`).
  final String nombre;

  final List<OperacionDdl> operaciones;

  /// SQL de la migración para el motor indicado (`postgres` | `sqlite`).
  String renderizar(String engine) => [
    for (final operacion in operaciones)
      engine == 'sqlite' ? operacion.sqlite : operacion.postgres,
  ].join('\n');
}

/// Un paso de migración traducible a cada motor.
abstract class OperacionDdl {
  const OperacionDdl();

  String get postgres;
  String get sqlite;
}

/// SQL idéntico en ambos motores (sentencias que ya son portables).
final class SqlCompartido extends OperacionDdl {
  const SqlCompartido(this.sql);

  final String sql;

  @override
  String get postgres => sql;

  @override
  String get sqlite => sql;
}

/// Escape hatch: SQL escrito a mano por motor. Úsalo solo cuando la
/// operación no se pueda expresar con las estructuradas (p. ej. un cambio
/// que dependa de funciones exclusivas de cada motor).
final class SqlPorMotor extends OperacionDdl {
  const SqlPorMotor({required this.postgres, required this.sqlite});

  @override
  final String postgres;

  @override
  final String sqlite;
}

/// `ALTER TABLE ... ADD COLUMN`.
///
/// Los tipos van por motor porque lo que cambia es la equivalencia
/// (`TIMESTAMPTZ` ↔ `TEXT`); el resto de la definición es una sola.
final class AgregarColumna extends OperacionDdl {
  const AgregarColumna({
    required this.tabla,
    required this.columna,
    required this.tipoPostgres,
    required this.tipoSqlite,
    this.porDefecto,
    this.noNula = false,
  });

  final String tabla;
  final String columna;
  final String tipoPostgres;
  final String tipoSqlite;

  /// Literal de valor por defecto (`'ACTIVO'`, `0`...); `null` sin defecto.
  final Object? porDefecto;

  final bool noNula;

  String _sql(String tipo) => 'ALTER TABLE $tabla ADD COLUMN $columna $tipo'
      '${noNula ? ' NOT NULL' : ''}'
      '${porDefecto == null ? '' : ' DEFAULT $porDefecto'}';

  @override
  String get postgres => _sql(tipoPostgres);

  @override
  String get sqlite => _sql(tipoSqlite);
}

/// `CREATE INDEX` (la sentencia es idéntica en ambos motores).
final class AgregarIndice extends OperacionDdl {
  const AgregarIndice({
    required this.nombre,
    required this.tabla,
    required this.columnas,
    this.unico = false,
    this.donde,
  });

  final String nombre;
  final String tabla;
  final String columnas;
  final bool unico;

  /// Expresión opcional `WHERE ...` (índice parcial).
  final String? donde;

  String get _sql => 'CREATE INDEX IF NOT EXISTS $nombre ON $tabla '
      '${unico ? 'UNIQUE ' : ''}($columnas)'
      '${donde == null ? '' : ' WHERE $donde'}';

  @override
  String get postgres => _sql;

  @override
  String get sqlite => _sql;
}

/// Venta por unidad o por peso: `productos` gana unidad de venta, código y
/// stock fraccionado; `detalles_ordenes_pedidos` pasa a cantidades
/// fraccionadas con su unidad y costo congelados; y nace el kardex
/// `movimientos_stock`.
///
/// Los `ADD COLUMN` de Postgres van con `IF NOT EXISTS` porque
/// `sql/reset_ventas.sql` ya crea estas columnas al recrear la BD (mismo
/// criterio que las migraciones 011–015). SQLite no admite ni
/// `IF NOT EXISTS` en `ADD COLUMN` ni `ALTER COLUMN ... TYPE`, y su tipado
/// dinámico guarda `12.5` en la columna `INT` sin rechazarla, así que ahí
/// solo se añaden las columnas.
const Migracion _ventasFraccionadas = Migracion('016_ventas_fraccionadas', [
  SqlPorMotor(
    postgres: r'''
ALTER TABLE productos ADD COLUMN IF NOT EXISTS codigo VARCHAR(60);
ALTER TABLE productos
    ADD COLUMN IF NOT EXISTS unidad VARCHAR(10) NOT NULL DEFAULT 'UN'
    CHECK (unidad IN ('UN','KG','GR','LT','ML','CAJA','BLISTER','FRASCO','SOBRE'));
ALTER TABLE productos
    ADD COLUMN IF NOT EXISTS stock_minimo NUMERIC(12, 3)
    CHECK (stock_minimo >= 0);
-- stock entero -> fraccionado (12.5 kg). El CHECK (stock >= 0) se conserva
-- y el índice idx_productos_stock se reconstruye solo.
ALTER TABLE productos
    ALTER COLUMN stock TYPE NUMERIC(12, 3) USING stock::NUMERIC(12, 3);

ALTER TABLE detalles_ordenes_pedidos
    ADD COLUMN IF NOT EXISTS unidad VARCHAR(10) NOT NULL DEFAULT 'UN';
-- Costo al momento de vender (habilita la utilidad por línea). Las líneas
-- ya emitidas quedan en NULL: no se backfillea con el precio_compra actual,
-- que sería mentir sobre el histórico.
ALTER TABLE detalles_ordenes_pedidos
    ADD COLUMN IF NOT EXISTS costo_unitario NUMERIC(10, 2);
ALTER TABLE detalles_ordenes_pedidos
    ALTER COLUMN cantidad TYPE NUMERIC(12, 3) USING cantidad::NUMERIC(12, 3);

-- Comparte `ItemOrden` con las órdenes, así que va a la par.
ALTER TABLE detalles_cotizaciones
    ADD COLUMN IF NOT EXISTS unidad VARCHAR(10) NOT NULL DEFAULT 'UN';
ALTER TABLE detalles_cotizaciones
    ALTER COLUMN cantidad TYPE NUMERIC(12, 3) USING cantidad::NUMERIC(12, 3);
''',
    sqlite: r'''
ALTER TABLE productos ADD COLUMN codigo VARCHAR(60);
ALTER TABLE productos
    ADD COLUMN unidad VARCHAR(10) NOT NULL DEFAULT 'UN'
    CHECK (unidad IN ('UN','KG','GR','LT','ML','CAJA','BLISTER','FRASCO','SOBRE'));
ALTER TABLE productos ADD COLUMN stock_minimo NUMERIC(12, 3)
    CHECK (stock_minimo >= 0);
ALTER TABLE detalles_ordenes_pedidos
    ADD COLUMN unidad VARCHAR(10) NOT NULL DEFAULT 'UN';
ALTER TABLE detalles_ordenes_pedidos ADD COLUMN costo_unitario NUMERIC(10, 2);
ALTER TABLE detalles_cotizaciones
    ADD COLUMN unidad VARCHAR(10) NOT NULL DEFAULT 'UN';
''',
  ),
  SqlCompartido(r'''
CREATE UNIQUE INDEX IF NOT EXISTS idx_productos_codigo ON productos (codigo);
CREATE INDEX IF NOT EXISTS idx_productos_unidad ON productos (unidad);
'''),
  // Kardex: quién movió cuánto stock y por qué. `cantidad` es firmada
  // (positiva = entra, negativa = sale) y `stock_resultante` permite saber
  // el stock en cualquier fecha sin recalcular. El actor de cada movimiento
  // ya lo registra `auditoria`, por eso no se guarda usuario aquí.
  SqlPorMotor(
    postgres: r'''
CREATE TABLE IF NOT EXISTS movimientos_stock (
    movimiento_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id      BIGINT NOT NULL
                         REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cantidad         NUMERIC(12, 3) NOT NULL CHECK (cantidad <> 0),
    motivo           VARCHAR(20) NOT NULL CHECK (motivo IN
                         ('VENTA','DEVOLUCION','COMPRA','AJUSTE','MERMA','INICIAL')),
    stock_resultante NUMERIC(12, 3) NOT NULL CHECK (stock_resultante >= 0),
    orden_id         BIGINT REFERENCES ordenes_pedidos(orden_id)
                         ON DELETE SET NULL,
    notas            VARCHAR(255),
    fecha            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
    sqlite: r'''
CREATE TABLE IF NOT EXISTS movimientos_stock (
    movimiento_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    producto_id      BIGINT NOT NULL
                         REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cantidad         NUMERIC(12, 3) NOT NULL CHECK (cantidad <> 0),
    motivo           VARCHAR(20) NOT NULL CHECK (motivo IN
                         ('VENTA','DEVOLUCION','COMPRA','AJUSTE','MERMA','INICIAL')),
    stock_resultante NUMERIC(12, 3) NOT NULL CHECK (stock_resultante >= 0),
    orden_id         BIGINT REFERENCES ordenes_pedidos(orden_id)
                         ON DELETE SET NULL,
    notas            VARCHAR(255),
    fecha            TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
  ),
  SqlCompartido(r'''
CREATE INDEX IF NOT EXISTS idx_movimientos_producto
    ON movimientos_stock (producto_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_movimientos_orden ON movimientos_stock (orden_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_fecha ON movimientos_stock (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_movimientos_motivo ON movimientos_stock (motivo);
'''),
]);

/// Enfoque ropa: fuera los campos de farmacia (fecha de vencimiento,
/// presentaciones, estado POR_VENCER y unidades que no sean 'UN') y nacen
/// `tallas`, `colores` y `producto_variantes` con stock propio por
/// prenda + talla + color.
///
/// `productos.stock` pasa a ser el **agregado** de sus variantes (se mantiene
/// en la misma transacción que cualquier cambio de variante). El detalle de
/// órdenes y cotizaciones cambia su PK a `(variante_id, ...)` para poder
/// vender varias tallas de la misma prenda en un mismo documento.
///
/// Diseñada para una base **vacía** (`ventarropa`): los `SELECT ... FROM`
/// que copian filas existentes no encuentran datos, y `ALTER TYPE` recrea
/// `estado_producto` sin valores en uso.
const Migracion _ropa = Migracion('017_ropa', [
  SqlPorMotor(
    postgres: r'''
-- =========================================================
-- Productos: eliminar el esquema de farmacia
-- =========================================================
DROP INDEX IF EXISTS idx_productos_presentacion;
DROP INDEX IF EXISTS idx_productos_vencimiento;
ALTER TABLE productos DROP COLUMN IF EXISTS fecha_vencimiento;
ALTER TABLE productos DROP COLUMN IF EXISTS presentacion_id;

-- Venta siempre por unidad entera: solo queda 'UN'
ALTER TABLE productos DROP CONSTRAINT IF EXISTS productos_unidad_check;
ALTER TABLE productos ADD CONSTRAINT productos_unidad_check
    CHECK (unidad IN ('UN'));

-- estado_producto sin POR_VENCER: PostgreSQL no implementa
-- ALTER TYPE ... DROP VALUE, así que se recrea el tipo.
ALTER TABLE productos ALTER COLUMN estado DROP DEFAULT;
ALTER TABLE productos ALTER COLUMN estado TYPE TEXT;
DROP TYPE estado_producto;
CREATE TYPE estado_producto AS ENUM
    ('DISPONIBLE', 'AGOTADO', 'DESCONTINUADO', 'ELIMINADO');
ALTER TABLE productos
    ALTER COLUMN estado TYPE estado_producto USING estado::estado_producto;
ALTER TABLE productos ALTER COLUMN estado SET DEFAULT 'DISPONIBLE';

DROP TABLE IF EXISTS presentaciones;

-- =========================================================
-- Catálogos de ropa y variantes con stock propio
-- =========================================================
CREATE TABLE IF NOT EXISTS tallas (
    talla_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre             VARCHAR(30) NOT NULL UNIQUE,
    orden              INT NOT NULL DEFAULT 0,
    estado             estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS colores (
    color_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre             VARCHAR(50) NOT NULL UNIQUE,
    codigo_hex         VARCHAR(7),
    estado             estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS producto_variantes (
    variante_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id        BIGINT NOT NULL
                         REFERENCES productos(producto_id) ON DELETE CASCADE,
    talla_id           BIGINT NOT NULL REFERENCES tallas(talla_id),
    color_id           BIGINT NOT NULL REFERENCES colores(color_id),
    stock              NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (stock >= 0),
    codigo             VARCHAR(60),
    estado             estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (producto_id, talla_id, color_id)
);

CREATE TRIGGER trg_actualizar_tallas BEFORE UPDATE ON tallas
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_colores BEFORE UPDATE ON colores
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_variantes BEFORE UPDATE ON producto_variantes
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();

-- =========================================================
-- Detalle de órdenes: PK por variante (varias tallas por prenda
-- en la misma orden)
-- =========================================================
ALTER TABLE detalles_ordenes_pedidos DROP CONSTRAINT IF EXISTS detalles_ordenes_pedidos_pkey;
ALTER TABLE detalles_ordenes_pedidos
    ADD COLUMN variante_id BIGINT REFERENCES producto_variantes(variante_id);
ALTER TABLE detalles_ordenes_pedidos ALTER COLUMN variante_id SET NOT NULL;
ALTER TABLE detalles_ordenes_pedidos
    ADD CONSTRAINT detalles_ordenes_pedidos_pkey PRIMARY KEY (variante_id, orden_id);

ALTER TABLE detalles_cotizaciones DROP CONSTRAINT IF EXISTS detalles_cotizaciones_pkey;
ALTER TABLE detalles_cotizaciones
    ADD COLUMN variante_id BIGINT REFERENCES producto_variantes(variante_id);
ALTER TABLE detalles_cotizaciones ALTER COLUMN variante_id SET NOT NULL;
ALTER TABLE detalles_cotizaciones
    ADD CONSTRAINT detalles_cotizaciones_pkey PRIMARY KEY (variante_id, cotizacion_id);

-- Kardex: cada movimiento queda ligado a su variante
ALTER TABLE movimientos_stock
    ADD COLUMN IF NOT EXISTS variante_id BIGINT
        REFERENCES producto_variantes(variante_id) ON DELETE SET NULL;
''',
    sqlite: r'''
-- =========================================================
-- Productos: se recrea para quitar fecha_vencimiento,
-- presentacion_id y el CHECK con POR_VENCER
-- =========================================================
CREATE TABLE Productos_Nueva (
    Producto_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Producto VARCHAR(150) NOT NULL,
    Imagen VARCHAR(500),
    Codigo VARCHAR(60),
    Unidad VARCHAR(10) NOT NULL DEFAULT 'UN' CHECK (Unidad IN ('UN')),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Precio_Compra NUMERIC(10, 2) CHECK (Precio_Compra >= 0),
    Precio_Rebaja NUMERIC(10, 2) CHECK (Precio_Rebaja >= 0),
    Stock NUMERIC(12, 3) DEFAULT 0 CHECK (Stock >= 0),
    Stock_Minimo NUMERIC(12, 3) CHECK (Stock_Minimo >= 0),
    Version INT NOT NULL DEFAULT 0,
    Categoria_ID BIGINT REFERENCES Categorias(Categoria_ID) ON DELETE RESTRICT,
    Proveedor_ID BIGINT REFERENCES Proveedores(Proveedor_ID) ON DELETE RESTRICT,
    Estado TEXT NOT NULL DEFAULT 'DISPONIBLE'
        CHECK (Estado IN ('DISPONIBLE','AGOTADO','DESCONTINUADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO Productos_Nueva
    (Producto_ID, Nombre_Producto, Imagen, Codigo, Unidad, Precio_Venta,
     Precio_Compra, Precio_Rebaja, Stock, Stock_Minimo, Version,
     Categoria_ID, Proveedor_ID, Estado, Fecha_Creacion, Fecha_Actualizacion)
SELECT Producto_ID, Nombre_Producto, Imagen, Codigo, Unidad, Precio_Venta,
       Precio_Compra, Precio_Rebaja, Stock, Stock_Minimo, Version,
       Categoria_ID, Proveedor_ID, Estado, Fecha_Creacion, Fecha_Actualizacion
FROM Productos;
DROP TABLE Productos;
ALTER TABLE Productos_Nueva RENAME TO Productos;

CREATE INDEX IF NOT EXISTS idx_productos_categoria  ON Productos (Categoria_ID);
CREATE INDEX IF NOT EXISTS idx_productos_estado     ON Productos (Estado);
CREATE INDEX IF NOT EXISTS idx_productos_stock      ON Productos (Stock);
CREATE INDEX IF NOT EXISTS idx_productos_nombre     ON Productos (Nombre_Producto);
CREATE INDEX IF NOT EXISTS idx_productos_proveedor  ON Productos (Proveedor_ID);
CREATE UNIQUE INDEX IF NOT EXISTS idx_productos_codigo ON Productos (Codigo);
CREATE INDEX IF NOT EXISTS idx_productos_unidad     ON Productos (Unidad);

CREATE TRIGGER trg_actualizar_productos AFTER UPDATE ON Productos
    FOR EACH ROW BEGIN
        UPDATE Productos SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Producto_ID = NEW.Producto_ID;
    END;

-- Presentaciones fuera
DROP TRIGGER IF EXISTS trg_actualizar_presentaciones;
DROP TABLE IF EXISTS presentaciones;

-- =========================================================
-- Catálogos de ropa y variantes con stock propio
-- =========================================================
CREATE TABLE tallas (
    talla_id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre VARCHAR(30) NOT NULL UNIQUE,
    orden INT NOT NULL DEFAULT 0,
    estado TEXT NOT NULL DEFAULT 'ACTIVO'
        CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE colores (
    color_id INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    codigo_hex VARCHAR(7),
    estado TEXT NOT NULL DEFAULT 'ACTIVO'
        CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE producto_variantes (
    variante_id INTEGER PRIMARY KEY AUTOINCREMENT,
    producto_id BIGINT NOT NULL REFERENCES Productos(Producto_ID) ON DELETE CASCADE,
    talla_id BIGINT NOT NULL REFERENCES tallas(talla_id),
    color_id BIGINT NOT NULL REFERENCES colores(color_id),
    stock NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (stock >= 0),
    codigo VARCHAR(60),
    estado TEXT NOT NULL DEFAULT 'ACTIVO'
        CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (producto_id, talla_id, color_id)
);

CREATE TRIGGER trg_actualizar_tallas AFTER UPDATE ON tallas
    FOR EACH ROW BEGIN
        UPDATE tallas SET fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE talla_id = NEW.talla_id;
    END;
CREATE TRIGGER trg_actualizar_colores AFTER UPDATE ON colores
    FOR EACH ROW BEGIN
        UPDATE colores SET fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE color_id = NEW.color_id;
    END;
CREATE TRIGGER trg_actualizar_variantes AFTER UPDATE ON producto_variantes
    FOR EACH ROW BEGIN
        UPDATE producto_variantes SET fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE variante_id = NEW.variante_id;
    END;

-- =========================================================
-- Detalle de órdenes: PK por variante. Se recrea la tabla
-- (SQLite no permite cambiar la PK in situ); base vacía.
-- =========================================================
CREATE TABLE Detalles_Ordenes_Pedidos_Nueva (
    Producto_ID BIGINT REFERENCES Productos(Producto_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
    Variante_ID BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    Nombre_Producto VARCHAR(150) NOT NULL,
    Unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    Cantidad NUMERIC(12, 3) NOT NULL CHECK (Cantidad > 0),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Costo_Unitario NUMERIC(10, 2),
    Monto_Total NUMERIC(10, 2) NOT NULL CHECK (Monto_Total >= 0),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO'
        CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    PRIMARY KEY (Variante_ID, Orden_ID)
);
INSERT INTO Detalles_Ordenes_Pedidos_Nueva
    (Producto_ID, Orden_ID, Variante_ID, Nombre_Producto, Unidad, Cantidad,
     Precio_Venta, Costo_Unitario, Monto_Total, Estado)
SELECT Producto_ID, Orden_ID, NULL, Nombre_Producto, Unidad, Cantidad,
       Precio_Venta, Costo_Unitario, Monto_Total, Estado
FROM Detalles_Ordenes_Pedidos;
DROP TABLE Detalles_Ordenes_Pedidos;
ALTER TABLE Detalles_Ordenes_Pedidos_Nueva RENAME TO Detalles_Ordenes_Pedidos;

CREATE INDEX IF NOT EXISTS idx_detalles_orden    ON Detalles_Ordenes_Pedidos (Orden_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_producto ON Detalles_Ordenes_Pedidos (Producto_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_estado   ON Detalles_Ordenes_Pedidos (Estado);
CREATE INDEX IF NOT EXISTS idx_detalles_variante ON Detalles_Ordenes_Pedidos (Variante_ID);

CREATE TABLE Detalles_Cotizaciones_Nueva (
    producto_id BIGINT REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cotizacion_id BIGINT REFERENCES cotizaciones(cotizacion_id) ON DELETE CASCADE,
    variante_id BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    nombre_producto VARCHAR(150) NOT NULL,
    imagen VARCHAR(500),
    unidad VARCHAR(10) DEFAULT 'UN',
    cantidad NUMERIC(12, 3) NOT NULL CHECK (cantidad > 0),
    precio_venta NUMERIC(10, 2) NOT NULL CHECK (precio_venta >= 0),
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    PRIMARY KEY (variante_id, cotizacion_id)
);
INSERT INTO Detalles_Cotizaciones_Nueva
    (producto_id, cotizacion_id, variante_id, nombre_producto, imagen, unidad,
     cantidad, precio_venta, monto_total)
SELECT producto_id, cotizacion_id, NULL, nombre_producto, imagen, unidad,
       cantidad, precio_venta, monto_total
FROM detalles_cotizaciones;
DROP TABLE detalles_cotizaciones;
ALTER TABLE Detalles_Cotizaciones_Nueva RENAME TO detalles_cotizaciones;

CREATE INDEX IF NOT EXISTS idx_detalles_cotizaciones_cot ON detalles_cotizaciones (cotizacion_id);

-- Kardex: cada movimiento queda ligado a su variante
ALTER TABLE movimientos_stock
    ADD COLUMN variante_id BIGINT REFERENCES producto_variantes(variante_id)
        ON DELETE SET NULL;
''',
  ),
  SqlCompartido(r'''
CREATE INDEX IF NOT EXISTS idx_variantes_producto ON producto_variantes (producto_id);
CREATE INDEX IF NOT EXISTS idx_variantes_talla    ON producto_variantes (talla_id);
CREATE INDEX IF NOT EXISTS idx_variantes_color    ON producto_variantes (color_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_variante ON movimientos_stock (variante_id);
'''),
  // Sin semillas: los catálogos de `tallas` y `colores` arrancan **vacíos**.
  // Quien crea un producto escribe sus propias tallas (S, M, XXL, 4...) y
  // colores, y el backend los da de alta en el catálogo al guardar. Ver la
  // migración 018, que además limpia las semillas que ya hubiera.
]);

/// `018`: retira los datos de ejemplo de los catálogos de ropa.
///
/// `017_ropa` siembraba tallas (`S`, `M`, `L`, `1`-`8`, `Única`) y colores
/// (`Negro`, `Blanco`, `Rojo`...) de fábrica; eran muestra, no datos del
/// negocio. Se borran las que **ningún producto** tenga puestas —las que ya
/// se usan se conservan para no romper el stock de las prendas existentes—
/// y a partir de ahora cada tienda llena sus catálogos desde la propia app.
const Migracion _catalogoPropio = Migracion('018_catalogo_tallas_colores_propio', [
  SqlCompartido(r'''
DELETE FROM tallas
WHERE NOT EXISTS (
    SELECT 1 FROM producto_variantes v WHERE v.talla_id = tallas.talla_id
);
DELETE FROM colores
WHERE NOT EXISTS (
    SELECT 1 FROM producto_variantes v WHERE v.color_id = colores.color_id
);
'''),
]);

/// `019`: precio propio de cada combinación (talla + color).
///
/// Se creó para poder vender la misma prenda a distinto precio según la
/// talla o el color (`NULL` = el `precio_venta` del producto), pero la app
/// trabaja con **un solo precio por producto**: la `020` retira la columna
/// y esta queda solo como registro histórico —de hecho, en una base nueva
/// se crea y a continuación se borra.
const Migracion _precioPorVariante = Migracion('019_precio_por_variante', [
  SqlPorMotor(
    postgres: r'''
ALTER TABLE producto_variantes
    ADD COLUMN IF NOT EXISTS precio NUMERIC(10, 2);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'producto_variantes_precio_check'
  ) THEN
    ALTER TABLE producto_variantes
      ADD CONSTRAINT producto_variantes_precio_check CHECK (precio >= 0);
  END IF;
END $$;
''',
    // SQLite no admite `IF NOT EXISTS` en `ADD COLUMN`.
    sqlite: r'''
ALTER TABLE producto_variantes
    ADD COLUMN precio NUMERIC(10, 2) CHECK (precio >= 0);
''',
  ),
]);

/// `020`: un único precio por producto.
///
/// Retira `producto_variantes.precio` (creado por la `019`): el precio de
/// venta vive solo en `productos.precio_venta` y todas las variantes de una
/// prenda se venden a ese precio. Como la `019` corre justo antes, la
/// columna siempre existe cuando llega aquí —en Postgres además con
/// `IF NOT EXISTS` por si una base no la hubiera llegado a crear—.
const Migracion _unSoloPrecio = Migracion('020_quitar_precio_por_variante', [
  SqlPorMotor(
    postgres: r'''
ALTER TABLE producto_variantes DROP COLUMN IF EXISTS precio;
''',
    // `DROP COLUMN` no admite `IF EXISTS` y SQLite no tiene DDL condicional,
    // por eso la `019` (que sí la crea) debe seguir en la lista.
    sqlite: r'''
ALTER TABLE producto_variantes DROP COLUMN precio;
''',
  ),
]);

/// `021`: permisos del módulo «Reportes».
///
/// Nace como módulo de **solo consulta** (informes de ventas), así que se
/// crean sus cuatro acciones —la matriz de Roles de la app pinta `módulo ×
/// 4`— pero solo el rol ADMIN las recibe, igual que hizo la `010_auditoria`
/// con Auditoría. Cualquier otro rol se le puede conceder después desde la
/// pestaña «Roles».
///
/// «Página inicial» guarda un **índice de `navItems`**: Reportes entra en
/// el 11 y Ajustes baja al 12, así que el ajuste guardado se reajusta (mismo
/// truco que la `010_auditoria`, que movió Ajustes del 10 al 11).
const Migracion _permisosReportes = Migracion('021_permisos_reportes', [
  SqlPorMotor(
    postgres: r'''
INSERT INTO Permisos (Modulo, Accion)
SELECT 'reportes', a.Accion
FROM (VALUES ('ver'), ('crear'), ('editar'), ('eliminar')) AS a(Accion)
ON CONFLICT (Modulo, Accion) DO NOTHING;

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p ON p.Modulo = 'reportes'
WHERE r.Nombre = 'ADMIN'
ON CONFLICT DO NOTHING;

UPDATE ajustes SET valor = '12'
WHERE clave = 'paginaInicial' AND valor = '11';
''',
    // En SQLite la forma idempotente sencilla es `INSERT OR IGNORE` (las dos
    // claves ya son UNIQUE); en PostgreSQL, `ON CONFLICT DO NOTHING`.
    sqlite: r'''
INSERT OR IGNORE INTO Permisos (Modulo, Accion)
SELECT 'reportes', a.Accion FROM (
    SELECT 'ver' AS Accion UNION ALL
    SELECT 'crear' UNION ALL
    SELECT 'editar' UNION ALL
    SELECT 'eliminar'
) a;

INSERT OR IGNORE INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p ON p.Modulo = 'reportes'
WHERE r.Nombre = 'ADMIN';

UPDATE ajustes SET valor = '12'
WHERE clave = 'paginaInicial' AND valor = '11';
''',
  ),
]);

/// `022`: email y NIT del proveedor.
///
/// Dos columnas opcionales (`NULL` en los proveedores ya registrados): el
/// NIT con el que se factura y un correo de contacto. Ninguna es única: la
/// validación de forma vive en la API (`ensureEmail`/`ensureNit`), así una
/// tienda puede repetir NIT si sus proveedores comparten facturación.
const Migracion _proveedoresContacto = Migracion('022_proveedores_email_nit', [
  SqlPorMotor(
    // En Postgres `IF NOT EXISTS` porque `sql/reset_ventas.sql` ya crea las
    // columnas al recrear la BD (mismo criterio que la 016).
    postgres: r'''
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS email VARCHAR(150);
ALTER TABLE proveedores ADD COLUMN IF NOT EXISTS nit VARCHAR(20);
''',
    // SQLite no admite `IF NOT EXISTS` en `ADD COLUMN` y su esquema base
    // (`000_esquema_sqlite`) no las trae, así que aquí siempre se añaden.
    sqlite: r'''
ALTER TABLE proveedores ADD COLUMN email VARCHAR(150);
ALTER TABLE proveedores ADD COLUMN nit VARCHAR(20);
''',
  ),
]);

/// `023`: descripción libre del producto.
///
/// Columna opcional (`NULL` en los productos ya registrados) para notas
/// largas de la ficha: materiales, cuidados, temporada... No es única ni
/// obligatoria: la validación de forma vive en la API (`maxLength` en
/// `producto_routes.dart`), así el límite se ajusta sin tocar la BD.
const Migracion _descripcionProducto = Migracion('023_descripcion_producto', [
  SqlPorMotor(
    // En Postgres `IF NOT EXISTS` porque `sql/reset_ventas.sql` ya crea la
    // columna al recrear la BD (mismo criterio que las 016 y la 022).
    postgres: r'''
ALTER TABLE productos ADD COLUMN IF NOT EXISTS descripcion TEXT;
''',
    // SQLite no admite `IF NOT EXISTS` en `ADD COLUMN`.
    sqlite: r'''
ALTER TABLE productos ADD COLUMN descripcion TEXT;
''',
  ),
]);

/// `024`: catálogo de marcas de ropa.
///
/// Tabla nueva `marcas` (nombre + estado, borrado lógico como categorías)
/// y columna opcional `productos.marca_id`: la marca es **anulable**, todo
/// producto puede existir sin ella. El trigger de fechas existe en ambos
/// motores por consistencia con `categorias`/`tallas` (el repositorio
/// además fija `fecha_actualizacion` en cada UPDATE).
const Migracion _marcas = Migracion('024_marcas', [
  SqlPorMotor(
    // En Postgres `IF NOT EXISTS` en ALTER/INDEX porque
    // `sql/reset_ventas.sql` ya crea la tabla y la columna al recrear la
    // BD (mismo criterio que las 016, 022 y 023); ese script además
    // siembra `024_marcas` en `schema_migrations`, así que esta migración
    // no vuelve a correr ahí y el `CREATE TRIGGER` no se duplica.
    postgres: r'''
-- =========================================================
-- Marcas de ropa (opcional en productos)
-- =========================================================
CREATE TABLE IF NOT EXISTS marcas (
    marca_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_marca        VARCHAR(100) NOT NULL,
    estado              estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE productos ADD COLUMN IF NOT EXISTS marca_id BIGINT
    REFERENCES marcas(marca_id);
CREATE INDEX IF NOT EXISTS idx_productos_marca ON productos (marca_id);

CREATE TRIGGER trg_actualizar_marcas BEFORE UPDATE ON marcas
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
''',
    // SQLite no admite `IF NOT EXISTS` en `ADD COLUMN`; la tabla se crea
    // con `IF NOT EXISTS` porque el esquema base no la trae.
    sqlite: r'''
CREATE TABLE IF NOT EXISTS marcas (
    marca_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre_marca        VARCHAR(100) NOT NULL,
    estado              TEXT NOT NULL DEFAULT 'ACTIVO'
        CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE productos ADD COLUMN marca_id BIGINT REFERENCES marcas(marca_id);
CREATE INDEX IF NOT EXISTS idx_productos_marca ON productos (marca_id);

CREATE TRIGGER trg_actualizar_marcas AFTER UPDATE ON marcas
    FOR EACH ROW BEGIN
        UPDATE marcas SET fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE marca_id = NEW.marca_id;
    END;
''',
  ),
]);

/// Lista única de migraciones futuras (ambos motores).
///
/// Las 15 migraciones originales de PostgreSQL viven en `migrations.dart`
/// y el esquema base de SQLite en `migrations_sqlite.dart`; esta lista es
/// para TODO lo que se cambie a partir de ahora.
const List<Migracion> migracionesCompartidas = [
  _ventasFraccionadas,
  _ropa,
  _catalogoPropio,
  _precioPorVariante,
  _unSoloPrecio,
  _permisosReportes,
  _proveedoresContacto,
  _descripcionProducto,
  _marcas,
];
