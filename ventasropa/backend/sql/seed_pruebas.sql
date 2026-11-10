-- ============================================================================
-- SEMILLA DE DATOS DE PRUEBA (no destructiva, idempotente)
--
-- Simula el flujo completo de la tienda de ropa sobre una BD ya poblada:
--   catálogos → catálogo de ropa → personas → usuario → productos →
--   variantes (talla+color) → kardex INICIAL → venta cobrada con pago mixto
--   (efectivo + QR, con rebaja e IVA) → factura → cotización.
--
-- Uso:
--   psql -U postgres -d ventarropa -f sql/seed_pruebas.sql
--
-- Reglas de negocio que respeta (venta.dart / validaciones.dart):
--   * IVA boliviano 14,94 %, solo si la orden pide factura.
--   * Base imponible = subtotal − rebaja (nunca negativa).
--   * Total cobrado = subtotal − rebaja + IVA = suma de pagos.
--   * productos.stock = SUMA del stock de sus variantes (la API lo mantiene).
--   * Cada variante con stock tiene su movimiento kardex INICIAL.
--
-- Es idempotente: se puede volver a correr y no duplica nada (todas las
-- insercciones clavan por su clave natural: CI, código, nombre de usuario,
-- talla/color únicos, o comprueban que la orden/cotización ya existe).
--
-- Usuario de prueba creado:  demo_prueba / prueba123  (rol CAJERO)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CATÁLOGOS DE ROPA (tallas y colores nuevos; los existentes se conservan)
-- ----------------------------------------------------------------------------
INSERT INTO tallas (nombre, orden)
VALUES ('M', 2), ('L', 3), ('XL', 4)
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO colores (nombre, codigo_hex)
VALUES ('Negro', '#000000'), ('Blanco', '#FFFFFF')
ON CONFLICT (nombre) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. CATEGORÍAS Y PROVEEDOR
-- ----------------------------------------------------------------------------
INSERT INTO categorias (nombre_categoria)
SELECT v.nombre
FROM (VALUES ('Camisetas'), ('Pantalones'), ('Vestidos'), ('Faldas')) AS v(nombre)
WHERE NOT EXISTS (
    SELECT 1 FROM categorias c WHERE c.nombre_categoria = v.nombre
);

INSERT INTO proveedores (nombre_proveedor, direccion, ciudad, telefono, email, nit)
SELECT 'Textiles Andinos SRL', 'Av. Busch 1245', 'Cochabamba',
       '4-4256789', 'ventas@textilesandinos.bo', '1029384756'
WHERE NOT EXISTS (
    SELECT 1 FROM proveedores WHERE nombre_proveedor = 'Textiles Andinos SRL'
);

-- ----------------------------------------------------------------------------
-- 3. PERSONAS
-- ----------------------------------------------------------------------------
INSERT INTO clientes (nombre_cliente, apellido, direccion, ciudad, genero, ci, telefono)
VALUES
    ('María', 'López',   'Calle Colón 456',  'Cochabamba', 'F', '7654321', '71234567'),
    ('Jorge', 'Mamani',  'Av. Oquendo 789',  'El Alto',    'M', '1122334', '77654321')
ON CONFLICT (ci) DO NOTHING;

INSERT INTO empleados (nombre_empleado, apellido, direccion, ciudad, edad, telefono)
SELECT 'Diego', 'Quispe Prueba', 'Av. Ayacucho 321', 'Cochabamba', 28, '70112233'
WHERE NOT EXISTS (
    SELECT 1 FROM empleados
    WHERE nombre_empleado = 'Diego' AND apellido = 'Quispe Prueba'
);

-- ----------------------------------------------------------------------------
-- 4. USUARIO DE PRUEBA (rol CAJERO; contraseña "prueba123" en bcrypt cost 10)
-- ----------------------------------------------------------------------------
INSERT INTO usuarios (empleado_id, rol_id, nombre_usuario, contrasena)
SELECT e.empleado_id, r.rol_id, 'demo_prueba',
       '$2a$10$fD2E63kw0VOoo1fCXo2b9.zI1aA11u2X1BA.JeAVufbAZr4cPVR.q'
