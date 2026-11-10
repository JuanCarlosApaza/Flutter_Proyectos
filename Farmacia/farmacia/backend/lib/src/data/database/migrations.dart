/// Registro de migraciones de la base de datos.
///
/// Las migraciones son **inmutables**: una vez aplicada, nunca se edita su
/// SQL. Cualquier cambio de esquema se añade como una migración nueva.
///
/// Para añadir una tabla o columna:
/// 1. Crea una constante con el SQL (usa `r'''...'''` para que los `$`
///    de PostgreSQL, como los de `$$` o `$1`, no se interpreten en Dart).
/// 2. Añádela al final de [migrations] con un nombre incremental.
final class Migration {
  const Migration(this.name, this.sql);

  /// Identificador único, p. ej. `001_esquema_farmacia`.
  final String name;

  /// SQL completo de la migración (puede contener varias sentencias).
  final String sql;
}

/// Migraciones ordenadas de menor a mayor.
const List<Migration> migrations = [
  Migration('001_esquema_farmacia', _esquemaFarmacia),
  Migration('002_borrado_logico', _borradoLogico),
  Migration('003_sesiones', _sesiones),
  Migration('004_indices_rendimiento', _indicesRendimiento),
  Migration('005_ajustes', _ajustes),
  Migration('006_pagos', _pagos),
  Migration('007_productos_version', _productosVersion),
  Migration('008_cotizaciones', _cotizaciones),
  Migration('009_roles_permisos', _rolesPermisos),
  Migration('010_auditoria', _auditoria),
  Migration('011_apellido_personas', _apellidoPersonas),
  Migration('012_ci_clientes', _ciClientes),
  Migration('013_empleados_sin_cargo', _empleadosSinCargo),
  Migration('014_facturas_rebaja_iva', _facturasRebajaIva),
  Migration('015_productos_precio_rebaja', _productosPrecioRebaja),
];

/// Guarda optimista de productos (concurrencia).
///
/// El backend incrementa `version` en cada `UPDATE` y exige que coincida con
/// la `versionLeida` que manda el cliente; si otra persona modificó el
/// producto entre leerlo y guardarlo, el `WHERE` no coincide y la API
/// responde `409 producto_desactualizado` en lugar de pisar el cambio.
const String _productosVersion = r'''
ALTER TABLE productos ADD COLUMN version INT NOT NULL DEFAULT 0;
''';

/// Sesiones de acceso (login).
///
/// Cada inicio de sesión crea una fila con un **token aleatorio** que el
/// cliente envía en `Authorization: Bearer <token>`. Cerrar la sesión borra
/// la fila, de modo que el token deja de servir en el servidor (el logout
/// invalida la sesión de verdad, no solo en el cliente).
///
/// `expira_en` marca el final de la sesión: 24 h si no se pidió "recordarme",
/// 30 días si sí (lo decide `domain/usecases/auth_usecases.dart`).
const String _sesiones = r'''
CREATE TABLE sesiones (
    token VARCHAR(64) PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(usuario_id) ON DELETE CASCADE,
    creada_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_sesiones_usuario ON sesiones(usuario_id);
CREATE INDEX idx_sesiones_expira ON sesiones(expira_en);
''';

/// Borrado lógico: ningún `DELETE` de la API borra filas.
///
/// 1. Añade el valor `ELIMINADO` a los cinco enums de estado, de modo que
///    cada tabla pueda marcar un registro como **oculto** sin tocar su resto
///    de columnas ni su historial.
/// 2. Añade la columna `estado` a `detalles_ordenes_pedidos`, la única tabla
///    que no la tenía.
///
/// En PostgreSQL ≥ 12 `ALTER TYPE ... ADD VALUE` se permite dentro de la
/// transacción de la migración, siempre que el valor nuevo no se *use* en esa
/// misma transacción (aquí solo se declaran).
const String _borradoLogico = r'''
ALTER TYPE estado_general  ADD VALUE IF NOT EXISTS 'ELIMINADO';
ALTER TYPE estado_empleado ADD VALUE IF NOT EXISTS 'ELIMINADO';
ALTER TYPE estado_producto ADD VALUE IF NOT EXISTS 'ELIMINADO';
ALTER TYPE estado_orden    ADD VALUE IF NOT EXISTS 'ELIMINADO';
ALTER TYPE estado_boleta   ADD VALUE IF NOT EXISTS 'ELIMINADO';

ALTER TABLE detalles_ordenes_pedidos
  ADD COLUMN IF NOT EXISTS estado estado_general NOT NULL DEFAULT 'ACTIVO';
''';

