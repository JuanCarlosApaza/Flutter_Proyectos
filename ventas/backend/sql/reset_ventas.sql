-- ============================================================================
-- SCRIPT DE RECREEACIÓN COMPLETA DE LA BD (DESTRUCTIVO)
--
-- ⚠️  USO MANUAL / DESARROLLO: borra todas las tablas y tipos y los vuelve
--     a crear. NO se ejecuta como migración de la aplicación.
--
-- Uso:
--   psql -U postgres -d ventas -f sql/reset_ventas.sql
--
-- La migración real (que sí corre sola al arrancar el servidor) está en
-- lib/src/data/database/migrations.dart y solo CREA la estructura.
-- ============================================================================

-- ============================================================================
-- 1. LIMPIEZA PREVIA (Opcional, elimina estructuras previas si existen)
-- ============================================================================
DROP TABLE IF EXISTS ajustes CASCADE;
DROP TABLE IF EXISTS auditoria CASCADE;
DROP TABLE IF EXISTS pagos CASCADE;
DROP TABLE IF EXISTS movimientos_stock CASCADE;
DROP TABLE IF EXISTS Rol_Permisos CASCADE;
DROP TABLE IF EXISTS Permisos CASCADE;
DROP TABLE IF EXISTS Roles CASCADE;
DROP TABLE IF EXISTS unidades_medida CASCADE;
DROP TABLE IF EXISTS detalles_cotizaciones CASCADE;
DROP TABLE IF EXISTS cotizaciones CASCADE;
DROP TABLE IF EXISTS Detalles_Ordenes_Pedidos CASCADE;
DROP TABLE IF EXISTS Facturas CASCADE;
DROP TABLE IF EXISTS Ordenes_Pedidos CASCADE;
DROP TABLE IF EXISTS producto_variantes CASCADE;
DROP TABLE IF EXISTS colores CASCADE;
DROP TABLE IF EXISTS marcas CASCADE;
DROP TABLE IF EXISTS Productos CASCADE;
DROP TABLE IF EXISTS Usuarios CASCADE;
DROP TABLE IF EXISTS Empleados CASCADE;
DROP TABLE IF EXISTS Proveedores CASCADE;
DROP TABLE IF EXISTS Clientes CASCADE;
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
CREATE TYPE estado_producto AS ENUM ('DISPONIBLE', 'AGOTADO', 'POR_VENCER', 'DESCONTINUADO', 'ELIMINADO');
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
-- 4. TABLAS INDEPENDIENTES (CATÁLOGOS)
-- ============================================================================
CREATE TABLE Categorias (
    Categoria_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Categoria VARCHAR(100) NOT NULL,
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Presentaciones (
    Presentacion_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Presentacion VARCHAR(100) NOT NULL,
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Unidades de venta (migración 017_unidades_medida): qué puede venderse y
-- con cuántos decimales admite la cantidad (KG → 3, UN → 0). El desplegable
-- «Unidad de venta» del producto y la pantalla «Unidades» leen de aquí.
CREATE TABLE unidades_medida (
    unidad_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Símbolo corto que viaja en `productos.unidad` (≤ 10, p. ej. `KG`).
    codigo VARCHAR(10) UNIQUE NOT NULL,
    nombre_unidad VARCHAR(50) NOT NULL,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('PESO','VOLUMEN','UNIDAD')),
    decimales SMALLINT NOT NULL DEFAULT 0 CHECK (decimales BETWEEN 0 AND 3),
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

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
       ('ROLLO', 'Rollo', 'UNIDAD', 0);


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

-- Semilla de permisos: 14 módulos de la app × 4 acciones.
INSERT INTO Permisos (Modulo, Accion)
SELECT m.Modulo, a.Accion
FROM (VALUES ('dashboard'), ('productos'), ('catalogo'), ('clientes'),
             ('ventas'), ('cotizaciones'), ('categorias'), ('proveedores'),
             ('empleados'), ('usuarios'), ('auditoria'), ('unidades'),
             ('ajustes'), ('reportes')) AS m(Modulo)
CROSS JOIN (VALUES ('ver'), ('crear'), ('editar'), ('eliminar')) AS a(Accion);

INSERT INTO Roles (Nombre, Descripcion, Es_Sistema) VALUES
    ('ADMIN',    'Acceso total al sistema', TRUE),
    ('CAJERO',   'Atención de mostrador',   TRUE),
    ('VENDEDOR', 'Solo ventas y catálogo',  TRUE);

-- ADMIN: los 56 permisos.
INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID FROM Roles r CROSS JOIN Permisos p
WHERE r.Nombre = 'ADMIN';

-- CAJERO: solo `ver`/`crear` (editar y eliminar quedan para rangos altos).
-- `reportes.ver` lo da también la migración 019 (mismo criterio: quien ve el
-- dashboard ve el informe), así que el INSERT es idempotente.
INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo || '.' || p.Accion IN (
        'dashboard.ver', 'productos.ver', 'catalogo.ver', 'clientes.ver',
        'clientes.crear', 'ventas.ver', 'ventas.crear', 'cotizaciones.ver',
        'cotizaciones.crear', 'categorias.ver', 'proveedores.ver',
        'unidades.ver', 'ajustes.ver', 'reportes.ver')
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

-- 5b. MARCAS Y GARANTÍA (migración 023_marcas_garantia)
--
--     Catálogo de marcas (vacío: lo llena la tienda desde su pestaña) y
--     columnas nuevas de `productos` debajo. El producto puede llevar marca
--     o no; la garantía es un dato en meses que solo se muestra en la ficha
--     del producto. Debe crearse ANTES de `Productos` por la FK.
CREATE TABLE marcas (
    marca_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    estado estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS marcas_nombre_activo_key
    ON marcas (LOWER(nombre)) WHERE estado <> 'ELIMINADO';

CREATE TABLE Productos (
    Producto_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Código interno / de barras. Índice UNIQUE aparte (migración 016), de
    -- modo que las filas existentes pueden quedarse en NULL.
    Codigo VARCHAR(60),
    Nombre_Producto VARCHAR(150) NOT NULL,
    Imagen VARCHAR(500),
    -- Texto libre opcional (migración 018_producto_descripcion): qué es o
    -- para qué sirve el producto. NULL = sin descripción.
    Descripcion VARCHAR(255),
    -- Unidad de venta (migración 016): con ella stock y cantidad de la
    -- venta se leen igual (1.450 KG), ya que no hay factor de conversión.
    -- La lista de códigos válidos ya no vive en un CHECK (la fijaba la 016):
    -- la decide la tabla `unidades_medida` (migración 017), validada en
    -- `ensureUnidad`.
    Unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Precio_Compra NUMERIC(10, 2) CHECK (Precio_Compra >= 0),
    Precio_Rebaja NUMERIC(10, 2) CHECK (Precio_Rebaja >= 0),
    Fecha_Vencimiento DATE,
    -- Fraccionado: admite 12.5 kg (migración 016; era INT).
    Stock NUMERIC(12, 3) DEFAULT 0 CHECK (Stock >= 0),
    -- NULL = usar el ajuste global `stockMinimo` del dashboard.
    Stock_Minimo NUMERIC(12, 3) CHECK (Stock_Minimo >= 0),
    -- Guarda optimista: cada UPDATE la incrementa y exige la versionLeida
    -- del cliente (migración 007_productos_version).
    Version INT NOT NULL DEFAULT 0,
    Categoria_ID BIGINT REFERENCES Categorias(Categoria_ID) ON DELETE RESTRICT,
    Proveedor_ID BIGINT REFERENCES Proveedores(Proveedor_ID) ON DELETE RESTRICT,
    Presentacion_ID BIGINT REFERENCES Presentaciones(Presentacion_ID) ON DELETE RESTRICT,
    -- Marca del catálogo (migración 023): nullable — el producto puede
    -- llevar marca o no. Solo texto: columna de la tabla de productos,
    -- filtro, búsqueda y la línea del Recibo 1 de la orden.
    Marca_ID BIGINT REFERENCES marcas(Marca_ID),
    -- Meses de garantía (migración 023): NULL = sin garantía; 1..120
    -- validados en `ensureGarantiaMeses`. Solo en la ficha del producto.
    Garantia_Meses SMALLINT,
    Estado estado_producto DEFAULT 'DISPONIBLE' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_productos_codigo ON Productos (Codigo);
CREATE INDEX IF NOT EXISTS idx_productos_unidad ON Productos (Unidad);
CREATE INDEX IF NOT EXISTS idx_productos_marca ON Productos (Marca_ID);

-- ============================================================================
-- 6b. COLORES Y VARIANTES DE STOCK (migración 022_colores_variantes)
--     El catálogo de colores (vacío: lo llena la tienda desde su pestaña) y
--     el reparto del stock de cada producto por color. Un producto sin
--     colores tiene una única variante con `color_id` NULL y `nombre_color
--     = 'Único'`; en una base con datos es el backfill de la migración la
--     que la crea, y en una recién reseteada, el seed.
-- ============================================================================
CREATE TABLE colores (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    -- Hexadecimal para el chip de color de la UI (#RRGGBB); opcional.
    codigo_hex VARCHAR(7),
    estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE producto_variantes (
    variante_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id BIGINT NOT NULL REFERENCES productos(producto_id) ON DELETE RESTRICT,
    -- NULL = variante «Único» (producto vendido sin color).
    color_id BIGINT REFERENCES colores(color_id) ON DELETE RESTRICT,
    -- Nombre congelado al crear la variante: renombrar el color no cambia
    -- el histórico de ventas.
    nombre_color VARCHAR(50) NOT NULL,
    stock NUMERIC(12, 3) NOT NULL DEFAULT 0 CHECK (stock >= 0),
    estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Unicidad solo entre filas vivas (borrado lógico), mismo criterio que la
-- 021: la clave la ocupan las vivas y ocultar libera el nombre/combo.
CREATE UNIQUE INDEX IF NOT EXISTS colores_nombre_activo_key
    ON colores (LOWER(nombre)) WHERE estado <> 'ELIMINADO';
CREATE UNIQUE INDEX IF NOT EXISTS producto_variantes_producto_color_key
    ON producto_variantes (producto_id, color_id)
    WHERE color_id IS NOT NULL AND estado <> 'ELIMINADO';
CREATE UNIQUE INDEX IF NOT EXISTS producto_variantes_producto_unico_key
    ON producto_variantes (producto_id)
    WHERE color_id IS NULL AND estado <> 'ELIMINADO';
CREATE INDEX IF NOT EXISTS idx_variantes_producto
    ON producto_variantes (producto_id);


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
    Rebaja NUMERIC(10, 2) DEFAULT 0 CHECK (Rebaja >= 0),
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
    Iva NUMERIC(10, 2) DEFAULT 0 CHECK (Iva >= 0),
    Estado estado_factura DEFAULT 'EMITIDA' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Detalles_Ordenes_Pedidos (
    Producto_ID BIGINT REFERENCES Productos(Producto_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
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
    -- Variante (color) concreta vendida (migración 022): una misma orden
    -- puede tener dos líneas del mismo producto con colores distintos.
    Variante_ID BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    PRIMARY KEY (Producto_ID, Orden_ID, Variante_ID)
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
    -- Variante movida (migración 022): NULL = movimiento anterior a los
    -- colores. Opcional y sin FK, como en la ruta de migraciones.
    variante_id BIGINT,
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
CREATE TRIGGER trg_actualizar_presentaciones BEFORE UPDATE ON Presentaciones FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
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
CREATE INDEX IF NOT EXISTS idx_productos_presentacion  ON Productos (Presentacion_ID);
CREATE INDEX IF NOT EXISTS idx_productos_vencimiento   ON Productos (Fecha_Vencimiento);

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
    producto_id BIGINT REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cotizacion_id BIGINT REFERENCES cotizaciones(cotizacion_id) ON DELETE CASCADE,
    nombre_producto VARCHAR(150) NOT NULL,
    -- La imagen se congela al cotizar, igual que el precio.
    imagen VARCHAR(500),
    unidad VARCHAR(10) NOT NULL DEFAULT 'UN',
    -- Fraccionada como en las órdenes (comparten `ItemOrden`, migración 016).
    cantidad NUMERIC(12, 3) NOT NULL CHECK (cantidad > 0),
    precio_venta NUMERIC(10, 2) NOT NULL CHECK (precio_venta >= 0),
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    -- Variante (color) concreta cotizada (migración 022).
    variante_id BIGINT NOT NULL REFERENCES producto_variantes(variante_id),
    PRIMARY KEY (producto_id, cotizacion_id, variante_id)
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