FROM empleados e
JOIN roles r ON r.nombre = 'CAJERO'
WHERE e.nombre_empleado = 'Diego' AND e.apellido = 'Quispe Prueba'
  AND NOT EXISTS (
      SELECT 1 FROM usuarios WHERE nombre_usuario = 'demo_prueba'
  );

-- ----------------------------------------------------------------------------
-- 5. PRODUCTOS (stock = suma de sus variantes ANTES de la venta de prueba)
-- ----------------------------------------------------------------------------
INSERT INTO productos (
    codigo, nombre_producto, descripcion, precio_venta, precio_compra,
    stock, stock_minimo, categoria_id, proveedor_id
)
SELECT v.codigo, v.nombre, v.descripcion, v.precio_venta, v.precio_compra,
       v.stock, 5,
       c.categoria_id,
       (SELECT proveedor_id FROM proveedores
         WHERE nombre_proveedor = 'Textiles Andinos SRL')
FROM (VALUES
    ('CAM-ALG-001', 'Camiseta Algodón Premium', 'Camiseta 100% algodón peinado, cuello redondo', 120.00,  60.00, 24, 'Camisetas'),
    ('CAM-DEP-001', 'Camiseta Deportiva Dry',   'Tela transpirable para entrenamiento',         150.00,  80.00,  9, 'Camisetas'),
    ('JEA-CLA-001', 'Jeans Clásico Azul',       'Jeans recto, talla regular',                   250.00, 140.00,  9, 'Pantalones'),
    ('PAN-JOG-001', 'Pantalón Jogger Negro',    'Jogger con puño elástico',                     200.00, 110.00, 21, 'Pantalones'),
    ('VES-FLA-001', 'Vestido Floral Verano',    'Estampado floral, tela liviana',               320.00, 180.00,  7, 'Vestidos'),
    ('FAL-PLI-001', 'Falda Plisada Elegante',   'Falda midi plisada',                           180.00,  95.00,  5, 'Faldas')
) AS v(codigo, nombre, descripcion, precio_venta, precio_compra, stock, categoria)
JOIN categorias c ON c.nombre_categoria = v.categoria
WHERE NOT EXISTS (
    SELECT 1 FROM productos p WHERE p.codigo = v.codigo
);

-- ----------------------------------------------------------------------------
-- 6. VARIANTES (combinación prenda + talla + color, cada una con su stock)
-- ----------------------------------------------------------------------------
INSERT INTO producto_variantes (producto_id, talla_id, color_id, stock)
SELECT p.producto_id, t.talla_id, c.color_id, v.stock
FROM (VALUES
    ('CAM-ALG-001', 'M',  'Negro',  10),
    ('CAM-ALG-001', 'M',  'Blanco',  8),
    ('CAM-ALG-001', 'L',  'Negro',   6),
    ('CAM-DEP-001', 'L',  'Blanco',  6),
    ('CAM-DEP-001', 'XL', 'Blanco',  3),
    ('JEA-CLA-001', 'L',  'Negro',   5),
    ('JEA-CLA-001', 'XL', 'Negro',   4),
    ('PAN-JOG-001', 'M',  'Negro',  12),
    ('PAN-JOG-001', 'L',  'Negro',   9),
    ('VES-FLA-001', 'M',  'Blanco',  7),
    ('FAL-PLI-001', 'M',  'Negro',   5)
) AS v(codigo, talla, color, stock)
JOIN productos p     ON p.codigo = v.codigo
JOIN tallas t        ON t.nombre = v.talla
JOIN colores c       ON c.nombre = v.color
WHERE NOT EXISTS (
    SELECT 1 FROM producto_variantes pv
    WHERE pv.producto_id = p.producto_id
      AND pv.talla_id   = t.talla_id
      AND pv.color_id   = c.color_id
);

