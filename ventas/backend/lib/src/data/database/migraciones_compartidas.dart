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

  String _sql(String tipo) =>
      'ALTER TABLE $tabla ADD COLUMN $columna $tipo'
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

  String get _sql =>
      'CREATE INDEX IF NOT EXISTS $nombre ON $tabla '
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

/// Catálogo de unidades de medida (`unidades`): la tabla que alimenta el
/// desplegable «Unidad de venta» del producto y la pantalla homónima.
///
/// Además de crearla y sembrarla con las unidades de partida:
///
/// * **levanta el `CHECK` fijo** de `productos.unidad` que puso la 016
///   (`UN, KG, GR, LT, ML, CAJA, BLISTER, FRASCO, SOBRE`): la validez de una
///   unidad la pasa a decidir esta tabla (vía `ensureUnidad`). En SQLite eso
///   no se puede hacer con `DROP CONSTRAINT`, así que la columna se reescribe
///   guardando antes sus valores (`_unidad_tmp`); en PostgreSQL se borra el
///   constraint. No se añade FK: SQLite no puede añadirla a una tabla ya
///   existente y la integridad tiene que ser igual en los dos motores — la
///   garantiza `Unidades.asegurarUnidadVigente` al escribir el producto.
/// * siembra los **permisos** del módulo `unidades` (13º de la app) y su
///   concesión a ADMIN (los cuatro) y a CAJERO (solo lectura), igual que hizo
///   la 010 con `auditoria`.
/// * reajusta el ajuste «página inicial» guardado: Unidades ocupa el 11 y
///   Ajustes pasa del 11 al 12 (sigue siendo la última entrada).
const Migracion _unidadesMedida = Migracion('017_unidades_medida', [
  // --- Tabla ---------------------------------------------------------------
  SqlPorMotor(
    postgres: r'''
CREATE TABLE IF NOT EXISTS unidades_medida (
    unidad_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo             VARCHAR(10) UNIQUE NOT NULL,
    nombre_unidad      VARCHAR(50) NOT NULL,
    tipo               VARCHAR(20) NOT NULL
                           CHECK (tipo IN ('PESO','VOLUMEN','UNIDAD')),
    decimales          SMALLINT NOT NULL DEFAULT 0
                           CHECK (decimales BETWEEN 0 AND 3),
    estado             estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
    sqlite: r'''
CREATE TABLE IF NOT EXISTS unidades_medida (
    unidad_id          INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo             VARCHAR(10) UNIQUE NOT NULL,
    nombre_unidad      VARCHAR(50) NOT NULL,
    tipo               VARCHAR(20) NOT NULL
                           CHECK (tipo IN ('PESO','VOLUMEN','UNIDAD')),
    decimales          SMALLINT NOT NULL DEFAULT 0
                           CHECK (decimales BETWEEN 0 AND 3),
    estado             TEXT NOT NULL DEFAULT 'ACTIVO'
                           CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
  ),
  // --- Semilla: unidades de partida ---------------------------------------
  // Los 9 códigos que ya usaban productos (KG, UN, CAJA...) más el resto
  // (peso y volumen de todo el comercio, envases): 15 en total.
  SqlPorMotor(
    postgres: r'''
INSERT INTO unidades_medida (codigo, nombre_unidad, tipo, decimales)
VALUES ('KG', 'Kilogramo', 'PESO', 3),
       ('GR', 'Gramo', 'PESO', 3),
       ('LB', 'Libra', 'PESO', 3),
       ('ONZA', 'Onza', 'PESO', 3),
       ('LT', 'Litro', 'VOLUMEN', 3),
       ('ML', 'Mililitro', 'VOLUMEN', 3),
       ('GALON', 'Galón', 'VOLUMEN', 3),
       ('UN', 'Unidad', 'UNIDAD', 0),
       ('DOCENA', 'Docena', 'UNIDAD', 0),
       ('PAQUETE', 'Paquete', 'UNIDAD', 0),
       ('CAJA', 'Caja', 'UNIDAD', 0),
       ('BLISTER', 'Blister', 'UNIDAD', 0),
       ('FRASCO', 'Frasco', 'UNIDAD', 0),
       ('SOBRE', 'Sobre', 'UNIDAD', 0),
       ('ROLLO', 'Rollo', 'UNIDAD', 0)
ON CONFLICT (codigo) DO NOTHING;
''',
    sqlite: r'''
INSERT OR IGNORE INTO unidades_medida
    (codigo, nombre_unidad, tipo, decimales)
VALUES ('KG', 'Kilogramo', 'PESO', 3),
       ('GR', 'Gramo', 'PESO', 3),
       ('LB', 'Libra', 'PESO', 3),
       ('ONZA', 'Onza', 'PESO', 3),
       ('LT', 'Litro', 'VOLUMEN', 3),
       ('ML', 'Mililitro', 'VOLUMEN', 3),
       ('GALON', 'Galón', 'VOLUMEN', 3),
       ('UN', 'Unidad', 'UNIDAD', 0),
       ('DOCENA', 'Docena', 'UNIDAD', 0),
       ('PAQUETE', 'Paquete', 'UNIDAD', 0),
       ('CAJA', 'Caja', 'UNIDAD', 0),
       ('BLISTER', 'Blister', 'UNIDAD', 0),
       ('FRASCO', 'Frasco', 'UNIDAD', 0),
       ('SOBRE', 'Sobre', 'UNIDAD', 0),
       ('ROLLO', 'Rollo', 'UNIDAD', 0);
''',
  ),
  // --- `productos.unidad` deja de tener lista fija --------------------------
  SqlPorMotor(
    postgres: r'''
DO $$
DECLARE
    c RECORD;
BEGIN
    FOR c IN
        SELECT conname FROM pg_constraint
        WHERE conrelid = 'productos'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%unidad%'
    LOOP
        EXECUTE format('ALTER TABLE productos DROP CONSTRAINT %I', c.conname);
    END LOOP;
END $$;
''',
    // La columna lleva el CHECK dentro de su definición (016) y SQLite no
    // tiene `DROP CONSTRAINT`: se guardan los códigos en una tabla temporal,
    // se reescribe la columna sin CHECK y se devuelven. `DROP COLUMN` exige
    // que no haya índices sobre ella.
    sqlite: r'''
CREATE TABLE _unidad_tmp AS SELECT producto_id, unidad FROM productos;
DROP INDEX IF EXISTS idx_productos_unidad;
ALTER TABLE productos DROP COLUMN unidad;
ALTER TABLE productos ADD COLUMN unidad VARCHAR(10) NOT NULL DEFAULT 'UN';
UPDATE productos SET unidad = COALESCE(
    (SELECT u.unidad FROM _unidad_tmp u
      WHERE u.producto_id = productos.producto_id), unidad);
DROP TABLE _unidad_tmp;
CREATE INDEX IF NOT EXISTS idx_productos_unidad ON productos (unidad);
''',
  ),
  // --- Permisos del módulo `unidades` (13º módulo de la app) ----------------
  SqlPorMotor(
    postgres: r'''
INSERT INTO Permisos (Modulo, Accion) VALUES
       ('unidades', 'ver'), ('unidades', 'crear'),
       ('unidades', 'editar'), ('unidades', 'eliminar')
ON CONFLICT (Modulo, Accion) DO NOTHING;

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p ON p.Modulo = 'unidades'
WHERE r.Nombre = 'ADMIN' OR (r.Nombre = 'CAJERO' AND p.Accion = 'ver')
ON CONFLICT DO NOTHING;
''',
    sqlite: r'''
INSERT OR IGNORE INTO Permisos (Modulo, Accion) VALUES
       ('unidades', 'ver'), ('unidades', 'crear'),
       ('unidades', 'editar'), ('unidades', 'eliminar');

INSERT OR IGNORE INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p ON p.Modulo = 'unidades'
WHERE r.Nombre = 'ADMIN' OR (r.Nombre = 'CAJERO' AND p.Accion = 'ver');
''',
  ),
  // --- «Página inicial» guarda el ÍNDICE del menú --------------------------
  SqlCompartido(r'''
UPDATE ajustes SET valor = '12' WHERE clave = 'paginaInicial' AND valor = '11';
'''),
]);

/// Descripción libre del producto (`productos.descripcion`): texto opcional
/// de hasta 255 caracteres que explica qué es o para qué sirve («jarabe para
/// la tos», «de venta suelta»…).
///
/// Columna nueva en una tabla ya existente, así que va como `ADD COLUMN`:
/// en PostgreSQL con `IF NOT EXISTS`, porque `sql/reset_ventas.sql` ya la
/// crea al recrear la BD (mismo criterio que las 011–016); SQLite no admite
/// `IF NOT EXISTS` y su migración corre una sola vez.
const Migracion _productoDescripcion = Migracion('018_producto_descripcion', [
  SqlPorMotor(
    postgres: r'''
ALTER TABLE productos ADD COLUMN IF NOT EXISTS descripcion VARCHAR(255);
''',
    sqlite: r'''
ALTER TABLE productos ADD COLUMN descripcion VARCHAR(255);
''',
  ),
]);

/// Permisos del módulo `reportes` (14º módulo de la app): la pantalla
/// «Reportes» solo tiene acción de lectura.
///
/// En la tabla `Permisos` entran los 4 permisos del módulo —igual que en el
/// resto, y así la matriz de la pestaña «Roles» sigue siendo módulo ×
/// acción—, pero el que se **concede** automáticamente es `reportes.ver`, y
/// solo a los roles que ya tenían `dashboard.ver`: quien puede ver los
/// gráficos del dashboard puede ver el informe de ventas.
///
/// El ranking del dashboard (`/reportes/productos-vendidos`) pasó a exigir
/// `reportes.ver` en vez de `dashboard.ver`, y como el permiso se copia
/// desde `dashboard.ver`, ningún rol pierde acceso.
const Migracion _permisoReportes = Migracion('019_permiso_reportes', [
  SqlPorMotor(
    postgres: r'''
INSERT INTO Permisos (Modulo, Accion) VALUES
       ('reportes', 'ver'), ('reportes', 'crear'),
       ('reportes', 'editar'), ('reportes', 'eliminar')
ON CONFLICT (Modulo, Accion) DO NOTHING;

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT rp.Rol_ID, nuevo.Permiso_ID
  FROM Rol_Permisos rp
  JOIN Permisos nuevo ON nuevo.Modulo = 'reportes' AND nuevo.Accion = 'ver'
 WHERE EXISTS (
         SELECT 1
           FROM Rol_Permisos rp2
           JOIN Permisos d ON d.Permiso_ID = rp2.Permiso_ID
          WHERE rp2.Rol_ID = rp.Rol_ID
            AND d.Modulo = 'dashboard' AND d.Accion = 'ver')
ON CONFLICT DO NOTHING;
''',
    sqlite: r'''
INSERT OR IGNORE INTO Permisos (Modulo, Accion) VALUES
       ('reportes', 'ver'), ('reportes', 'crear'),
       ('reportes', 'editar'), ('reportes', 'eliminar');

INSERT OR IGNORE INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT rp.Rol_ID, nuevo.Permiso_ID
  FROM Rol_Permisos rp
  JOIN Permisos nuevo ON nuevo.Modulo = 'reportes' AND nuevo.Accion = 'ver'
 WHERE EXISTS (
         SELECT 1
           FROM Rol_Permisos rp2
           JOIN Permisos d ON d.Permiso_ID = rp2.Permiso_ID
          WHERE rp2.Rol_ID = rp.Rol_ID
            AND d.Modulo = 'dashboard' AND d.Accion = 'ver');
''',
  ),
]);

/// Acciones de escritura de `reportes` para el rol `ADMIN`.
///
/// La 019 siembra los cuatro permisos del módulo pero solo concede
/// `reportes.ver` (a quien ya tenía `dashboard.ver`), así que `reportes.crear`,
/// `reportes.editar` y `reportes.eliminar` se quedaban sin ningún rol: la
/// matriz de la pestaña «Roles» enseñaba a ADMIN con tres casillas vacías en
/// un solo módulo —única asimetría del sistema— y el esquema que deja esta
/// ruta de migraciones no coincidía con el de `sql/reset_ventas.sql`, que da a
/// ADMIN los 56 permisos (`CROSS JOIN Permisos`).
///
/// Se los da a ADMIN, igual que hizo la 017 con `unidades`: es el único rol
/// que tiene las cuatro acciones de los demás módulos. CAJERO y VENDEDOR se
/// quedan con `reportes.ver`, porque el informe es de solo lectura.
const Migracion _permisosReportesAdmin = Migracion(
  '020_permisos_reportes_admin',
  [
    SqlPorMotor(
      postgres: r'''
INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo = 'reportes'
   AND p.Accion IN ('crear', 'editar', 'eliminar')
WHERE r.Nombre = 'ADMIN'
ON CONFLICT DO NOTHING;
''',
      sqlite: r'''
INSERT OR IGNORE INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo = 'reportes'
   AND p.Accion IN ('crear', 'editar', 'eliminar')
WHERE r.Nombre = 'ADMIN';
''',
    ),
  ],
);

/// Unicidad solo entre filas vivas.
///
/// `roles.nombre`, `productos.codigo` y `unidades_medida.codigo` nacieron con
/// `UNIQUE` incondicional, pero el borrado de la API es **lógico**: la fila
/// oculta seguía ocupando la clave, de modo que en cuanto existía una, el
/// siguiente alta con ese nombre o código recibía `409` para siempre —es lo
/// que rompía repetir `scripts/smoke_test.ps1` (`SMOKE ROL`, `SMOKE-DUP`,
/// `BARRIL`).
///
/// Se cambia el `UNIQUE` por un índice único **parcial**
/// (`WHERE estado <> 'ELIMINADO'`): entre filas vivas la clave sigue siendo
/// única —que es lo que comprueban las rutas: `POST /roles` duplicado, código
/// de producto repetido, `codigo=KG`— y las ocultas la liberan. (No se toca
/// `facturas.orden_id`: allí la fila oculta **debe** seguir ocupando la clave,
/// como deja escrito `venta_usecases_test.dart`.)
///
/// En SQLite solo cambia `productos.codigo` y `unidades_medida.codigo`;
/// `roles.nombre` se queda estricto porque es un `UNIQUE` incrustado en la
/// columna y SQLite solo lo quita reconstruyendo la tabla, cosa imposible
/// aquí: `usuarios` y `rol_permisos` la referencian y la migración corre
/// **dentro de su transacción**, donde `PRAGMA foreign_keys` no hace efecto
/// (y bajarla haría que `DROP TABLE` borrara en cascada `rol_permisos`).
const Migracion _unicidadFilasVivas = Migracion('021_unicidad_filas_vivas', [
  SqlPorMotor(
    postgres: r'''
DROP INDEX IF EXISTS idx_productos_codigo;
CREATE UNIQUE INDEX idx_productos_codigo ON productos (codigo)
    WHERE estado <> 'ELIMINADO';

ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_nombre_key;
CREATE UNIQUE INDEX roles_nombre_activo_key ON roles (nombre)
    WHERE estado <> 'ELIMINADO';

ALTER TABLE unidades_medida DROP CONSTRAINT IF EXISTS unidades_medida_codigo_key;
CREATE UNIQUE INDEX unidades_medida_codigo_activo_key ON unidades_medida (codigo)
    WHERE estado <> 'ELIMINADO';
''',
    sqlite: r'''
DROP INDEX IF EXISTS idx_productos_codigo;
CREATE UNIQUE INDEX idx_productos_codigo ON productos (codigo)
    WHERE estado <> 'ELIMINADO';

-- `codigo` es `UNIQUE` incrustado en la columna (017): se reconstruye la
-- tabla sin esa cláusula. Nada la referencia, así que el `DROP` es seguro.
CREATE TABLE _unidades_021 (
    unidad_id           INTEGER PRIMARY KEY AUTOINCREMENT,
    codigo              VARCHAR(10) NOT NULL,
    nombre_unidad       VARCHAR(50) NOT NULL,
    tipo                VARCHAR(20) NOT NULL
                            CHECK (tipo IN ('PESO','VOLUMEN','UNIDAD')),
    decimales           SMALLINT NOT NULL DEFAULT 0
                            CHECK (decimales BETWEEN 0 AND 3),
    estado              TEXT NOT NULL DEFAULT 'ACTIVO'
                            CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO _unidades_021 (unidad_id, codigo, nombre_unidad, tipo, decimales,
                           estado, fecha_creacion, fecha_actualizacion)
    SELECT unidad_id, codigo, nombre_unidad, tipo, decimales, estado,
           fecha_creacion, fecha_actualizacion
      FROM unidades_medida;
DROP TABLE unidades_medida;
ALTER TABLE _unidades_021 RENAME TO unidades_medida;
CREATE UNIQUE INDEX unidades_medida_codigo_activo_key ON unidades_medida (codigo)
    WHERE estado <> 'ELIMINADO';
''',
  ),
]);

/// Colores: catálogo de colores y variantes de stock por producto.
///
/// Dos tablas nuevas:
///
/// * `colores` — el catálogo que llena la pestaña «Colores» (nace **vacío**,
///   como todo catálogo; la 017 solo sembró unidades por ser referenciales).
///   El nombre es único solo entre filas vivas y sobre `LOWER(nombre)`, con
///   el mismo criterio parcial de la 021: «Rojo» y «rojo» tampoco conviven
///   y el borrado lógico libera la clave para poder repetirla.
/// * `producto_variantes` — reparte el stock de un producto por color. Un
///   producto sin colores no es un caso aparte: tiene una única variante con
///   `color_id = NULL` y `nombre_color = 'Único'` («Única» es solo etiqueta
///   de UI). Dos índices únicos parciales imponen, entre filas vivas, «a lo
///   sumo una variante por color» y «a lo sumo una Único» por producto: un
///   combo repetido en el formulario da `409` y un color oculto puede volver
///   a usarse. `nombre_color` se congela al crear la variante, de modo que
///   renombrar el color **no** reescribe el histórico de ventas.
///
/// `productos.stock` sigue siendo el agregado (suma de las variantes vivas):
/// la API lo recalcula en cada alta/edición de variantes, y el backfill de
/// esta migración le da a cada producto existente su variante «Único» con el
/// stock que ya traía —guardado con `WHERE NOT EXISTS` para que repetir la
/// migración no duplique filas y para que el DDL espejado en
/// `sql/reset_ventas.sql` pueda correr antes que esta migración.
///
/// **Líneas de detalle**: `detalles_ordenes_pedidos` y `detalles_cotizaciones`
/// ganan `variante_id NOT NULL` y lo suman a su clave primaria —una misma
/// orden puede vender dos colores del mismo producto como dos líneas
/// distintas—; cada fila existente queda ligada a la primera variante de su
/// producto. En PostgreSQL la PK se cambia con `DROP CONSTRAINT` +
/// `ADD CONSTRAINT` (soltar la PK **no** quita el `NOT NULL` de
/// `producto_id`/`orden_id`, verificado en vivo); SQLite no admite alterar
/// claves, así que ambas tablas se reconstruyen —mismo criterio que la 018/
/// 021: nada las referencia, el `DROP` es seguro— y se recrean sus índices.
///
/// **Kardex**: `movimientos_stock.variante_id` es opcional y sin relleno: un
/// `NULL` es un movimiento anterior a los colores (igual que `unidad` en la
/// 016, no se backfillea) y **sin FK**, como en 017/016.
///
/// Idempotencia: la rama PostgreSQL usa `IF NOT EXISTS` en todo (también en
/// el `ADD COLUMN` de detalles, porque reset espeja estas columnas); SQLite
/// corre una sola vez por `schema_migrations` (reconstrucción, como 018/021).
const Migracion _coloresVariantes = Migracion('022_colores_variantes', [
  // --- Tablas --------------------------------------------------------------
  SqlPorMotor(
    postgres: r'''
CREATE TABLE IF NOT EXISTS colores (
    color_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR(50) NOT NULL,
    -- Hexadecimal para el chip de color de la UI (#RRGGBB); opcional.
    codigo_hex          VARCHAR(7),
    estado              estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS producto_variantes (
    variante_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id         BIGINT NOT NULL
                            REFERENCES productos(producto_id) ON DELETE RESTRICT,
    -- NULL = variante «Único» (producto vendido sin color).
    color_id            BIGINT
                            REFERENCES colores(color_id) ON DELETE RESTRICT,
    -- Nombre congelado al crear la variante: renombrar el color no cambia
    -- el histórico de ventas.
    nombre_color        VARCHAR(50) NOT NULL,
    stock               NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (stock >= 0),
    estado              estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
    sqlite: r'''
CREATE TABLE IF NOT EXISTS colores (
    color_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre              VARCHAR(50) NOT NULL,
    -- Hexadecimal para el chip de color de la UI (#RRGGBB); opcional.
    codigo_hex          VARCHAR(7),
    estado              TEXT NOT NULL DEFAULT 'ACTIVO'
                          CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS producto_variantes (
    variante_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    producto_id         BIGINT NOT NULL
                          REFERENCES productos(producto_id) ON DELETE RESTRICT,
    color_id            BIGINT
                          REFERENCES colores(color_id) ON DELETE RESTRICT,
    nombre_color        VARCHAR(50) NOT NULL,
    stock               NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (stock >= 0),
    estado              TEXT NOT NULL DEFAULT 'ACTIVO'
                          CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
  ),
  // --- Unicidad entre filas vivas + backfill de «Único» --------------------
  // Los tres índices únicos y el backfill son sentencias portables; la
  // comprobación de unicidad es de fila viva porque el borrado es lógico.
  SqlCompartido(r'''
CREATE UNIQUE INDEX IF NOT EXISTS colores_nombre_activo_key
    ON colores (LOWER(nombre)) WHERE estado <> 'ELIMINADO';

CREATE UNIQUE INDEX IF NOT EXISTS producto_variantes_producto_color_key
    ON producto_variantes (producto_id, color_id)
    WHERE color_id IS NOT NULL AND estado <> 'ELIMINADO';

CREATE UNIQUE INDEX IF NOT EXISTS producto_variantes_producto_unico_key
    ON producto_variantes (producto_id)
    WHERE color_id IS NULL AND estado <> 'ELIMINADO';

-- Lecturas por producto (cargas por lote y "reusar" una variante oculta):
-- los dos índices parciales de arriba no sirven para un `producto_id` a
-- secas, y PostgreSQL exige un índice llano para ese plan.
CREATE INDEX IF NOT EXISTS idx_variantes_producto
    ON producto_variantes (producto_id);

INSERT INTO producto_variantes (producto_id, color_id, nombre_color, stock)
SELECT p.producto_id, NULL, 'Único', COALESCE(p.stock, 0)
  FROM productos p
 WHERE NOT EXISTS (
       SELECT 1 FROM producto_variantes v
        WHERE v.producto_id = p.producto_id
     );
'''),
  // --- Las líneas de detalle nombran la variante ---------------------------
  SqlPorMotor(
    postgres: r'''
ALTER TABLE detalles_ordenes_pedidos
    ADD COLUMN IF NOT EXISTS variante_id BIGINT
    REFERENCES producto_variantes(variante_id);

UPDATE detalles_ordenes_pedidos d
   SET variante_id = (
       SELECT v.variante_id
         FROM producto_variantes v
        WHERE v.producto_id = d.producto_id
        ORDER BY v.variante_id
        LIMIT 1
   )
 WHERE d.variante_id IS NULL;

ALTER TABLE detalles_ordenes_pedidos
    ALTER COLUMN variante_id SET NOT NULL;

-- Cambio de PK: soltarla no quita el NOT NULL de producto_id/orden_id
-- (verificado en vivo con BEGIN/ROLLBACK), así que basta el DROP+ADD.
ALTER TABLE detalles_ordenes_pedidos
    DROP CONSTRAINT IF EXISTS detalles_ordenes_pedidos_pkey;
ALTER TABLE detalles_ordenes_pedidos
    ADD CONSTRAINT detalles_ordenes_pedidos_pkey
    PRIMARY KEY (producto_id, orden_id, variante_id);

ALTER TABLE detalles_cotizaciones
    ADD COLUMN IF NOT EXISTS variante_id BIGINT
    REFERENCES producto_variantes(variante_id);

UPDATE detalles_cotizaciones d
   SET variante_id = (
       SELECT v.variante_id
         FROM producto_variantes v
        WHERE v.producto_id = d.producto_id
        ORDER BY v.variante_id
        LIMIT 1
   )
 WHERE d.variante_id IS NULL;

ALTER TABLE detalles_cotizaciones
    ALTER COLUMN variante_id SET NOT NULL;

ALTER TABLE detalles_cotizaciones
    DROP CONSTRAINT IF EXISTS detalles_cotizaciones_pkey;
ALTER TABLE detalles_cotizaciones
    ADD CONSTRAINT detalles_cotizaciones_pkey
    PRIMARY KEY (producto_id, cotizacion_id, variante_id);
''',
    sqlite: r'''
-- SQLite no admite alterar una clave primaria: se reconstruyen las dos
-- tablas (mismo criterio que la 018/021 — nada las referencia, el DROP es
-- seguro, no hay vistas ni triggers encima) conservando columnas, FKs y
-- CHECKs, con la variante ya en la clave.
CREATE TABLE _detalles_orden_022 (
    Producto_ID BIGINT REFERENCES productos(producto_id) ON DELETE RESTRICT,
    Orden_ID BIGINT REFERENCES ordenes_pedidos(orden_id) ON DELETE CASCADE,
    Nombre_Producto VARCHAR(150) NOT NULL,
    Cantidad NUMERIC(12, 3) NOT NULL CHECK (Cantidad > 0),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Monto_Total NUMERIC(10, 2) NOT NULL CHECK (Monto_Total >= 0),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO'
             CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    costo_unitario NUMERIC(10, 2),
    variante_id BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    PRIMARY KEY (Producto_ID, Orden_ID, variante_id)
);

INSERT INTO _detalles_orden_022
    (Producto_ID, Orden_ID, Nombre_Producto, Cantidad, Precio_Venta,
     Monto_Total, Estado, unidad, costo_unitario, variante_id)
SELECT d.Producto_ID, d.Orden_ID, d.Nombre_Producto, d.Cantidad,
       d.Precio_Venta, d.Monto_Total, d.Estado, d.unidad, d.costo_unitario,
       (SELECT v.variante_id
          FROM producto_variantes v
         WHERE v.producto_id = d.Producto_ID
         ORDER BY v.variante_id
         LIMIT 1)
  FROM Detalles_Ordenes_Pedidos d;

DROP TABLE Detalles_Ordenes_Pedidos;
ALTER TABLE _detalles_orden_022 RENAME TO Detalles_Ordenes_Pedidos;
CREATE INDEX IF NOT EXISTS idx_detalles_orden    ON Detalles_Ordenes_Pedidos (Orden_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_producto ON Detalles_Ordenes_Pedidos (Producto_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_estado   ON Detalles_Ordenes_Pedidos (Estado);

CREATE TABLE _detalles_cot_022 (
    producto_id BIGINT REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cotizacion_id BIGINT REFERENCES cotizaciones(cotizacion_id) ON DELETE CASCADE,
    nombre_producto VARCHAR(150) NOT NULL,
    imagen VARCHAR(500),
    cantidad NUMERIC(12, 3) NOT NULL CHECK (cantidad > 0),
    precio_venta NUMERIC(10, 2) NOT NULL CHECK (precio_venta >= 0),
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    variante_id BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    PRIMARY KEY (producto_id, cotizacion_id, variante_id)
);

INSERT INTO _detalles_cot_022
    (producto_id, cotizacion_id, nombre_producto, imagen, cantidad,
     precio_venta, monto_total, unidad, variante_id)
SELECT d.producto_id, d.cotizacion_id, d.nombre_producto, d.imagen,
       d.cantidad, d.precio_venta, d.monto_total, d.unidad,
       (SELECT v.variante_id
          FROM producto_variantes v
         WHERE v.producto_id = d.producto_id
         ORDER BY v.variante_id
         LIMIT 1)
  FROM detalles_cotizaciones d;

DROP TABLE detalles_cotizaciones;
ALTER TABLE _detalles_cot_022 RENAME TO detalles_cotizaciones;
CREATE INDEX IF NOT EXISTS idx_detalles_cotizaciones_cot
    ON detalles_cotizaciones (cotizacion_id);
''',
  ),
  // --- Kardex: columna opcional, sin relleno y sin FK ----------------------
  SqlPorMotor(
    postgres: r'''
ALTER TABLE movimientos_stock
    ADD COLUMN IF NOT EXISTS variante_id BIGINT;
''',
    sqlite: r'''
ALTER TABLE movimientos_stock ADD COLUMN variante_id BIGINT;
''',
  ),
]);

/// Marcas de producto (catálogo de texto) y garantía en meses.
///
/// * `marcas` — catálogo que llena la pestaña «Marcas» de la página
///   Categorías (nace **vacío**, igual que colores); nombre único entre
///   filas vivas vía índice parcial, borrado lógico con `ELIMINADO`.
/// * `productos.marca_id` — nullable: el producto puede llevar marca o no.
///   Solo texto: columna visible en la tabla de productos, filtro del
///   listado, búsqueda libre y — **únicamente en el Recibo 1** — una línea
///   del recibo de la orden (la Boleta 2 no la imprime).
/// * `productos.garantia_meses` — nullable; los meses se validan en
///   `ensureGarantiaMeses` (1..120) y la UI los ofrece como desplegable de
///   presets. Se muestra solo en la ficha «ver toda la información».
///
/// Idempotencia: rama PostgreSQL con `IF NOT EXISTS` (reset espeja estas
/// columnas); SQLite corre una sola vez por `schema_migrations` — el
/// `ADD COLUMN` con `REFERENCES` es válido porque la columna nace sin
/// `DEFAULT` (NULL implícito), como exige SQLite.
const Migracion _marcasGarantia = Migracion('023_marcas_garantia', [
  // --- Tabla del catálogo --------------------------------------------------
  SqlPorMotor(
    postgres: r'''
CREATE TABLE IF NOT EXISTS marcas (
    marca_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR(50) NOT NULL,
    estado              estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
    sqlite: r'''
CREATE TABLE IF NOT EXISTS marcas (
    marca_id            INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre              VARCHAR(50) NOT NULL,
    estado              TEXT NOT NULL DEFAULT 'ACTIVO'
                          CHECK (estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    fecha_creacion      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
''',
  ),
  // --- Columnas del producto ------------------------------------------------
  SqlPorMotor(
    postgres: r'''
ALTER TABLE productos ADD COLUMN IF NOT EXISTS marca_id BIGINT
    REFERENCES marcas(marca_id);

ALTER TABLE productos ADD COLUMN IF NOT EXISTS garantia_meses SMALLINT;
''',
    sqlite: r'''
ALTER TABLE productos ADD COLUMN marca_id BIGINT REFERENCES marcas(marca_id);

ALTER TABLE productos ADD COLUMN garantia_meses SMALLINT;
''',
  ),
  // --- Unicidad entre filas vivas + índice de filtro ------------------------
  SqlCompartido(r'''
CREATE UNIQUE INDEX IF NOT EXISTS marcas_nombre_activo_key
    ON marcas (LOWER(nombre)) WHERE estado <> 'ELIMINADO';

CREATE INDEX IF NOT EXISTS idx_productos_marca ON productos (marca_id);
'''),
]);

/// Lista única de migraciones futuras (ambos motores).
///
/// Las 15 migraciones originales de PostgreSQL viven en `migrations.dart`
/// y el esquema base de SQLite en `migrations_sqlite.dart`; esta lista es
/// para TODO lo que se cambie a partir de ahora.
const List<Migracion> migracionesCompartidas = [
  _ventasFraccionadas,
  _unidadesMedida,
  _productoDescripcion,
  _permisoReportes,
  _permisosReportesAdmin,
  _unicidadFilasVivas,
  _coloresVariantes,
  _marcasGarantia,
];