/// Esquema completo de la farmacia:
/// categorías y presentaciones, personas (clientes, proveedores,
/// empleados), usuarios, productos, órdenes de pedido, boletas y detalles,
/// más los triggers de auditoría de `Fecha_Actualizacion`.
///
/// NOTA: este script solo **crea**. La limpieza destructiva (`DROP TABLE`)
/// vive en `sql/reset_farmacia.sql` y se ejecuta a mano.
const String _esquemaFarmacia = r'''
-- ============================================================================
-- TIPOS ENUMERADOS PARA ESTADOS DE NEGOCIO
-- ============================================================================
CREATE TYPE estado_general AS ENUM ('ACTIVO', 'INACTIVO', 'BLOQUEADO');
CREATE TYPE estado_empleado AS ENUM ('ACTIVO', 'VACACIONES', 'LICENCIA', 'INACTIVO');
CREATE TYPE estado_producto AS ENUM ('DISPONIBLE', 'AGOTADO', 'POR_VENCER', 'DESCONTINUADO');
CREATE TYPE estado_orden AS ENUM ('PENDIENTE', 'PAGADO', 'CANCELADO', 'DEVUELTO');
CREATE TYPE estado_boleta AS ENUM ('EMITIDA', 'ANULADA');

-- ============================================================================
-- FUNCIÓN PARA AUDITORÍA AUTOMÁTICA DE FECHA_ACTUALIZACION
-- ============================================================================
CREATE OR REPLACE FUNCTION actualizar_fecha_modificacion()
RETURNS TRIGGER AS $$
BEGIN
    NEW.Fecha_Actualizacion = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TABLAS INDEPENDIENTES (CATÁLOGOS)
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

-- ============================================================================
-- PERSONAS Y ENTIDADES
-- ============================================================================
CREATE TABLE Clientes (
    Cliente_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Cliente VARCHAR(150) NOT NULL,
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Genero CHAR(1),
    DNI VARCHAR(15) UNIQUE,
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
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Cargo VARCHAR(50),
    Edad INT CHECK (Edad >= 18),
    Telefono VARCHAR(20),
    Estado estado_empleado DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ============================================================================
-- USUARIOS Y PRODUCTOS
-- ============================================================================
CREATE TABLE Usuarios (
    Usuario_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Empleado_ID BIGINT UNIQUE REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Nivel_Usuario VARCHAR(50) NOT NULL,
    Nombre_Usuario VARCHAR(50) UNIQUE NOT NULL,
    Contrasena VARCHAR(255) NOT NULL,
    Estado estado_general DEFAULT 'ACTIVO' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Productos (
    Producto_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Nombre_Producto VARCHAR(150) NOT NULL,
    Imagen VARCHAR(500),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Precio_Compra NUMERIC(10, 2) CHECK (Precio_Compra >= 0),
    Fecha_Vencimiento DATE,
    Stock INT DEFAULT 0 CHECK (Stock >= 0),
    Categoria_ID BIGINT REFERENCES Categorias(Categoria_ID) ON DELETE RESTRICT,
    Proveedor_ID BIGINT REFERENCES Proveedores(Proveedor_ID) ON DELETE RESTRICT,
    Presentacion_ID BIGINT REFERENCES Presentaciones(Presentacion_ID) ON DELETE RESTRICT,
    Estado estado_producto DEFAULT 'DISPONIBLE' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ============================================================================
-- ORDENES DE PEDIDO, BOLETAS Y DETALLES
-- ============================================================================
CREATE TABLE Ordenes_Pedidos (
    Orden_ID BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Fecha_Orden TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Cliente_ID BIGINT REFERENCES Clientes(Cliente_ID) ON DELETE RESTRICT,
    Nombre_Cliente VARCHAR(150),
    Empleado_ID BIGINT REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Tipo_Pago_ID VARCHAR(50) NOT NULL,
    Total NUMERIC(10, 2) DEFAULT 0 CHECK (Total >= 0),
    Estado estado_orden DEFAULT 'PENDIENTE' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Boletas (
    Boleta_Numero BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Fecha_Boleta TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Empleado_ID BIGINT REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Cliente_ID BIGINT REFERENCES Clientes(Cliente_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT UNIQUE REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE RESTRICT,
    Subtotal NUMERIC(10, 2) NOT NULL CHECK (Subtotal >= 0),
    Descuento NUMERIC(10, 2) DEFAULT 0 CHECK (Descuento >= 0),
    Estado estado_boleta DEFAULT 'EMITIDA' NOT NULL,
    Fecha_Creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    Fecha_Actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE Detalles_Ordenes_Pedidos (
    Producto_ID BIGINT REFERENCES Productos(Producto_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
    Nombre_Producto VARCHAR(150) NOT NULL,
    Cantidad INT NOT NULL CHECK (Cantidad > 0),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Monto_Total NUMERIC(10, 2) NOT NULL CHECK (Monto_Total >= 0),
    PRIMARY KEY (Producto_ID, Orden_ID)
);

-- ============================================================================
-- TRIGGERS DE ACTUALIZACIÓN DE FECHAS DE AUDITORÍA
-- ============================================================================
CREATE TRIGGER trg_actualizar_categorias BEFORE UPDATE ON Categorias FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_presentaciones BEFORE UPDATE ON Presentaciones FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_clientes BEFORE UPDATE ON Clientes FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_proveedores BEFORE UPDATE ON Proveedores FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_empleados BEFORE UPDATE ON Empleados FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_usuarios BEFORE UPDATE ON Usuarios FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_productos BEFORE UPDATE ON Productos FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_ordenes BEFORE UPDATE ON Ordenes_Pedidos FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
CREATE TRIGGER trg_actualizar_boletas BEFORE UPDATE ON Boletas FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
''';

