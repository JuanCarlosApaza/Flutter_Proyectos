-- ============================================================================
-- SCRIPT DE RECREEACIÓN COMPLETA DE LA BD (DESTRUCTIVO)
--
-- ⚠️  USO MANUAL / DESARROLLO: borra todas las tablas y tipos y los vuelve
--     a crear. NO se ejecuta como migración de la aplicación.
--
-- Uso:
--   psql -U postgres -d ventarropa -f sql/reset_ventas.sql
--
-- La migración real (que sí corre sola al arrancar el servidor) está en
-- lib/src/data/database/migrations.dart (001-015) y en
-- lib/src/data/database/migraciones_compartidas.dart (016-020, fuente
-- única compartida con SQLite) y solo CREA la estructura.
--
-- Este script recrea el esquema **tal como queda tras las migraciones
-- compartidas** (016-020) y además siembra `schema_migrations` con todas
-- las migraciones marcadas como aplicadas: sin ese registro el servidor, al
-- arrancar, intentaría volver a correrlas sobre un esquema ya creado y
-- abortaría con `migration_failed`.
-- ============================================================================

-- ============================================================================
-- 1. LIMPIEZA PREVIA (Opcional, elimina estructuras previas si existen)
-- ============================================================================
DROP TABLE IF EXISTS schema_migrations CASCADE;
DROP TABLE IF EXISTS ajustes CASCADE;
DROP TABLE IF EXISTS auditoria CASCADE;
DROP TABLE IF EXISTS sesiones CASCADE;
DROP TABLE IF EXISTS pagos CASCADE;
DROP TABLE IF EXISTS movimientos_stock CASCADE;
DROP TABLE IF EXISTS Rol_Permisos CASCADE;
DROP TABLE IF EXISTS Permisos CASCADE;
DROP TABLE IF EXISTS Roles CASCADE;
DROP TABLE IF EXISTS detalles_cotizaciones CASCADE;
DROP TABLE IF EXISTS cotizaciones CASCADE;
DROP TABLE IF EXISTS Detalles_Ordenes_Pedidos CASCADE;
DROP TABLE IF EXISTS producto_variantes CASCADE;
DROP TABLE IF EXISTS Facturas CASCADE;
DROP TABLE IF EXISTS Ordenes_Pedidos CASCADE;
DROP TABLE IF EXISTS Productos CASCADE;
DROP TABLE IF EXISTS Usuarios CASCADE;
DROP TABLE IF EXISTS Empleados CASCADE;
DROP TABLE IF EXISTS Proveedores CASCADE;
DROP TABLE IF EXISTS Clientes CASCADE;
DROP TABLE IF EXISTS tallas CASCADE;
DROP TABLE IF EXISTS colores CASCADE;
-- Heredadas de la versión de farmacia: ya no se crean (migración 017_ropa),
-- se dejan en la limpieza para que un recreate viejo quede del todo vacío.
DROP TABLE IF EXISTS Presentaciones CASCADE;
DROP TABLE IF EXISTS Categorias CASCADE;

DROP TYPE IF EXISTS estado_general CASCADE;
DROP TYPE IF EXISTS estado_empleado CASCADE;
DROP TYPE IF EXISTS estado_producto CASCADE;
DROP TYPE IF EXISTS estado_orden CASCADE;
DROP TYPE IF EXISTS estado_factura CASCADE;
DROP TYPE IF EXISTS estado_cotizacion CASCADE;

DROP FUNCTION IF EXISTS actualizar_fecha_modificacion CASCADE;