-- ----------------------------------------------------------------------------
-- 7. KARDEX INICIAL (una entrada por variante de la semilla)
-- ----------------------------------------------------------------------------
INSERT INTO movimientos_stock (
    producto_id, variante_id, cantidad, motivo, stock_resultante, notas
)
SELECT pv.producto_id, pv.variante_id, pv.stock, 'INICIAL', pv.stock,
       'Stock inicial de la semilla de prueba'
FROM producto_variantes pv
JOIN productos p ON p.producto_id = pv.producto_id
WHERE p.codigo IN ('CAM-ALG-001', 'CAM-DEP-001', 'JEA-CLA-001',
                   'PAN-JOG-001', 'VES-FLA-001', 'FAL-PLI-001')
  AND NOT EXISTS (
      SELECT 1 FROM movimientos_stock m
      WHERE m.variante_id = pv.variante_id AND m.motivo = 'INICIAL'
  );

-- ----------------------------------------------------------------------------
-- 8. VENTA DE PRUEBA (pago mixto, con rebaja e IVA) + FACTURA
--    Líneas:  2 × Camiseta Algodón M/Negro   @ 120,00 = 240,00
--             1 × Jeans Clásico  L/Negro     @ 250,00 = 250,00
--    Subtotal 490,00 · Rebaja 40,00 · Base 450,00
--    IVA 14,94 % = 67,23 · Total a pagar = 517,23  →  EFECTIVO 300,00 + QR 217,23
--    OJO: `ordenes.total` guarda la SUMA DE LAS LÍNEAS (subtotal, 490,00);
--    la API deriva base/IVA/totalPagar al leer (venta.dart: totalPagar).
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_cliente_id    BIGINT;
    v_cliente2_id   BIGINT;
    v_empleado_id   BIGINT;
    v_orden_id      BIGINT;
    v_cotizacion_id BIGINT;