/// Índices de las consultas de negocio (listados del catálogo, ventas,
/// reportes y borrado lógico).
///
/// Sin estos índices, cada listado recorre la tabla entera (`Seq Scan`).
/// PostgreSQL **sí** indexa solo las claves primarias y los `UNIQUE`; las
/// columnas foráneas y los estados no tienen ningún índice:
///
/// - `Productos`: filtros del catálogo (categoría, estado, stock) y el
///   `ORDER BY nombre` de la vitrina.
/// - `Ordenes_Pedidos` / `Boletas`: filtros por persona, fecha y estado de
///   los módulos de Ventas y del dashboard.
/// - `Detalles_Ordenes_Pedidos`: la clave primaria `(Producto_ID, Orden_ID)`
///   **no** sirve para buscar por `Orden_ID` (no es la columna izquierda), y
///   ese es el caso típico al abrir una orden o anular una boleta.
///
/// Las tablas pequeñas (`Categorias`, `Presentaciones`) no llevan índice: un
/// recorrido completo es más rápido que la ida y vuelta al índice.
const String _indicesRendimiento = r'''
-- ============================================================================
-- CATÁLOGO: PRODUCTOS (filtros, stock y orden de la vitrina)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_productos_categoria     ON Productos (Categoria_ID);
CREATE INDEX IF NOT EXISTS idx_productos_estado        ON Productos (Estado);
CREATE INDEX IF NOT EXISTS idx_productos_stock         ON Productos (Stock);
CREATE INDEX IF NOT EXISTS idx_productos_nombre        ON Productos (Nombre_Producto);
CREATE INDEX IF NOT EXISTS idx_productos_proveedor     ON Productos (Proveedor_ID);
CREATE INDEX IF NOT EXISTS idx_productos_presentacion  ON Productos (Presentacion_ID);
CREATE INDEX IF NOT EXISTS idx_productos_vencimiento   ON Productos (Fecha_Vencimiento);

-- ============================================================================
-- VENTAS Y DASHBOARD: ÓRDENES Y BOLETAS
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_ordenes_cliente   ON Ordenes_Pedidos (Cliente_ID);
CREATE INDEX IF NOT EXISTS idx_ordenes_empleado  ON Ordenes_Pedidos (Empleado_ID);
CREATE INDEX IF NOT EXISTS idx_ordenes_fecha     ON Ordenes_Pedidos (Fecha_Orden);
CREATE INDEX IF NOT EXISTS idx_ordenes_estado    ON Ordenes_Pedidos (Estado);

CREATE INDEX IF NOT EXISTS idx_boletas_empleado  ON Boletas (Empleado_ID);
CREATE INDEX IF NOT EXISTS idx_boletas_cliente   ON Boletas (Cliente_ID);
CREATE INDEX IF NOT EXISTS idx_boletas_fecha     ON Boletas (Fecha_Boleta);
CREATE INDEX IF NOT EXISTS idx_boletas_estado    ON Boletas (Estado);

-- Detalle: buscar por orden (listado y anulación) sin barrer la tabla.
CREATE INDEX IF NOT EXISTS idx_detalles_orden    ON Detalles_Ordenes_Pedidos (Orden_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_producto ON Detalles_Ordenes_Pedidos (Producto_ID);
CREATE INDEX IF NOT EXISTS idx_detalles_estado   ON Detalles_Ordenes_Pedidos (Estado);

-- ============================================================================
-- PERSONAS Y CATÁLOGOS AUXILIARES (borrado lógico y combos)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_clientes_estado      ON Clientes (Estado);
CREATE INDEX IF NOT EXISTS idx_proveedores_estado   ON Proveedores (Estado);
CREATE INDEX IF NOT EXISTS idx_empleados_estado     ON Empleados (Estado);
CREATE INDEX IF NOT EXISTS idx_usuarios_estado      ON Usuarios (Estado);
''';