-- ============================================================================
-- 2. TIPOS ENUMERADOS PARA ESTADOS DE NEGOCIO
--   `ELIMINADO` = registro oculto por borrado lógico (nunca se borra la fila;
--   lo escribe la API en el `DELETE` y lo excluyen los listados).
-- ============================================================================
CREATE TYPE estado_general AS ENUM ('ACTIVO', 'INACTIVO', 'BLOQUEADO', 'ELIMINADO');
CREATE TYPE estado_empleado AS ENUM ('ACTIVO', 'VACACIONES', 'LICENCIA', 'INACTIVO', 'ELIMINADO');
CREATE TYPE estado_producto AS ENUM ('DISPONIBLE', 'AGOTADO', 'DESCONTINUADO', 'ELIMINADO');
CREATE TYPE estado_orden AS ENUM ('PENDIENTE', 'PAGADO', 'CANCELADO', 'DEVUELTO', 'ELIMINADO');
CREATE TYPE estado_factura AS ENUM ('EMITIDA', 'ANULADA', 'ELIMINADO');
CREATE TYPE estado_cotizacion AS ENUM ('VIGENTE', 'ACEPTADA', 'RECHAZADA', 'ELIMINADO');


-- ============================================================================
-- 3. FUNCIÓN Y TRIGGER PARA AUDITORÍA AUTOMÁTICA DE FECHA_ACTUALIZACION
-- ============================================================================
CREATE OR REPLACE FUNCTION actualizar_fecha_modificacion()
RETURNS TRIGGER AS $$
BEGIN
    NEW.Fecha_Actualizacion = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 4. CATÁLOGOS DE ROPA (migración 017_ropa)
