import 'migrations.dart';

/// Esquema SQLite de partida para la APK embebida.
///
/// Es la traducción de `backend/sql/reset_farmacia.sql` (esquema final de
/// PostgreSQL tras las 15 migraciones) más la tabla `sesiones` de la
/// migración 003, que ese script no incluía. Reglas de traducción:
///
/// * enums (`estado_*`) → `TEXT ... CHECK (col IN (...))` (conserva la
///   validación en BD que hacía el tipo enum);
/// * `BIGINT GENERATED ALWAYS AS IDENTITY` → `INTEGER PRIMARY KEY AUTOINCREMENT`;
/// * `TIMESTAMP WITH TIME ZONE`/`TIMESTAMPTZ` → `TEXT` con
///   `DEFAULT CURRENT_TIMESTAMP` (formato `yyyy-MM-dd HH:mm:ss`, UTC);
/// * `JSONB` → `TEXT` (los valores llegan ya serializados con `jsonEncode`);
/// * `BOOLEAN` y `NUMERIC(10,2)` se quedan igual (SQLite los entiende);
/// * el trigger plpgsql `actualizar_fecha_modificacion()` → trigger
///   `AFTER UPDATE` equivalente por tabla (los repositorios no escriben
///   `fecha_actualizacion` en los UPDATE: la mantiene el trigger);
/// * las semillas de `Permisos` con `VALUES ... CROSS JOIN` se reescriben en
///   subconsultas `UNION ALL`, que funcionan en ambos motores.
///
/// Las migraciones **futuras** no se añaden aquí ni en `migrations.dart`:
/// se definen una sola vez en `migraciones_compartidas.dart` y el `Migrator`
/// las renderiza para cada motor.
const String esquemaSqlite = r'''
CREATE TABLE Categorias (
    Categoria_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Categoria VARCHAR(100) NOT NULL,
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Presentaciones (
    Presentacion_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Presentacion VARCHAR(100) NOT NULL,
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Clientes (
    Cliente_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Cliente VARCHAR(150) NOT NULL,
    Apellido VARCHAR(100),
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Genero CHAR(1),
    CI VARCHAR(15) UNIQUE,
    Telefono VARCHAR(20),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Proveedores (
    Proveedor_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Proveedor VARCHAR(150) NOT NULL,
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Telefono VARCHAR(20),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Empleados (
    Empleado_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Empleado VARCHAR(150) NOT NULL,
    Apellido VARCHAR(100),
    Direccion VARCHAR(200),
    Ciudad VARCHAR(100),
    Edad INT CHECK (Edad >= 18),
    Telefono VARCHAR(20),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','VACACIONES','LICENCIA','INACTIVO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Roles (
    Rol_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre VARCHAR(50) UNIQUE NOT NULL,
    Descripcion VARCHAR(255),
    Es_Sistema BOOLEAN NOT NULL DEFAULT FALSE,
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Creado_En TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Actualizado_En TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Permisos (
    Permiso_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Modulo VARCHAR(50) NOT NULL,
    Accion VARCHAR(20) NOT NULL CHECK (Accion IN ('ver','crear','editar','eliminar')),
    UNIQUE (Modulo, Accion)
);

CREATE TABLE Rol_Permisos (
    Rol_ID BIGINT NOT NULL REFERENCES Roles(Rol_ID) ON DELETE CASCADE,
    Permiso_ID BIGINT NOT NULL REFERENCES Permisos(Permiso_ID) ON DELETE CASCADE,
    PRIMARY KEY (Rol_ID, Permiso_ID)
);

INSERT INTO Permisos (Modulo, Accion)
SELECT m.Modulo, a.Accion FROM (
    SELECT 'dashboard' AS Modulo UNION ALL
    SELECT 'productos' UNION ALL
    SELECT 'catalogo' UNION ALL
    SELECT 'clientes' UNION ALL
    SELECT 'ventas' UNION ALL
    SELECT 'cotizaciones' UNION ALL
    SELECT 'categorias' UNION ALL
    SELECT 'proveedores' UNION ALL
    SELECT 'empleados' UNION ALL
    SELECT 'usuarios' UNION ALL
    SELECT 'auditoria' UNION ALL
    SELECT 'ajustes'
) m CROSS JOIN (
    SELECT 'ver' AS Accion UNION ALL
    SELECT 'crear' UNION ALL
    SELECT 'editar' UNION ALL
    SELECT 'eliminar'
) a;

INSERT INTO Roles (Nombre, Descripcion, Es_Sistema) VALUES
    ('ADMIN',    'Acceso total al sistema', TRUE),
    ('CAJERO',   'Atención de mostrador',   TRUE),
    ('VENDEDOR', 'Solo ventas y catálogo',  TRUE);

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID FROM Roles r CROSS JOIN Permisos p
WHERE r.Nombre = 'ADMIN';

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo || '.' || p.Accion IN (
        'dashboard.ver', 'productos.ver', 'catalogo.ver', 'clientes.ver',
        'clientes.crear', 'ventas.ver', 'ventas.crear', 'cotizaciones.ver',
        'cotizaciones.crear', 'categorias.ver', 'proveedores.ver',
        'ajustes.ver')
WHERE r.Nombre = 'CAJERO';

INSERT INTO Rol_Permisos (Rol_ID, Permiso_ID)
SELECT r.Rol_ID, p.Permiso_ID
FROM Roles r JOIN Permisos p
    ON p.Modulo || '.' || p.Accion IN (
        'ventas.ver', 'ventas.crear', 'catalogo.ver', 'catalogo.crear',
        'clientes.ver')
WHERE r.Nombre = 'VENDEDOR';

CREATE TABLE Usuarios (
    Usuario_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Empleado_ID BIGINT UNIQUE REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Rol_ID BIGINT NOT NULL REFERENCES Roles(Rol_ID),
    Nombre_Usuario VARCHAR(50) UNIQUE NOT NULL,
    Contrasena VARCHAR(255) NOT NULL,
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Productos (
    Producto_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Nombre_Producto VARCHAR(150) NOT NULL,
    Imagen VARCHAR(500),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Precio_Compra NUMERIC(10, 2) CHECK (Precio_Compra >= 0),
    Precio_Rebaja NUMERIC(10, 2) CHECK (Precio_Rebaja >= 0),
    Fecha_Vencimiento DATE,
    Stock INT DEFAULT 0 CHECK (Stock >= 0),
    Version INT NOT NULL DEFAULT 0,
    Categoria_ID BIGINT REFERENCES Categorias(Categoria_ID) ON DELETE RESTRICT,
    Proveedor_ID BIGINT REFERENCES Proveedores(Proveedor_ID) ON DELETE RESTRICT,
    Presentacion_ID BIGINT REFERENCES Presentaciones(Presentacion_ID) ON DELETE RESTRICT,
    Estado TEXT NOT NULL DEFAULT 'DISPONIBLE' CHECK (Estado IN ('DISPONIBLE','AGOTADO','POR_VENCER','DESCONTINUADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Ordenes_Pedidos (
    Orden_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Fecha_Orden TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Cliente_ID BIGINT REFERENCES Clientes(Cliente_ID) ON DELETE RESTRICT,
    Nombre_Cliente VARCHAR(150),
    Empleado_ID BIGINT REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Total NUMERIC(10, 2) DEFAULT 0 CHECK (Total >= 0),
    Rebaja NUMERIC(10, 2) DEFAULT 0 CHECK (Rebaja >= 0),
    Factura BOOLEAN NOT NULL DEFAULT FALSE,
    Estado TEXT NOT NULL DEFAULT 'PENDIENTE' CHECK (Estado IN ('PENDIENTE','PAGADO','CANCELADO','DEVUELTO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pagos (
    Pago_ID INTEGER PRIMARY KEY AUTOINCREMENT,
    Orden_ID BIGINT NOT NULL REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
    Metodo_Pago VARCHAR(50) NOT NULL,
    Monto NUMERIC(10, 2) NOT NULL CHECK (Monto > 0),
    Referencia VARCHAR(100),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Facturas (
    Factura_Numero INTEGER PRIMARY KEY AUTOINCREMENT,
    Fecha_Factura TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Empleado_ID BIGINT REFERENCES Empleados(Empleado_ID) ON DELETE RESTRICT,
    Cliente_ID BIGINT REFERENCES Clientes(Cliente_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT UNIQUE REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE RESTRICT,
    Subtotal NUMERIC(10, 2) NOT NULL CHECK (Subtotal >= 0),
    Rebaja NUMERIC(10, 2) DEFAULT 0 CHECK (Rebaja >= 0),
    Iva NUMERIC(10, 2) DEFAULT 0 CHECK (Iva >= 0),
    Estado TEXT NOT NULL DEFAULT 'EMITIDA' CHECK (Estado IN ('EMITIDA','ANULADA','ELIMINADO')),
    Fecha_Creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Fecha_Actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Detalles_Ordenes_Pedidos (
    Producto_ID BIGINT REFERENCES Productos(Producto_ID) ON DELETE RESTRICT,
    Orden_ID BIGINT REFERENCES Ordenes_Pedidos(Orden_ID) ON DELETE CASCADE,
    Nombre_Producto VARCHAR(150) NOT NULL,
    Cantidad INT NOT NULL CHECK (Cantidad > 0),
    Precio_Venta NUMERIC(10, 2) NOT NULL CHECK (Precio_Venta >= 0),
    Monto_Total NUMERIC(10, 2) NOT NULL CHECK (Monto_Total >= 0),
    Estado TEXT NOT NULL DEFAULT 'ACTIVO' CHECK (Estado IN ('ACTIVO','INACTIVO','BLOQUEADO','ELIMINADO')),
    PRIMARY KEY (Producto_ID, Orden_ID)
);

CREATE TABLE ajustes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    clave VARCHAR(100) UNIQUE NOT NULL,
    valor VARCHAR(500) NOT NULL DEFAULT '',
    fecha_creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE cotizaciones (
    cotizacion_id INTEGER PRIMARY KEY AUTOINCREMENT,
    cliente_id BIGINT REFERENCES clientes(cliente_id) ON DELETE RESTRICT,
    nombre_cliente VARCHAR(150),
    empleado_id BIGINT REFERENCES empleados(empleado_id) ON DELETE RESTRICT,
    fecha_cotizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total NUMERIC(10, 2) DEFAULT 0 CHECK (total >= 0),
    estado TEXT NOT NULL DEFAULT 'VIGENTE' CHECK (estado IN ('VIGENTE','ACEPTADA','RECHAZADA','ELIMINADO')),
    fecha_creacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_actualizacion TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE detalles_cotizaciones (
    producto_id BIGINT REFERENCES productos(producto_id) ON DELETE RESTRICT,
    cotizacion_id BIGINT REFERENCES cotizaciones(cotizacion_id) ON DELETE CASCADE,
    nombre_producto VARCHAR(150) NOT NULL,
    imagen VARCHAR(500),
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_venta NUMERIC(10, 2) NOT NULL CHECK (precio_venta >= 0),
    monto_total NUMERIC(10, 2) NOT NULL CHECK (monto_total >= 0),
    PRIMARY KEY (producto_id, cotizacion_id)
);

CREATE TABLE auditoria (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_id BIGINT,
    nombre_usuario VARCHAR(50),
    rol VARCHAR(50),
    accion VARCHAR(40) NOT NULL,
    exitoso BOOLEAN NOT NULL DEFAULT TRUE,
    codigo_error VARCHAR(50),
    entidad VARCHAR(50),
    entidad_id BIGINT,
    resumen TEXT NOT NULL,
    detalles TEXT,
    ip VARCHAR(45)
);

CREATE TABLE sesiones (
    token VARCHAR(64) PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(usuario_id) ON DELETE CASCADE,
    creada_en TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expira_en TEXT NOT NULL
);

CREATE INDEX idx_sesiones_usuario ON sesiones(usuario_id);
CREATE INDEX idx_sesiones_expira ON sesiones(expira_en);

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

CREATE INDEX IF NOT EXISTS idx_cotizaciones_estado ON cotizaciones (estado);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_cliente ON cotizaciones (cliente_id);
CREATE INDEX IF NOT EXISTS idx_cotizaciones_empleado ON cotizaciones (empleado_id);
CREATE INDEX IF NOT EXISTS idx_detalles_cotizaciones_cot ON detalles_cotizaciones (cotizacion_id);

CREATE INDEX IF NOT EXISTS idx_auditoria_fecha ON auditoria (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_auditoria_usuario ON auditoria (nombre_usuario);
CREATE INDEX IF NOT EXISTS idx_auditoria_entidad ON auditoria (entidad);

CREATE TRIGGER trg_actualizar_categorias AFTER UPDATE ON Categorias
    FOR EACH ROW BEGIN
        UPDATE Categorias SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Categoria_ID = NEW.Categoria_ID;
    END;
CREATE TRIGGER trg_actualizar_presentaciones AFTER UPDATE ON Presentaciones
    FOR EACH ROW BEGIN
        UPDATE Presentaciones SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Presentacion_ID = NEW.Presentacion_ID;
    END;
CREATE TRIGGER trg_actualizar_clientes AFTER UPDATE ON Clientes
    FOR EACH ROW BEGIN
        UPDATE Clientes SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Cliente_ID = NEW.Cliente_ID;
    END;
CREATE TRIGGER trg_actualizar_proveedores AFTER UPDATE ON Proveedores
    FOR EACH ROW BEGIN
        UPDATE Proveedores SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Proveedor_ID = NEW.Proveedor_ID;
    END;
CREATE TRIGGER trg_actualizar_empleados AFTER UPDATE ON Empleados
    FOR EACH ROW BEGIN
        UPDATE Empleados SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Empleado_ID = NEW.Empleado_ID;
    END;
CREATE TRIGGER trg_actualizar_usuarios AFTER UPDATE ON Usuarios
    FOR EACH ROW BEGIN
        UPDATE Usuarios SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Usuario_ID = NEW.Usuario_ID;
    END;
CREATE TRIGGER trg_actualizar_productos AFTER UPDATE ON Productos
    FOR EACH ROW BEGIN
        UPDATE Productos SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Producto_ID = NEW.Producto_ID;
    END;
CREATE TRIGGER trg_actualizar_ordenes AFTER UPDATE ON Ordenes_Pedidos
    FOR EACH ROW BEGIN
        UPDATE Ordenes_Pedidos SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Orden_ID = NEW.Orden_ID;
    END;
CREATE TRIGGER trg_actualizar_facturas AFTER UPDATE ON Facturas
    FOR EACH ROW BEGIN
        UPDATE Facturas SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Factura_Numero = NEW.Factura_Numero;
    END;
CREATE TRIGGER trg_actualizar_ajustes AFTER UPDATE ON ajustes
    FOR EACH ROW BEGIN
        UPDATE ajustes SET fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE id = NEW.id;
    END;
CREATE TRIGGER trg_actualizar_pagos AFTER UPDATE ON pagos
    FOR EACH ROW BEGIN
        UPDATE pagos SET Fecha_Actualizacion = CURRENT_TIMESTAMP
        WHERE Pago_ID = NEW.Pago_ID;
    END;
CREATE TRIGGER trg_actualizar_cotizaciones AFTER UPDATE ON cotizaciones
    FOR EACH ROW BEGIN
        UPDATE cotizaciones SET fecha_actualizacion = CURRENT_TIMESTAMP
        WHERE cotizacion_id = NEW.cotizacion_id;
    END;
''';

/// Migraciones de partida para SQLite: el esquema completo de una sola vez.
///
/// En una base de datos PostgreSQL ya existente estas migraciones **no**
/// corren (su `schema_migrations` no las contiene pero tampoco las
/// necesita): el `Migrator` elige la lista según el motor.
const List<Migration> migrationsSqlite = [
  Migration('000_esquema_sqlite', esquemaSqlite),
];