/// Ajustes globales de la aplicación (clave/valor).
///
/// Una fila por ajuste: `clave` dice qué se personaliza (vendedor por
/// defecto, tipo de pago, página inicial, filas por página… y el valor por
/// defecto de cada desplegable, con la forma `defecto.<entidad>.<campo>`) y
/// `valor` guarda lo último elegido en la vista «Ajustes». La BD no impone
/// ninguna restricción de claves (solo `UNIQUE`): quién decide qué es válido
/// es `domain/usecases/ajuste_usecases.dart`, que rechaza con `400` cualquier
/// clave que no sea de la lista conocida ni siga ese patrón.
///
/// Es una tabla nueva y diminuta que **no lee ni toca** los datos existentes
/// (usuarios, ventas ni existencias): guardar un ajuste no modifica nada más.
const String _ajustes = r'''
CREATE TABLE ajustes (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    clave VARCHAR(100) UNIQUE NOT NULL,
    valor VARCHAR(500) NOT NULL DEFAULT '',
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- `fecha_actualizacion` la mantiene la misma función del esquema 001.
CREATE TRIGGER trg_actualizar_ajustes BEFORE UPDATE ON ajustes
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
''';

/// Desglose de pagos de una venta (pago mixto: efectivo + QR, tarjeta +
/// Plin…).
///
/// Antes cada orden tenía un **único** `tipo_pago_id`. Ahora una orden admite
/// **varias** líneas de pago, cada una con su método y su monto; la suma de
/// los montos cuadra con el total de la orden.
///
/// La migración **backfillea** las órdenes existentes (método + total →
/// un único pago) y elimina la columna `tipo_pago_id`.
const String _pagos = r'''
CREATE TABLE pagos (
    pago_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    orden_id BIGINT NOT NULL REFERENCES ordenes_pedidos(orden_id) ON DELETE CASCADE,
    metodo_pago VARCHAR(50) NOT NULL,
    monto NUMERIC(10, 2) NOT NULL CHECK (monto > 0),
    referencia VARCHAR(100),
    estado estado_general NOT NULL DEFAULT 'ACTIVO',
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL,
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE INDEX idx_pagos_orden ON pagos(orden_id);

CREATE TRIGGER trg_actualizar_pagos BEFORE UPDATE ON pagos
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();

-- Las órdenes ya creadas heredan su método y total como un único pago
-- (las de total 0 no generan pago: el `CHECK (monto > 0)`).
INSERT INTO pagos (orden_id, metodo_pago, monto)
SELECT orden_id, tipo_pago_id, total FROM ordenes_pedidos WHERE total > 0;

ALTER TABLE ordenes_pedidos DROP COLUMN IF EXISTS tipo_pago_id;
''';