BEGIN
    -- Clientes y empleado de la prueba
    SELECT cliente_id INTO v_cliente_id  FROM clientes WHERE ci = '7654321';
    SELECT cliente_id INTO v_cliente2_id FROM clientes WHERE ci = '1122334';
    SELECT empleado_id INTO v_empleado_id FROM empleados
     WHERE nombre_empleado = 'Diego' AND apellido = 'Quispe Prueba';

    -- 8a. La orden solo se crea si no existe todavía
    IF v_cliente_id IS NOT NULL AND v_empleado_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM ordenes_pedidos
            WHERE cliente_id = v_cliente_id
              AND estado <> 'ELIMINADO'
       ) THEN

        INSERT INTO ordenes_pedidos (
            cliente_id, nombre_cliente, empleado_id,
            total, rebaja, factura, estado
        ) VALUES (
            v_cliente_id, 'María López', v_empleado_id,
            490.00, 40.00, TRUE, 'PAGADO'
        )
        RETURNING orden_id INTO v_orden_id;

        -- Líneas de la venta (PK = variante + orden)
        INSERT INTO detalles_ordenes_pedidos (
            producto_id, orden_id, variante_id, nombre_producto, unidad,
            cantidad, precio_venta, costo_unitario, monto_total
        )
        SELECT p.producto_id, v_orden_id, pv.variante_id,
               p.nombre_producto, 'UN', d.cantidad, d.precio_venta,
               p.precio_compra, d.monto_total
        FROM (VALUES
            ('CAM-ALG-001', 'M', 'Negro', 2::NUMERIC, 120.00::NUMERIC, 240.00::NUMERIC),
            ('JEA-CLA-001', 'L', 'Negro', 1::NUMERIC, 250.00::NUMERIC, 250.00::NUMERIC)
        ) AS d(codigo, talla, color, cantidad, precio_venta, monto_total)
        JOIN productos p  ON p.codigo = d.codigo
        JOIN producto_variantes pv ON pv.producto_id = p.producto_id
        JOIN tallas t  ON t.talla_id  = pv.talla_id AND t.nombre  = d.talla
        JOIN colores c ON c.color_id  = pv.color_id AND c.nombre = d.color;

        -- Kardex de salida (cantidad firmada, stock_resultante ya descontado)
        INSERT INTO movimientos_stock (
            producto_id, variante_id, cantidad, motivo,
            stock_resultante, orden_id, notas
        )
        SELECT pv.producto_id, pv.variante_id, -d.cantidad, 'VENTA',
               pv.stock - d.cantidad, v_orden_id, 'Venta de la semilla de prueba'
        FROM (VALUES
            ('CAM-ALG-001', 'M', 'Negro', 2::NUMERIC),
            ('JEA-CLA-001', 'L', 'Negro', 1::NUMERIC)
        ) AS d(codigo, talla, color, cantidad)
        JOIN productos p  ON p.codigo = d.codigo
        JOIN producto_variantes pv ON pv.producto_id = p.producto_id
        JOIN tallas t  ON t.talla_id  = pv.talla_id AND t.nombre  = d.talla
        JOIN colores c ON c.color_id  = pv.color_id AND c.nombre = d.color;

        -- Descuenta el stock de las variantes vendidas
        UPDATE producto_variantes pv
        SET stock = pv.stock - d.cantidad
        FROM (VALUES
            ('CAM-ALG-001', 'M', 'Negro', 2::NUMERIC),
            ('JEA-CLA-001', 'L', 'Negro', 1::NUMERIC)
        ) AS d(codigo, talla, color, cantidad)
        JOIN productos p ON p.codigo = d.codigo
        WHERE pv.producto_id = p.producto_id
          AND EXISTS (
              SELECT 1 FROM tallas t, colores c
               WHERE t.talla_id = pv.talla_id AND t.nombre = d.talla
                 AND c.color_id = pv.color_id AND c.nombre = d.color
          );

        -- Recalcula el stock agregado de los productos afectados
        UPDATE productos p
        SET stock = s.total
        FROM (SELECT producto_id, SUM(stock) AS total
                FROM producto_variantes GROUP BY producto_id) s
        WHERE p.producto_id = s.producto_id
          AND p.codigo IN ('CAM-ALG-001', 'JEA-CLA-001');

        -- Pago mixto: debe sumar exactamente subtotal − rebaja + IVA
        INSERT INTO pagos (orden_id, metodo_pago, monto, referencia)
        VALUES (v_orden_id, 'EFECTIVO', 300.00, NULL),
               (v_orden_id, 'QR',       217.23, 'QR-SEMILLA-001');

        -- Factura: copia subtotal, rebaja e IVA ya cobrados
        INSERT INTO facturas (
            empleado_id, cliente_id, orden_id,
            subtotal, rebaja, iva, estado
        ) VALUES (
            v_empleado_id, v_cliente_id, v_orden_id,
            490.00, 40.00, 67.23, 'EMITIDA'
        );
    END IF;

    -- 8b. Cotización de prueba (no toca stock ni lleva pagos)
    IF v_cliente2_id IS NOT NULL AND v_empleado_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM cotizaciones
            WHERE cliente_id = v_cliente2_id
              AND estado <> 'ELIMINADO'
       ) THEN

        INSERT INTO cotizaciones (
            cliente_id, nombre_cliente, empleado_id, total, estado
        ) VALUES (
            v_cliente2_id, 'Jorge Mamani', v_empleado_id, 620.00, 'VIGENTE'
        )
        RETURNING cotizacion_id INTO v_cotizacion_id;

        INSERT INTO detalles_cotizaciones (
            producto_id, cotizacion_id, variante_id, nombre_producto,
            unidad, cantidad, precio_venta, monto_total
        )
        SELECT p.producto_id, v_cotizacion_id, pv.variante_id,
               p.nombre_producto, 'UN', d.cantidad, d.precio_venta, d.monto_total
        FROM (VALUES
            ('VES-FLA-001', 'M', 'Blanco', 1::NUMERIC, 320.00::NUMERIC, 320.00::NUMERIC),
            ('CAM-DEP-001', 'L', 'Blanco', 2::NUMERIC, 150.00::NUMERIC, 300.00::NUMERIC)
        ) AS d(codigo, talla, color, cantidad, precio_venta, monto_total)
        JOIN productos p  ON p.codigo = d.codigo
        JOIN producto_variantes pv ON pv.producto_id = p.producto_id
        JOIN tallas t  ON t.talla_id  = pv.talla_id AND t.nombre  = d.talla
        JOIN colores c ON c.color_id  = pv.color_id AND c.nombre = d.color;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 9. TRAZA EN AUDITORÍA (un solo registro, aunque se repita el script)