--     `tallas` y `colores` son catálogos propios (se gestionan desde la
--     pestaña «Tallas»/«Colores» del módulo Categorías); las variantes de
--     cada prenda viven en la sección 6b, con su propio stock.
--     («Presentaciones» era el catálogo de farmacia: fuera).
-- ============================================================================
CREATE TABLE Categorias (
    Categoria_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Categoria VARCHAR(100) NOT NULL,
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE marcas (
    marca_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_marca VARCHAR(100) NOT NULL,
    estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE tallas (
    talla_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL UNIQUE,
    orden INT NOT NULL DEFAULT 0,
    estado estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE colores (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE,
    codigo_hex VARCHAR(7),
    estado estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Sin semillas de tallas/colores: los catálogos arrancan vacíos y cada
-- tienda los llena desde la propia app (migraciones 017_ropa + 018).


-- ============================================================================
-- 5. PERSONAS Y ENTIDADES
-- ============================================================================
CREATE TABLE Clientes (
    Cliente_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Cliente VARCHAR(150) NOT NULL,
    Apellido VARCHAR(100),
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Genero CHAR(1),
    CI VARCHAR(15) UNIQUE,
    Telefono VARCHAR(20),
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Proveedores (
    Proveedor_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Proveedor VARCHAR(150) NOT NULL,
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Telefono VARCHAR(20),
    Email VARCHAR(150),
    NIT VARCHAR(20),
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Empleados (
    Empleado_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Empleado VARCHAR(150) NOT NULL,
    Apellido VARCHAR(100),
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Edad INT CHECK (Edad >= 18),
    Telefono VARCHAR(20),
    Estado estado_empleado DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);


-- ============================================================================
-- 6. USUARIOS, ROLES Y PRODUCTOS
-- ============================================================================
-- Roles y permisos (RBAC, migración 009_roles_permisos): la única fuente de
-- verdad de los niveles de acceso. `Permisos` es módulo × acción de los 11
-- módulos de la app; `Rol_Permisos` dice qué puede cada rol.
CREATE TABLE Roles (
    Rol_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre VARCHAR(50) UNIQUE NOT NULL,
    Descripcion VARCHAR(255),
    Es_Sistema BOOLEAN NOT NULL DEFAULT FALSE,
    Estado estado_general NOT NULL DEFAULT 'ACTIVO',
    Creado_En TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Actualizado_En TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Permisos (
    Permiso_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Modulo VARCHAR(50) NOT NULL,
    Accion VARCHAR(20) NOT NULL
        CHECK (Accion IN ('ver', 'crear', 'editar', 'eliminar')),
    UNIQUE (Modulo, Accion)
);

CREATE TABLE Rol_Permisos (
    Rol_ID BIGINT NOT NULL REFERENCES Roles(Rol_ID) ON DELETE CASCADE,
    Permiso_ID BIGINT NOT NULL REFERENCES Permisos(Permiso_ID) ON DELETE CASCADE,
    PRIMARY KEY (Rol_ID, Permiso_ID)
);

-- Semilla de permisos: 13 módulos de la app × 4 acciones.
INSERT INTO Permisos (Modulo, Accion)
SELECT m.Modulo, a.Accion
FROM (VALUES ('dashboard'), ('productos'), ('catalogo'), ('clientes'),
             ('ventas'), ('cotizaciones'), ('categorias'), ('proveedores'),
             ('empleados'), ('usuarios'), ('auditoria'), ('reportes'),
             ('ajustes')) AS m(Modulo)
CROSS JOIN (VALUES ('ver'), ('crear'), ('editar'), ('eliminar')) AS a(Accion);

INSERT INTO Roles (Nombre, Descripcion, Es_Sistema) VALUES
    ('ADMIN',    'Acceso total al sistema', TRUE),
    ('CAJERO',   'Atención de mostrador',   TRUE),
    ('VENDEDOR', 'Solo ventas y catálogo',  TRUE);

-- ADMIN: los 52 permisos.
INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID FROM Roles r CROSS JOIN Permisos p
WHERE r.Nombre = 'ADMIN';

-- CAJERO: solo `ver`/`crear` (editar y eliminar quedan para rangos altos).
INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo || '.' || p.Accion IN (
        'dashboard.ver', 'productos.ver', 'catalogo.ver', 'clientes.ver',
        'clientes.crear', 'ventas.ver', 'ventas.crear', 'cotizaciones.ver',
        'cotizaciones.crear', 'categorias.ver', 'proveedores.ver',
        'ajustes.ver')
WHERE r.Nombre = 'CAJERO';

-- VENDEDOR: estrictamente ventas y catálogo (+ clientes para facturar).
INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo || '.' || p.Accion IN (
        'ventas.ver', 'ventas.crear', 'catalogo.ver', 'catalogo.crear',
        'clientes.ver')
WHERE r.Nombre = 'VENDEDOR';

CREATE TABLE Usuarios (
    Usuario_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Empleado_ID BIGINT UNIQUE REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Rol_ID BIGINT NOT NULL REFERENCES Roles(Rol_ID),
    Nombre_Usuario VARCHAR(50) UNIQUE NOT NULL,
    Contrasena VARCHAR(255) NOT NULL,
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Sesiones Bearer (migración 003_sesiones): el token es aleatorio de 64 hex
-- y caduca a los 30 días con «recuerdame» y a las 24 h sin él; el `DELETE`
-- de `POST /auth/logout` borra la fila y deja el token inservible.
CREATE TABLE sesiones (
    token VARCHAR(64) PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES Usuarios(Usuario_ID) ON DELETE CASCADE,
    creada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en TIMESTAMPTZ NOT NULL
);

CREATE TABLE Productos (
    Producto_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Código interno / de barras. Índice UNIQUE aparte (migración 016), de
    -- modo que las filas existentes pueden quedarse en NULL.
    Codigo VARCHAR(60),
    Nombre_Producto VARCHAR(150) NOT NULL,
    Imagen VARCHAR(500),
    -- Descripción libre de la ficha (migración 023): opcional, sin tope
    -- de la BD (TEXT) — el tope de longitud lo pone la API.
    Descripcion TEXT,
    -- Venta siempre por unidad entera (migración 017_ropa): fuera las
    -- unidades de farmacia (KG, LT, BLISTER...). El stock fraccionado
    -- (migración 016) se conserva por compatibilidad con las filas previas.
    Unidad VARCHAR(10) NOT NULL DEFAULT 'UN'
        CHECK (Unidad IN ('UN')),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Precio_Compra NUMERIC(10, 2) CHECK (Precio_Compra >= 0),
    Precio_Rebaja NUMERIC(10, 2) CHECK (Precio_Rebaja >= 0),
    -- Agregado de las variantes de la prenda: la API lo actualiza en la
    -- misma transacción que cualquier cambio de variante.
    Stock NUMERIC(12, 3) DEFAULT 0 CHECK (Stock >= 0),
    -- NULL = usar el ajuste global `stockMinimo` del dashboard.
    Stock_Minimo NUMERIC(12, 3) CHECK (Stock_Minimo >= 0),
    -- Guarda optimista: cada UPDATE la incrementa y exige la versionLeida
    -- del cliente (migración 007_productos_version).
    Version INT NOT NULL DEFAULT 0,
    Categoria_ID BIGINT REFERENCES Categorias(Categoria_ID) ON DELETE RESTRICT,
    -- Marca opcional de la prenda (migración 024_marcas): NULL = sin marca.
    Marca_ID BIGINT REFERENCES marcas(marca_id),
    Proveedor_ID BIGINT REFERENCES Proveedores(Proveedor_ID) ON DELETE RESTRICT,
    -- Sin `fecha_vencimiento` ni `presentacion_id`: eran campos de farmacia
    -- y la migración 017_ropa los elimina.
    Estado estado_producto DEFAULT 'DISPONIBLE' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_productos_codigo ON Productos (Codigo);
CREATE INDEX IF NOT EXISTS idx_productos_unidad ON Productos (Unidad);

-- ============================================================================
-- 6b. VARIANTES DE PRENDA (migración 017_ropa)
--     Una fila por combinación prenda + talla + color, con su propio stock:
--     es lo que se vende (el detalle de órdenes y cotizaciones referencia a
--     `variante_id`, no solo al producto). `productos.stock` es el agregado.
-- ============================================================================
CREATE TABLE producto_variantes (
    variante_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id BIGINT NOT NULL
                 REFERENCES Productos(Producto_ID) ON DELETE CASCADE,
    talla_id BIGINT NOT NULL REFERENCES tallas(talla_id),
    color_id BIGINT NOT NULL REFERENCES colores(color_id),
    stock NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (stock >= 0),
    -- Un único precio por producto: no hay precio propio por combinación
    -- (la 019 lo creó y la 020 lo retiró).
    codigo VARCHAR(60),
    estado estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (producto_id, talla_id, color_id)
);


-- ============================================================================
-- 7. ORDENES DE PEDIDO, FACTURAS Y DETALLES
-- ============================================================================
CREATE TABLE Ordenes_Pedidos (
    Orden_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Fecha_Orden TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Cliente_ID BIGINT REFERENCES Clientes(Cliente_ID) ON DELETE RESTRICT,
    Nombre_Cliente VARCHAR(150),
    Empleado_ID BIGINT REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Total NUMERIC(10, 2) DEFAULT 0 CHECK (Total >= 0),
    -- Rebaja hecha al cobrar; el IVA (14.94%) solo entra si `Factura` es
    -- TRUE, y los pagos cuadran contra `Total − Rebaja + IVA`.
    Rebaja NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (Rebaja >= 0),
    Factura BOOLEAN NOT NULL DEFAULT FALSE,
    Estado estado_orden DEFAULT 'PENDIENTE' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Desglose de pagos de la venta (pago mixto: efectivo + QR, etc.).
CREATE TABLE pagos (
    Pago_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Orden_ID BIGINT NOT NULL REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
    Metodo_Pago VARCHAR(50) NOT NULL,
    Monto NUMERIC(10, 2) NOT NULL CHECK (Monto > 0),
    Referencia VARCHAR(100),
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Facturas (
    Factura_Numero BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Fecha_Factura TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Empleado_ID BIGINT REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Cliente_ID BIGINT REFERENCES Clientes(Cliente_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT UNIQUE REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE RESTRICT,
    Subtotal NUMERIC(10, 2) NOT NULL CHECK (Subtotal >= 0),
    Rebaja NUMERIC(10, 2) DEFAULT 0 CHECK (Rebaja >= 0),
    Iva NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (Iva >= 0),
    Estado estado_factura DEFAULT 'EMITIDA' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Detalles_Ordenes_Pedidos (
    Producto_ID BIGINT NOT NULL REFERENCES Productos(Producto_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
    -- Variante vendida (talla + color): la PK es (variante, orden) para que
    -- la misma prenda pueda entrar varias veces en un documento, cada talla
    -- en su línea (migración 017_ropa).
    Variante_ID BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    Nombre_Producto VARCHAR(150) NOT NULL,
    -- Unidad congelada al vender (migración 016): el documento sigue
    -- leyéndose bien aunque el producto cambie de unidad después.
    Unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    -- Fraccionada (migración 016; era INT): 1.450 KG en vez de 1 KG.
    Cantidad NUMERIC(12, 3) NOT NULL CHECK (Cantidad > 0),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    -- Costo al momento de vender (habilita la utilidad por línea). Las
    -- líneas antiguas quedan en NULL: backfillear con el precio_compra
    -- actual mentiría sobre el histórico.
    Costo_Unitario NUMERIC(10, 2),
    Monto_Total NUMERIC(10, 2) NOT NULL CHECK (Monto_Total >= 0),
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    PRIMARY KEY (Variante_ID, Orden_ID)
);


-- ============================================================================
-- 7b. KARDEX DE STOCK (migración 016_ventas_fraccionadas)
--     Quién movió cuánto stock y por qué. `cantidad` es firmada (positiva
--     = entra, negativa = sale) y `stock_resultante` permite saber el stock
--     en cualquier fecha sin recalcular. El actor de cada movimiento ya lo
--     registra `auditoria`, por eso aquí no se guarda usuario.
-- ============================================================================
CREATE TABLE movimientos_stock (
    movimiento_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id BIGINT NOT NULL REFERENCES productos(producto_id) ON DELETE RESTRICT,
    -- Kardex por variante (migración 017_ropa): al ser opcional, un
    -- movimiento previo a la ropa queda registrado aunque no haya talla.
    variante_id BIGINT REFERENCES producto_variantes(variante_id) ON DELETE SET NULL,
    cantidad NUMERIC(12, 3) NOT NULL CHECK (cantidad <> 0),
    motivo VARCHAR(20) NOT NULL CHECK (motivo IN
        ('VENTA','DEVOLUCION','COMPRA','AJUSTE','MERMA','INICIAL')),
    stock_resultante NUMERIC(12, 3) NOT NULL CHECK (stock_resultante >= 0),
    orden_id BIGINT REFERENCES ordenes_pedidos(orden_id) ON DELETE SET NULL,
    notas VARCHAR(255),
    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_movimientos_producto
    ON movimientos_stock (producto_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_movimientos_orden ON movimientos_stock (orden_id);
CREATE INDEX IF NOT EXISTS idx_movimientos_fecha ON movimientos_stock (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_movimientos_motivo ON movimientos_stock (motivo);
CREATE INDEX IF NOT EXISTS idx_movimientos_variante ON movimientos_stock (variante_id);


-- ============================================================================
-- 8. AJUSTES GLOBALES (clave/valor)
--    Mismo contenido que la migración 005_ajustes: una fila por ajuste que
--    personaliza el sistema (vendedor por defecto, tipo de pago, página
--    inicial, filas por página, avisos del dashboard). No referencia a
--    ninguna otra tabla: añadirla no toca datos existentes.
-- ============================================================================
CREATE TABLE ajustes (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clave VARCHAR(100) UNIQUE NOT NULL,
    valor VARCHAR(500) NOT NULL DEFAULT '',
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);


-- ============================================================================
-- 9. TRIGGERS DE ACTUALIZACIÓN DE FECHAS DE AUDITORÍA
-- ============================================================================
CREATE TRIGGER trg_actualizar_categorias BEFORE UPDATE ON Categorias FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_marcas BEFORE UPDATE ON marcas FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_tallas BEFORE UPDATE ON tallas FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_colores BEFORE UPDATE ON colores FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_variantes BEFORE UPDATE ON producto_variantes FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_clientes BEFORE UPDATE ON Clientes FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_proveedores BEFORE UPDATE ON Proveedores FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_empleados BEFORE UPDATE ON Empleados FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_usuarios BEFORE UPDATE ON Usuarios FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_roles BEFORE UPDATE ON Roles FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_productos BEFORE UPDATE ON Productos FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_ordenes BEFORE UPDATE ON Ordenes_Pedidos FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_facturas BEFORE UPDATE ON Facturas FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_ajustes BEFORE UPDATE ON ajustes FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_pagos BEFORE UPDATE ON pagos FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();

-- ============================================================================
-- 10. ÍNDICES DE RENDIMIENTO
--    Mismo contenido que la migración 004_indices_rendimiento: sin ellos los
--    listados (catálogo, ventas, dashboard) recorren las tablas enteras.
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_productos_categoria     ON Productos (Categoria_ID);
CREATE INDEX IF NOT EXISTS idx_productos_estado        ON Productos (Estado);
CREATE INDEX IF NOT EXISTS idx_productos_stock         ON Productos (Stock);
CREATE INDEX IF NOT EXISTS idx_productos_nombre        ON Productos (Nombre_Producto);
CREATE INDEX IF NOT EXISTS idx_productos_proveedor     ON Productos (Proveedor_ID);
CREATE INDEX IF NOT EXISTS idx_productos_marca         ON Productos (Marca_ID);
-- Sin `idx_productos_presentacion` ni `idx_productos_vencimiento`: las
-- columnas dejaron de existir con la migración 017_ropa.

CREATE INDEX IF NOT EXISTS idx_variantes_producto      ON producto_variantes (producto_id);
CREATE INDEX IF NOT EXISTS idx_variantes_talla         ON producto_variantes (talla_id);
CREATE INDEX IF NOT EXISTS idx_variantes_color         ON producto_variantes (color_id);

CREATE INDEX IF NOT EXISTS idx_sesiones_usuario        ON sesiones (usuario_id);
CREATE INDEX IF NOT EXISTS idx_sesiones_expira         ON sesiones (expira_en);

CREATE INDEX IF NOT EXISTS idx_ordenes_cliente   ON Ordenes_Pedidos (Cliente_ID);
CREATE INDEX IF NOT EXISTS idx_ordenes_empleado  ON Ordenes_Pedidos (Empleado_ID);
CREATE INDEX IF NOT EXISTS idx_ordenes_fecha     ON Ordenes_Pedidos (Fecha_Orden);
CREATE INDEX IF NOT EXISTS idx_ordenes_estado    ON Ordenes_Pedidos (Estado);

CREATE INDEX IF NOT EXISTS idx_facturas_empleado  ON Facturas (Empleado_ID);
CREATE INDEX IF NOT EXISTS idx_facturas_cliente   ON Facturas (Cliente_ID);
CREATE INDEX IF NOT EXISTS idx_facturas_fecha     ON Facturas (Fecha_Factura);
CREATE INDEX IF NOT EXISTS idx_facturas_estado    ON Facturas (Estado);

CREATE INDEX IF NOT EXISTS idx_detalles_orden    ON Detalles_Ordenes_Pedidos (Orden_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_producto ON Detalles_Ordenes_Pedidos (Producto_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_estado   ON Detalles_Ordenes_Pedidos (Estado);

CREATE INDEX IF NOT EXISTS idx_pagos_orden       ON pagos (Orden_ID);

CREATE INDEX IF NOT EXISTS idx_clientes_estado      ON Clientes (Estado);
CREATE INDEX IF NOT EXISTS idx_proveedores_estado   ON Proveedores (Estado);
CREATE INDEX IF NOT EXISTS idx_empleados_estado     ON Empleados (Estado);
CREATE INDEX IF NOT EXISTS idx_usuarios_estado      ON Usuarios (Estado);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol         ON Usuarios (Rol_ID);
CREATE INDEX IF NOT EXISTS idx_rol_permisos_rol     ON Rol_Permisos (Rol_ID);

-- ============================================================================
-- 11. COTIZACIONES (migración 008_cotizaciones)
--     Propuestas de precio: quién la creó (empleado), para quién (cliente) y
--     sus líneas con el precio vigente. No toca stock ni lleva pagos.
-- ============================================================================
CREATE TABLE cotizaciones (
    cotizacion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id BIGINT REFERENCES clientes(cliente_id) ON DELETE RESTRICT,
    nombre_cliente VARCHAR(150),
    empleado_id BIGINT REFERENCES empleados(empleado_id) ON DELETE RESTRICT,
    fecha_cotizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total NUMERIC(10, 2) DEFAULT 0 CHECK (total >= 0),
    estado estado_cotizacion DEFAULT 'VIGENTE' NOT NULL,
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE detalles_cotizaciones (
    producto_id BIGINT NOT NULL REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cotizacion_id BIGINT REFERENCES cotizaciones(cotizacion_id) ON DELETE CASCADE,
    -- Mismo criterio que el detalle de órdenes: la PK es (variante, documento).
    variante_id BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    nombre_producto VARCHAR(150) NOT NULL,
    -- La imagen se congela al cotizar, igual que el precio.
    imagen VARCHAR(500),
    unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    -- Fraccionada como en las órdenes (comparten `ItemOrden`, migración 016).
    cantidad NUMERIC(12, 3) NOT NULL CHECK (cantidad > 0),
    precio_venta NUMERIC(10, 2) NOT NULL CHECK (precio_venta >= 0),
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    PRIMARY KEY (variante_id, cotizacion_id)
);

CREATE INDEX IF NOT EXISTS idx_cotizaciones_estado ON cotizaciones (estado);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_cliente ON cotizaciones (cliente_id);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_empleado ON cotizaciones (empleado_id);
CREATE INDEX IF NOT EXISTS idx_detalles_cotizaciones_cot ON detalles_cotizaciones (cotizacion_id);

-- ============================================================================
-- 12. AUDITORÍA DE CAMBIOS (migración 010_auditoria)
--     Quién hizo qué, cuándo, desde dónde y con qué resultado. Instantáneas
--     de usuario/rol sin FK (el registro sobrevive al borrado de cuentas);
--     `detalles` solo lleva detalle explícito (jamás contraseñas/tokens).
-- ============================================================================
CREATE TABLE auditoria (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_id BIGINT,
    nombre_usuario VARCHAR(50),
    rol VARCHAR(50),
    accion VARCHAR(40) NOT NULL,
    exitoso BOOLEAN NOT NULL DEFAULT TRUE,
    codigo_error VARCHAR(50),
    entidad VARCHAR(50),
    entidad_id BIGINT,
    resumen TEXT NOT NULL,
    detalles JSONB,
    ip VARCHAR(45)
);

CREATE INDEX IF NOT EXISTS idx_auditoria_fecha ON auditoria (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_auditoria_usuario ON auditoria (nombre_usuario);
CREATE INDEX IF NOT EXISTS idx_auditoria_entidad ON auditoria (entidad);

CREATE TRIGGER trg_actualizar_cotizaciones BEFORE UPDATE ON cotizaciones
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();

-- ============================================================================
-- 13. REGISTRO DE MIGRACIONES APLICADAS
--     Mismo contenido que crea el `Migrator` al arrancar, pero **sembrado**-- con las 22 migraciones ya aplicadas: este script deja el esquema igual
--     que la base viva, así que volver a correrlas daría error y el servidor
--     no arrancaría (`migration_failed`).
-- ============================================================================
CREATE TABLE IF NOT EXISTS schema_migrations (
    name       TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO schema_migrations (name) VALUES
    ('001_esquema_farmacia'),
    ('002_borrado_logico'),
    ('003_sesiones'),
    ('004_indices_rendimiento'),
    ('005_ajustes'),
    ('006_pagos'),
    ('007_productos_version'),
    ('008_cotizaciones'),
    ('009_roles_permisos'),
    ('010_auditoria'),
    ('011_apellido_personas'),
    ('012_ci_clientes'),
    ('013_empleados_sin_cargo'),
    ('014_facturas_rebaja_iva'),
    ('015_productos_precio_rebaja'),
    ('016_ventas_fraccionadas'),
    ('017_ropa'),
    ('018_catalogo_tallas_colores_propio'),
    ('019_precio_por_variante'),
    ('020_quitar_precio_por_variante'),
    ('021_permisos_reportes'),
    ('022_proveedores_email_nit'),
    ('024_marcas')
ON CONFLICT (name) DO NOTHING;