/// Cotizaciones: propuestas de precio para un cliente.
///
/// No toca stock (una cotización no reserva nada) ni lleva pagos: solo la
/// cabecera —con quién la creó (empleado de la sesión) y para quién
/// (cliente)— y sus líneas con el precio vigente de la BD.
const String _cotizaciones = r'''
CREATE TYPE estado_cotizacion AS ENUM ('VIGENTE', 'ACEPTADA', 'RECHAZADA', 'ELIMINADO');

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
    -- La imagen se congela al cotizar, igual que el precio: la hoja muestra
    -- lo que se ofreció, aunque el producto cambie después.
    imagen VARCHAR(500),
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_venta NUMERIC(10, 2) NOT NULL CHECK (precio_venta >= 0),
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    PRIMARY KEY (producto_id, cotizacion_id)
);

-- Los listados filtran por estado y el detalle abre por cotizacion_id (la
-- clave primaria compuesta no sirve para buscar solo por la izquierda).
CREATE INDEX idx_cotizaciones_estado ON cotizaciones (estado);
CREATE INDEX idx_cotizaciones_cliente ON cotizaciones (cliente_id);
CREATE INDEX idx_cotizaciones_empleado ON cotizaciones (empleado_id);
CREATE INDEX idx_detalles_cotizaciones_cot ON detalles_cotizaciones (cotizacion_id);

CREATE TRIGGER trg_actualizar_cotizaciones BEFORE UPDATE ON cotizaciones
    FOR EACH ROW EXECUTE FUNCTION actualizar_fecha_modificacion();
''';

/// Roles y permisos (RBAC): sustituye el texto libre `Usuarios.Nivel_Usuario`.
///
/// - `Roles`: los niveles de acceso (ADMIN, CAJERO, VENDEDOR y los creados
///   desde la UI). `Es_Sistema` protege los roles base: no se borran ni se
///   editan sus permisos.
/// - `Permisos`: cada fila es `módulo` × `acción` (`ver`, `crear`, `editar`,
///   `eliminar`) de los 11 módulos de la app.
/// - `Rol_Permisos`: qué puede cada rol.
///
/// Migra los usuarios existentes (busca un rol con el mismo nombre que su
/// `Nivel_Usuario`; los niveles desconocidos caen a CAJERO) y **borra** la
/// columna antigua para que la única fuente de verdad sea `Roles`.
const String _rolesPermisos = r'''
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

CREATE INDEX idx_rol_permisos_rol ON Rol_Permisos(Rol_ID);

-- Semilla de permisos: 11 módulos de la app × 4 acciones.
INSERT INTO Permisos (Modulo, Accion)
SELECT m.Modulo, a.Accion
FROM (VALUES ('dashboard'), ('productos'), ('catalogo'), ('clientes'),
             ('ventas'), ('cotizaciones'), ('categorias'), ('proveedores'),
             ('empleados'), ('usuarios'), ('ajustes')) AS m(Modulo)
CROSS JOIN (VALUES ('ver'), ('crear'), ('editar'), ('eliminar')) AS a(Accion);

-- Roles base.
INSERT INTO Roles (Nombre, Descripcion, Es_Sistema) VALUES
    ('ADMIN',    'Acceso total al sistema', TRUE),
    ('CAJERO',   'Atención de mostrador',   TRUE),
    ('VENDEDOR', 'Solo ventas y catálogo',  TRUE);

-- Vincular los usuarios existentes a su rol y eliminar la columna vieja.
ALTER TABLE Usuarios ADD COLUMN Rol_ID BIGINT REFERENCES Roles(Rol_ID);
UPDATE Usuarios u SET Rol_ID = COALESCE(
    (SELECT r.Rol_ID FROM Roles r WHERE r.Nombre = u.Nivel_Usuario),
    (SELECT Rol_ID FROM Roles WHERE Nombre = 'CAJERO'));
ALTER TABLE Usuarios ALTER COLUMN Rol_ID SET NOT NULL;
ALTER TABLE Usuarios DROP COLUMN Nivel_Usuario;
CREATE INDEX idx_usuarios_rol ON Usuarios(Rol_ID);

-- ADMIN: los 44 permisos.
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
''';