-- ----------------------------------------------------------------------------
INSERT INTO auditoria (
    usuario_id, nombre_usuario, rol, accion, entidad, entidad_id, resumen, ip
)
SELECT u.usuario_id, u.nombre_usuario, 'CAJERO', 'SEED_PRUEBA', 'sistema', NULL,
       'Semilla de datos de prueba aplicada sobre la BD ventarropa', '127.0.0.1'
FROM usuarios u
WHERE u.nombre_usuario = 'demo_prueba'
  AND NOT EXISTS (
      SELECT 1 FROM auditoria WHERE accion = 'SEED_PRUEBA'
  );

COMMIT;

-- ----------------------------------------------------------------------------
-- VERIFICACIÓN (estas consultas deben devolver filas coherentes)
-- ----------------------------------------------------------------------------
SELECT 'categorias' AS tabla, COUNT(*) AS filas FROM categorias
UNION ALL SELECT 'tallas',       COUNT(*) FROM tallas
UNION ALL SELECT 'colores',      COUNT(*) FROM colores
UNION ALL SELECT 'proveedores',  COUNT(*) FROM proveedores
UNION ALL SELECT 'clientes',     COUNT(*) FROM clientes
UNION ALL SELECT 'empleados',    COUNT(*) FROM empleados
UNION ALL SELECT 'usuarios',     COUNT(*) FROM usuarios
UNION ALL SELECT 'productos',    COUNT(*) FROM productos
UNION ALL SELECT 'variantes',    COUNT(*) FROM producto_variantes
UNION ALL SELECT 'ordenes',      COUNT(*) FROM ordenes_pedidos
UNION ALL SELECT 'detalles',     COUNT(*) FROM detalles_ordenes_pedidos
UNION ALL SELECT 'pagos',        COUNT(*) FROM pagos
UNION ALL SELECT 'facturas',     COUNT(*) FROM facturas
UNION ALL SELECT 'cotizaciones', COUNT(*) FROM cotizaciones
UNION ALL SELECT 'movimientos',  COUNT(*) FROM movimientos_stock
ORDER BY 1;

-- La venta debe cuadrar: base = total − rebaja · IVA = base × 0,1494
--                        totalPagar = base + IVA = suma de pagos
SELECT o.orden_id,
       o.total,
       o.rebaja,
       ROUND((o.total - o.rebaja) * 0.1494, 2) AS iva_calculado,
       f.iva AS iva_factura,
       o.total - o.rebaja + ROUND((o.total - o.rebaja) * 0.1494, 2) AS total_pagar,
       (SELECT COALESCE(SUM(p.monto), 0) FROM pagos p WHERE p.orden_id = o.orden_id) AS total_pagado
FROM ordenes_pedidos o
JOIN facturas f ON f.orden_id = o.orden_id
WHERE o.cliente_id = (SELECT cliente_id FROM clientes WHERE ci = '7654321');

-- El stock agregado debe ser igual a la suma de las variantes
SELECT p.codigo, p.nombre_producto, p.stock AS stock_producto,
       SUM(pv.stock) AS suma_variantes
FROM productos p
JOIN producto_variantes pv ON pv.producto_id = p.producto_id
WHERE p.codigo IN ('CAM-ALG-001', 'JEA-CLA-001')
GROUP BY p.producto_id, p.codigo, p.nombre_producto, p.stock;