/// Auditoría de cambios: quién hizo qué, cuándo, desde dónde y con qué
/// resultado (migración `010_auditoria`).
///
/// - Cada fila es un evento: login (y fallidos), logout y TODA mutación
///   (`POST/PUT/DELETE`) de la API, con detalle fino en lo sensible.
/// - `usuario_id`/`nombre_usuario`/`rol` son **instantáneas**: no hay FK
///   para que el registro sobreviva al borrado de la cuenta.
/// - `detalles` es JSONB y solo lleva detalle explícito de las rutas: la
///   capa que lo escribe elimina `contrasena`/`claveAdmin`/`token` por
///   defecto (nunca viajan a la BD).
/// - Los permisos del nuevo módulo (`auditoria.*`) solo van al rol ADMIN.
const String _auditoria = r'''
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

CREATE INDEX idx_auditoria_fecha ON auditoria (fecha DESC);
CREATE INDEX idx_auditoria_usuario ON auditoria (nombre_usuario);
CREATE INDEX idx_auditoria_entidad ON auditoria (entidad);

-- Permisos del módulo Auditoría (12º módulo de la app) y concesión al ADMIN.
INSERT INTO Permisos (Modulo, Accion)
SELECT 'auditoria', a.Accion
FROM (VALUES ('ver'), ('crear'), ('editar'), ('eliminar')) AS a(Accion);

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p ON p.Modulo = 'auditoria'
WHERE r.Nombre = 'ADMIN';

-- «Página inicial» guarda el ÍNDICE del menú: Auditoría ocupa el 10 y
-- Ajustes pasa del 10 al 11 (sigue siendo la última entrada).
UPDATE ajustes SET valor = '11' WHERE clave = 'paginaInicial' AND valor = '10';
''';

/// Apellido de clientes y empleados.
///
/// Hasta ahora el nombre entero iba en un único campo (`Nombre_Cliente` /
/// `Nombre_Empleado`), sin sitio para los apellidos. Se añade una columna
/// `apellido` a las dos tablas (los proveedores siguen con un solo campo de
/// razón social). Las filas existentes se quedan con `apellido` a `NULL`: la
/// app muestra solo el nombre cuando no hay apellido. Es `IF NOT EXISTS`
/// porque `sql/reset_farmacia.sql` ya crea la columna al recrear la BD.
const String _apellidoPersonas = r'''
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS apellido VARCHAR(100);
ALTER TABLE empleados ADD COLUMN IF NOT EXISTS apellido VARCHAR(100);
''';

/// Documento de identidad: `dni` pasa a `ci` (Cédula de Identidad boliviana).
///
/// Solo `clientes` tiene esa columna. Va **protegido con `IF EXISTS`** porque
/// `sql/reset_farmacia.sql` ya la crea como `CI` al recrear la BD: si la
/// columna ya se llama `ci`, no hay nada que renombrar.
const String _ciClientes = r'''
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'clientes'
      AND column_name = 'dni'
  ) THEN
    ALTER TABLE clientes RENAME COLUMN dni TO ci;

    IF EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conname = 'clientes_dni_key'
        AND conrelid = 'clientes'::regclass
    ) THEN
      ALTER TABLE clientes RENAME CONSTRAINT clientes_dni_key
        TO clientes_ci_key;
    END IF;
  END IF;
END $$;
''';

/// El cargo de texto libre queda fuera de `empleados`: la función de cada
/// empleado la define su **rol vinculado** (`usuarios` → `roles`), que es
/// lo que muestran y filtran la tabla de Empleados y el selector de
/// vendedor. `IF EXISTS` porque `sql/reset_farmacia.sql` ya no lo crea.
const String _empleadosSinCargo = r'''
ALTER TABLE empleados DROP COLUMN IF EXISTS cargo;
''';

/// Cobro boliviano: la **rebaja** se aplica al cobrar, el **IVA** (14.94 %)
/// entra con la factura, y el documento «boleta» pasa a llamarse «factura».
///
/// Todo va protegido con `IF EXISTS`/`IF NOT EXISTS` porque
/// `sql/reset_farmacia.sql` ya crea el esquema final (`facturas` con
/// `rebaja`/`iva` y las columnas nuevas de la orden): si no existe nada que
/// renombrar, la migración no hace nada.
const String _facturasRebajaIva = r'''
ALTER TABLE ordenes_pedidos
    ADD COLUMN IF NOT EXISTS rebaja NUMERIC(10, 2) NOT NULL DEFAULT 0;
ALTER TABLE ordenes_pedidos
    ADD COLUMN IF NOT EXISTS factura BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ordenes_pedidos_rebaja_check'
  ) THEN
    ALTER TABLE ordenes_pedidos
      ADD CONSTRAINT ordenes_pedidos_rebaja_check CHECK (rebaja >= 0);
  END IF;

  -- «boletas» → «facturas» (columnas, tipo, trigger, índices y claves).
  IF to_regclass('public.boletas') IS NOT NULL THEN
    ALTER TABLE boletas RENAME TO facturas;
  END IF;

  IF to_regclass('public.facturas') IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'facturas' AND column_name = 'boleta_numero'
    ) THEN
      ALTER TABLE facturas RENAME COLUMN boleta_numero TO factura_numero;
    END IF;
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'facturas' AND column_name = 'fecha_boleta'
    ) THEN
      ALTER TABLE facturas RENAME COLUMN fecha_boleta TO fecha_factura;
    END IF;
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'facturas' AND column_name = 'descuento'
    ) THEN
      ALTER TABLE facturas RENAME COLUMN descuento TO rebaja;
    END IF;
    ALTER TABLE facturas ADD COLUMN IF NOT EXISTS iva NUMERIC(10, 2)
      NOT NULL DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'facturas_iva_check'
  ) AND to_regclass('public.facturas') IS NOT NULL THEN
    ALTER TABLE facturas ADD CONSTRAINT facturas_iva_check CHECK (iva >= 0);
  END IF;

  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'estado_boleta') THEN
    ALTER TYPE estado_boleta RENAME TO estado_factura;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_actualizar_boletas'
  ) THEN
    ALTER TRIGGER trg_actualizar_boletas ON facturas
      RENAME TO trg_actualizar_facturas;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'idx_boletas_empleado') THEN
    ALTER INDEX idx_boletas_empleado RENAME TO idx_facturas_empleado;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'idx_boletas_cliente') THEN
    ALTER INDEX idx_boletas_cliente RENAME TO idx_facturas_cliente;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'idx_boletas_fecha') THEN
    ALTER INDEX idx_boletas_fecha RENAME TO idx_facturas_fecha;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'idx_boletas_estado') THEN
    ALTER INDEX idx_boletas_estado RENAME TO idx_facturas_estado;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'boletas_pkey'
  ) THEN
    ALTER TABLE facturas RENAME CONSTRAINT boletas_pkey TO facturas_pkey;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'boletas_orden_id_key'
  ) THEN
    ALTER TABLE facturas RENAME CONSTRAINT boletas_orden_id_key
      TO facturas_orden_id_key;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'boletas_descuento_check'
  ) THEN
    ALTER TABLE facturas RENAME CONSTRAINT boletas_descuento_check
      TO facturas_rebaja_check;
  END IF;
END $$;
''';

/// Máximo a rebajar por unidad de un producto (`precio_rebaja`).
///
/// `NULL` = sin límite, `0` = no se puede rebajar; nunca por encima del
/// precio de venta (lo valida el dominio). `IF NOT EXISTS` porque
/// `sql/reset_farmacia.sql` ya la crea.
const String _productosPrecioRebaja = r'''
ALTER TABLE productos
    ADD COLUMN IF NOT EXISTS precio_rebaja NUMERIC(10, 2);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'productos_precio_rebaja_check'
  ) THEN
    ALTER TABLE productos
      ADD CONSTRAINT productos_precio_rebaja_check CHECK (precio_rebaja >= 0);
  END IF;
END $$;
''';
