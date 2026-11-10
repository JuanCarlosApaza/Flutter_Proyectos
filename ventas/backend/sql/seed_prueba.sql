-- =====================================================================
-- Seed de datos de prueba — sistema «ventas»
-- =====================================================================
-- Puebla una base VACÍA con un catálogo realista y 12 órdenes repartidas
-- en ~18 días, para poder probar listados, informes, kardex y RBAC.
--
-- Respeta las reglas del dominio (lib/src/domain/usecases/venta_usecases.dart
-- y lib/src/domain/rules/validaciones.dart):
--
--   * total          = Σ (cantidad × precio_venta) redondeado a 2 decimales
--   * base           = total − rebaja      (la rebaja ≤ total)
--   * iva            = round(base × 0.1494, 2)  solo si la orden es factura
--   * total a pagar  = base + iva  → los pagos cuadran exactamente con él
--   * factura        = solo de una orden PAGADO; una sola por orden;
--                      subtotal = total, rebaja y iva copiados de la orden
--   * al pasar a PAGADO se descuenta el stock y se escribe el kardex
--     (movimientos_stock, cantidad negativa y stock_resultante en curso);
--     al salir de PAGADO (DEVUELTO) se repone con DEVOLUCION
--   * DESCONTINUADO no se vende, AGOTADO nace al llegar el stock a 0
--
-- Uso:   psql -U postgres -d ventas -f sql/seed_prueba.sql
-- Idempotencia: se niega a ejecutarse si la tabla productos ya tiene filas,
-- para no duplicar el catálogo.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Guardia: solo sobre una base sin catálogo
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM productos) THEN
    RAISE EXCEPTION
      'La base ya tiene productos (% filas); este seed solo corre sobre una '
      'base vacía. Usa sql/reset_ventas.sql antes de sembrar.',
      (SELECT count(*) FROM productos);
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 1. Catálogos
-- ---------------------------------------------------------------------
INSERT INTO categorias (nombre_categoria) VALUES
  ('Bebidas'),
  ('Snacks'),
  ('Limpieza'),
  ('Panadería'),
  ('Frutas y Verduras');

INSERT INTO presentaciones (nombre_presentacion) VALUES
  ('Botella'),
  ('Caja'),
  ('Paquete'),
  ('Sobre');

INSERT INTO proveedores (nombre_proveedor, direccion, ciudad, telefono) VALUES
  ('Distribuidora Andina',   'Av. Busch 2140',        'La Paz',       '22445566'),
  ('Importaciones Santa Cruz','Zona Norte, Km 4',     'Santa Cruz',   '33445566'),
  ('Alimentos del Sur',      'Calle Ayacucho 89',     'Cochabamba',   '44556677');

INSERT INTO empleados (nombre_empleado, apellido, edad, telefono, ciudad, direccion) VALUES
  ('Juan',   'Pérez',      29, '71111111', 'La Paz',      'Av. Circunvalación 10'),
  ('María',  'López',      34, '72222222', 'Cochabamba',  'Calle Quijarro 20'),
  ('Carlos', 'Rodríguez',  41, '73333333', 'Santa Cruz',  'Av. Alemana 30'),
  ('Ana',    'Torres',     26, '74444444', 'Sucre',       'Calle Azurduy 40');

INSERT INTO clientes (nombre_cliente, apellido, ci, telefono, genero, ciudad, direccion) VALUES
  ('Luis',         'Mamani Quispe', '6845123',  '71234567', 'M', 'La Paz',     'Av. Busch 123'),
  ('María Fernanda','Rojas',       '7123456',  '72345678', 'F', 'Cochabamba', 'Calle Libertad 456'),
  ('José Carlos',  'Vargas',       '8123456',  '73456789', 'M', 'Santa Cruz', 'Av. Principal 789'),
  ('Ana Lucía',    'Flores',       '9123456',  '74567890', 'F', 'Sucre',      'Calle Bolívar 12'),
  ('Pedro',        'Rodríguez Choque','10234567','75678901','M', 'Oruro',      'Av. Sajama 34'),
  ('Carmen Elena', 'Suárez',       '11234567', '76789012', 'F', 'Tarija',     'Calle Reyes 56');

-- Dos cuentas de prueba además de carlos_admin (que ya existe).
--   juan_cajero   / cajero1234    → rol CAJERO
--   ana_vendedora / vendedor1234  → rol VENDEDOR
INSERT INTO usuarios (empleado_id, rol_id, nombre_usuario, contrasena, estado)
SELECT e.empleado_id, r.rol_id, 'juan_cajero',
       '$2a$10$pUq/M6b2QtHsouviUNdPCOvryr.kp78Q38wJoyGUDgBTmzwne4tWe', 'ACTIVO'
  FROM empleados e, roles r
 WHERE e.nombre_empleado = 'Juan' AND e.apellido = 'Pérez'
   AND r.nombre = 'CAJERO';

INSERT INTO usuarios (empleado_id, rol_id, nombre_usuario, contrasena, estado)
SELECT e.empleado_id, r.rol_id, 'ana_vendedora',
       '$2a$10$uzPD2p82JQiqPI8BfkEQK.sRsECu8YIv5/A8ue.Y/E1FGxhq0uRLq', 'ACTIVO'
  FROM empleados e, roles r
 WHERE e.nombre_empleado = 'Ana' AND e.apellido = 'Torres'
   AND r.nombre = 'VENDEDOR';

-- ---------------------------------------------------------------------
-- 2. Productos  (stock = existencias INICIALES; el kardex posterior lo
--    descontará lo vendido en órdenes PAGADAS)
-- ---------------------------------------------------------------------
INSERT INTO productos
  (nombre_producto, codigo, descripcion, categoria_id, proveedor_id,
   presentacion_id, unidad, precio_compra, precio_venta, precio_rebaja,
   stock, stock_minimo, fecha_vencimiento, estado)
SELECT
  v.nombre, v.codigo, v.descripcion,
  c.categoria_id, p.proveedor_id, pr.presentacion_id,
  v.unidad, v.compra::numeric, v.venta::numeric, v.rebaja::numeric,
  v.stock::numeric, v.stock_minimo::numeric,
  NULLIF(v.vencimiento, '')::date, v.estado::estado_producto
FROM (VALUES
  -- nombre, codigo, descripcion, cat, prov, pres, unidad, compra, venta, rebaja, stock, stock_min, vencimiento, estado
  ('Agua Mineral 600 ml',   'BEB-001', 'Agua pura natural',            'Bebidas',           'Distribuidora Andina',   'Botella', 'UN',       3.00,  5.00, NULL, 144,   12, '',              'DISPONIBLE'),
  ('Gaseosa Cola 2 L',      'BEB-002', NULL,                           'Bebidas',           'Distribuidora Andina',   'Botella', 'LT',       8.00, 12.00, NULL,  60,    6, '',              'DISPONIBLE'),
  ('Jugo de Naranja 1 L',   'BEB-003', 'Recién exprimido',             'Bebidas',           'Alimentos del Sur',      'Botella', 'LT',       9.00, 15.00, NULL,  36,   40, '2026-10-20',    'DISPONIBLE'),
  ('Café Molido 250 g',     'BEB-004', NULL,                           'Bebidas',           'Alimentos del Sur',      'Sobre',   'SOBRE',   15.00, 24.00, NULL,  40,    5, '',              'DISPONIBLE'),
  ('Papas Fritas 150 g',    'SNK-001', NULL,                           'Snacks',            'Distribuidora Andina',   'Paquete', 'PAQUETE',  5.00,  8.50, 2.00,  90,   10, '',              'DISPONIBLE'),
  ('Galletas de Chocolate', 'SNK-002', NULL,                           'Snacks',            'Alimentos del Sur',      'Paquete', 'PAQUETE',  6.00, 10.00, NULL,  72,    8, '2026-11-15',    'DISPONIBLE'),
  ('Chocolate Negro 100 g', 'SNK-003', 'Se agotó el lote anterior',    'Snacks',            'Alimentos del Sur',      'Caja',    'UN',       4.50,  7.50, NULL,   4,    5, '',              'DISPONIBLE'),
  ('Detergente en Polvo 1 kg','LIM-001',NULL,                           'Limpieza',          'Importaciones Santa Cruz','Caja',   'KG',      12.00, 18.00, NULL,  48,    5, '',              'DISPONIBLE'),
  ('Línea Blanca 500 ml',   'LIM-002', NULL,                           'Limpieza',          'Importaciones Santa Cruz','Botella','ML',       7.00, 11.50, NULL,  30,    5, '',              'DISPONIBLE'),
  ('Lejía 1 L',             'LIM-003', 'Ya no se repone',              'Limpieza',          'Importaciones Santa Cruz','Botella','LT',       5.00,  8.00, NULL,  54,    6, '',              'DESCONTINUADO'),
  ('Pan Integral',          'PAN-001', 'Horneado del día',             'Panadería',         'Alimentos del Sur',      'Paquete', 'KG',       9.00, 14.00, NULL,  24,    4, '2026-10-12',    'POR_VENCER'),
  ('Croissant',             'PAN-002', NULL,                           'Panadería',         'Alimentos del Sur',      'Paquete', 'UN',       3.50,  6.00, NULL,  36,    6, '2026-10-11',    'DISPONIBLE'),
  ('Torta de Chocolate',    'PAN-003', NULL,                           'Panadería',         'Alimentos del Sur',      'Caja',    'CAJA',     45.00, 70.00, NULL,  10,    2, '2026-10-14',    'DISPONIBLE'),
  ('Manzana Roja',          'FRU-001', NULL,                           'Frutas y Verduras', 'Alimentos del Sur',      'Caja',    'KG',       6.50, 10.00, NULL, 80.500, 10, '',            'DISPONIBLE'),
  ('Plátano',               'FRU-002', NULL,                           'Frutas y Verduras', 'Alimentos del Sur',      'Caja',    'KG',       4.00,  7.00, NULL, 65.250, 10, '',            'DISPONIBLE'),
  ('Tomate',                'FRU-003', NULL,                           'Frutas y Verduras', 'Alimentos del Sur',      'Caja',    'KG',       5.00,  9.00, NULL, 45.750,  8, '',            'DISPONIBLE')
) AS v(nombre, codigo, descripcion, cat, prov, pres, unidad, compra, venta, rebaja, stock, stock_minimo, vencimiento, estado)
JOIN categorias       c  ON c.nombre_categoria  = v.cat
JOIN proveedores      p  ON p.nombre_proveedor  = v.prov
JOIN presentaciones   pr ON pr.nombre_presentacion = v.pres;

-- Variantes (migración 022): cada producto arranca con su variante «Único»,
-- que hereda el stock inicial. El catálogo de colores queda vacío a propósito
-- (se llena desde la UI de Colores).
INSERT INTO producto_variantes (producto_id, color_id, nombre_color, stock)
SELECT p.producto_id, NULL, 'Único', COALESCE(p.stock, 0)
  FROM productos p
 WHERE NOT EXISTS (
       SELECT 1 FROM producto_variantes v WHERE v.producto_id = p.producto_id
     );

-- Kardex: la entrada inicial de cada producto.
INSERT INTO movimientos_stock (producto_id, cantidad, motivo, stock_resultante, notas)
SELECT producto_id, stock, 'INICIAL', stock, 'Carga inicial del seed de prueba'
  FROM productos;

-- ---------------------------------------------------------------------
-- 3. Órdenes de pedido
--    Se crean con total 0; los importes se recalculan abajo a partir de
--    las líneas, de modo que nunca pueden des cuadrar.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_ordenes (
  etiqueta     text PRIMARY KEY,
  fecha        timestamptz  NOT NULL,
  ci_cliente   text         NOT NULL,
  nombre_emp   text         NOT NULL,   -- nombre del empleado
  apellido_emp text         NOT NULL,   -- apellido del empleado
  estado       estado_orden NOT NULL,
  rebaja       numeric(10,2) NOT NULL DEFAULT 0,
  factura      boolean      NOT NULL DEFAULT false,
  metodo1      text         NOT NULL,
  monto1       numeric(10,2),           -- NULL = pago único por el total
  metodo2      text,
  orden_id     bigint
);

INSERT INTO tmp_ordenes
  (etiqueta, fecha, ci_cliente, nombre_emp, apellido_emp, estado, rebaja, factura, metodo1, monto1, metodo2)
VALUES
  ('O01', '2026-09-22 10:15:00-04', '6845123',  'Juan',   'Pérez',      'PAGADO',    0.00, false, 'EFECTIVO',      NULL, NULL),
  ('O02', '2026-09-25 16:40:00-04', '7123456',  'María',  'López',      'PAGADO',    5.00, true,  'EFECTIVO',     60.00, 'QR'),
  ('O03', '2026-09-28 11:05:00-04', '8123456',  'Carlos', 'Rodríguez',  'PAGADO',    0.00, true,  'TARJETA',      NULL, NULL),
  ('O04', '2026-10-01 09:30:00-04', '9123456',  'Ana',    'Torres',     'PAGADO',    0.00, false, 'YAPE',         NULL, NULL),
  ('O05', '2026-10-03 15:20:00-04', '10234567', 'Juan',   'Pérez',      'PENDIENTE', 0.00, false, 'EFECTIVO',     NULL, NULL),
  ('O06', '2026-10-04 12:45:00-04', '11234567', 'María',  'López',      'CANCELADO', 0.00, false, 'TRANSFERENCIA',NULL, NULL),
  ('O07', '2026-10-05 17:10:00-04', '6845123',  'Carlos', 'Rodríguez',  'PAGADO',    3.00, false, 'EFECTIVO',     50.00, 'PLIN'),
  ('O08', '2026-10-06 10:55:00-04', '7123456',  'Ana',    'Torres',     'PAGADO',    0.00, true,  'QR',           NULL, NULL),
  ('O09', '2026-10-07 14:05:00-04', '8123456',  'Juan',   'Pérez',      'PENDIENTE', 0.00, false, 'EFECTIVO',     NULL, NULL),
  ('O10', '2026-10-08 11:35:00-04', '9123456',  'María',  'López',      'PAGADO',    0.00, false, 'EFECTIVO',     NULL, NULL),
  ('O11', '2026-10-09 09:20:00-04', '10234567', 'Carlos', 'Rodríguez',  'PAGADO',    0.00, true,  'EFECTIVO',    100.00, 'QR'),
  ('O12', '2026-10-09 16:50:00-04', '11234567', 'Ana',    'Torres',     'DEVUELTO',  0.00, false, 'EFECTIVO',     NULL, NULL);

-- Líneas: (orden, código de producto, cantidad)
CREATE TEMP TABLE tmp_lineas (
  etiqueta text NOT NULL,
  codigo   text NOT NULL,
  cantidad numeric(12,3) NOT NULL
);

INSERT INTO tmp_lineas (etiqueta, codigo, cantidad) VALUES
  ('O01', 'BEB-001', 12.000),
  ('O01', 'SNK-001',  6.000),

  ('O02', 'BEB-002',  4.000),
  ('O02', 'FRU-001',  3.500),
  ('O02', 'FRU-002',  2.250),

  ('O03', 'LIM-001',  5.000),
  ('O03', 'LIM-002',  3.000),

  ('O04', 'PAN-001',  2.500),
  ('O04', 'PAN-002',  8.000),

  ('O05', 'BEB-003',  6.000),
  ('O05', 'SNK-002', 10.000),

  ('O06', 'PAN-003',  2.000),

  ('O07', 'BEB-004',  2.000),
  ('O07', 'SNK-003',  4.000),
  ('O07', 'FRU-003',  2.500),

  ('O08', 'BEB-001', 24.000),
  ('O08', 'FRU-001',  5.000),

  ('O09', 'LIM-002',  4.000),
  ('O09', 'SNK-001',  5.000),

  ('O10', 'BEB-002',  2.000),
  ('O10', 'FRU-002',  4.000),
  ('O10', 'FRU-003',  3.000),

  ('O11', 'BEB-001',  6.000),
  ('O11', 'PAN-002',  6.000),
  ('O11', 'SNK-002',  3.000),

  ('O12', 'SNK-001',  4.000);

DO $$
DECLARE
  o        record;
  l        record;
  v_orden  bigint;
  v_total  numeric(10,2);
  v_base   numeric(10,2);
  v_iva    numeric(10,2);
  v_pagar  numeric(10,2);
  v_cod    bigint;
BEGIN
  FOR o IN SELECT * FROM tmp_ordenes ORDER BY fecha LOOP
    INSERT INTO ordenes_pedidos
      (fecha_orden, cliente_id, nombre_cliente, empleado_id,
       total, estado, rebaja, factura)
    SELECT o.fecha,
           cl.cliente_id,
           cl.nombre_cliente || ' ' || cl.apellido,
           em.empleado_id,
           0, o.estado, o.rebaja, o.factura
      FROM clientes cl
      JOIN empleados em ON em.nombre_empleado = o.nombre_emp
                       AND em.apellido       = o.apellido_emp
     WHERE cl.ci = o.ci_cliente
    RETURNING orden_id INTO v_orden;

    UPDATE tmp_ordenes SET orden_id = v_orden WHERE etiqueta = o.etiqueta;

    -- Líneas con el precio y la unidad vigentes del producto, atadas a su
    -- variante «Único» (022): la clave de la línea la incluye.
    FOR l IN
      SELECT p.producto_id, p.nombre_producto, p.unidad,
             p.precio_venta, p.precio_compra, t.cantidad, v.variante_id
        FROM tmp_lineas t
        JOIN productos p ON p.codigo = t.codigo
        JOIN producto_variantes v ON v.producto_id = p.producto_id
                                 AND v.color_id IS NULL
       WHERE t.etiqueta = o.etiqueta
       ORDER BY p.producto_id
    LOOP
      INSERT INTO detalles_ordenes_pedidos
        (orden_id, producto_id, nombre_producto, unidad, cantidad,
         precio_venta, costo_unitario, monto_total, estado, variante_id)
      VALUES (v_orden, l.producto_id, l.nombre_producto, l.unidad, l.cantidad,
              l.precio_venta, l.precio_compra,
              round(l.cantidad * l.precio_venta, 2), 'ACTIVO', l.variante_id);
    END LOOP;

    -- Total = suma real de las líneas.
    SELECT COALESCE(sum(monto_total), 0) INTO v_total
      FROM detalles_ordenes_pedidos WHERE orden_id = v_orden;

    -- Rebaja ≤ total (dominio: ensureImporteNoNegativo + rebaja_excesiva).
    IF o.rebaja > v_total THEN
      RAISE EXCEPTION 'O%: la rebaja (%) supera el total (%)',
                      o.etiqueta, o.rebaja, v_total;
    END IF;

    v_base  := v_total - o.rebaja;
    v_iva   := CASE WHEN o.factura THEN round(v_base * 0.1494, 2) ELSE 0 END;
    v_pagar := v_base + v_iva;

    UPDATE ordenes_pedidos SET total = v_total WHERE orden_id = v_orden;

    -- Desglose de pagos: cuadra exactamente con total + rebaja + IVA.
    INSERT INTO pagos (orden_id, metodo_pago, monto, referencia, estado)
    VALUES (v_orden, o.metodo1,
            COALESCE(o.monto1, v_pagar),
            CASE WHEN o.monto1 IS NULL THEN NULL ELSE 'REF-' || o.etiqueta || '-1' END,
            'ACTIVO');

    IF o.metodo2 IS NOT NULL THEN
      IF o.monto1 IS NULL OR o.monto1 >= v_pagar THEN
        RAISE EXCEPTION 'O%: pago dividido inválido (%)', o.etiqueta, v_pagar;
      END IF;
      INSERT INTO pagos (orden_id, metodo_pago, monto, referencia, estado)
      VALUES (v_orden, o.metodo2, round(v_pagar - o.monto1, 2),
              'REF-' || o.etiqueta || '-2', 'ACTIVO');
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 4. Cobro: descuento de stock + kardex, igual que _aplicarCobro
--    (solo para las órdenes PAGADAS y para la DEVUELTA, que repone).
--    Se recorre en orden cronológico para que stock_resultante sea coherente.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  o     record;
  d     record;
  v_new numeric(12,3);
BEGIN
  FOR o IN
    SELECT t.orden_id, t.etiqueta, t.estado, t.fecha
      FROM tmp_ordenes t
     WHERE t.estado IN ('PAGADO', 'DEVUELTO')
     ORDER BY t.fecha
  LOOP
    FOR d IN
      SELECT dd.producto_id, dd.cantidad
        FROM detalles_ordenes_pedidos dd
       WHERE dd.orden_id = o.orden_id AND dd.estado <> 'ELIMINADO'
       ORDER BY dd.producto_id
    LOOP
      -- VENTA: descuenta y marca AGOTADO al llegar a 0.
      UPDATE productos
         SET stock = stock - d.cantidad,
             estado = CASE WHEN stock - d.cantidad <= 0 AND estado = 'DISPONIBLE'
                           THEN 'AGOTADO'::estado_producto ELSE estado END
       WHERE producto_id = d.producto_id AND stock >= d.cantidad
      RETURNING stock INTO v_new;

      IF v_new IS NULL THEN
        RAISE EXCEPTION 'O%: stock insuficiente del producto %',
                        o.etiqueta, d.producto_id;
      END IF;

      INSERT INTO movimientos_stock
        (producto_id, cantidad, motivo, stock_resultante, orden_id)
      VALUES (d.producto_id, -d.cantidad, 'VENTA', v_new, o.orden_id);

      -- DEVUELTO: se repone y se revierte el AGOTADO (como _revertirCobro).
      IF o.estado = 'DEVUELTO' THEN
        UPDATE productos
           SET stock = stock + d.cantidad,
               estado = CASE WHEN estado = 'AGOTADO'
                             THEN 'DISPONIBLE'::estado_producto ELSE estado END
         WHERE producto_id = d.producto_id
        RETURNING stock INTO v_new;

        INSERT INTO movimientos_stock
          (producto_id, cantidad, motivo, stock_resultante, orden_id)
        VALUES (d.producto_id, d.cantidad, 'DEVOLUCION', v_new, o.orden_id);
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- Variantes «Único» alineadas con el stock final: el cobro de arriba solo
-- descuenta `productos`, y el invariante es que la suma de las variantes
-- vivas coincide con el stock del producto (la API lo mantiene en cada
-- operación; aquí se cierra de una vez tras los cobros).
UPDATE producto_variantes v
   SET stock = p.stock
  FROM productos p
 WHERE p.producto_id = v.producto_id
   AND v.color_id IS NULL
   AND v.stock IS DISTINCT FROM p.stock;

-- ---------------------------------------------------------------------
-- 5. Facturas: solo de órdenes PAGADAS y una sola por orden.
--    subtotal = total de la orden, rebaja e IVA copiados de la orden.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  o       record;
  v_total numeric(10,2);
  v_reb   numeric(10,2);
  v_iva   numeric(10,2);
BEGIN
  FOR o IN
    SELECT t.orden_id, t.etiqueta, t.fecha, t.ci_cliente, t.nombre_emp,
           t.apellido_emp, t.rebaja, t.factura
      FROM tmp_ordenes t
     WHERE t.estado = 'PAGADO'
       AND t.etiqueta IN ('O02', 'O03', 'O07', 'O08', 'O11')
  LOOP
    SELECT total, rebaja,
           CASE WHEN (SELECT factura FROM ordenes_pedidos WHERE orden_id = o.orden_id)
                THEN round((total - rebaja) * 0.1494, 2) ELSE 0 END
      INTO v_total, v_reb, v_iva
      FROM ordenes_pedidos WHERE orden_id = o.orden_id;

    INSERT INTO facturas
      (fecha_factura, empleado_id, cliente_id, orden_id,
       subtotal, rebaja, iva, estado)
    SELECT o.fecha, em.empleado_id, cl.cliente_id, o.orden_id,
           v_total, v_reb, v_iva,
           -- O08 queda ANULADA para poder probar el filtro de facturas.
           CASE WHEN o.etiqueta = 'O08' THEN 'ANULADA' ELSE 'EMITIDA' END
             ::estado_factura
      FROM clientes cl
      JOIN empleados em ON em.nombre_empleado = o.nombre_emp
                       AND em.apellido       = o.apellido_emp
     WHERE cl.ci = o.ci_cliente;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 6. Cotizaciones (no tocan stock)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  c      record;
  d      record;
  v_cot  bigint;
  v_total numeric(10,2);
BEGIN
  FOR c IN
    SELECT * FROM (VALUES
      ('C01', '2026-09-30 10:00:00-04', '6845123', 'Juan',   'Pérez',      'VIGENTE'),
      ('C02', '2026-10-04 15:30:00-04', '7123456', 'María',  'López',      'ACEPTADA'),
      ('C03', '2026-10-07 09:45:00-04', '8123456', 'Carlos', 'Rodríguez',  'RECHAZADA')
    ) AS t(etiqueta, fecha, ci, nom, ape, estado)
  LOOP
    INSERT INTO cotizaciones
      (fecha_cotizacion, cliente_id, nombre_cliente, empleado_id, total, estado)
    SELECT c.fecha::timestamptz, cl.cliente_id, cl.nombre_cliente || ' ' || cl.apellido,
           em.empleado_id, 0, c.estado::estado_cotizacion
      FROM clientes cl
      JOIN empleados em ON em.nombre_empleado = c.nom AND em.apellido = c.ape
     WHERE cl.ci = c.ci
    RETURNING cotizacion_id INTO v_cot;

    FOR d IN
      SELECT p.producto_id, p.nombre_producto, p.imagen, p.unidad,
             p.precio_venta, t.cantidad, v.variante_id
        FROM (VALUES ('C01', 'BEB-001', 20.000),
                     ('C01', 'SNK-001', 10.000),
                     ('C02', 'PAN-003',  1.000),
                     ('C02', 'FRU-001',  4.000),
                     ('C03', 'LIM-001',  8.000),
                     ('C03', 'BEB-002',  6.000)) AS t(etiqueta, codigo, cantidad)
          JOIN productos p ON p.codigo = t.codigo
          JOIN producto_variantes v ON v.producto_id = p.producto_id
                                   AND v.color_id IS NULL
         WHERE t.etiqueta = c.etiqueta
    LOOP
      INSERT INTO detalles_cotizaciones
        (cotizacion_id, producto_id, nombre_producto, imagen, unidad,
         cantidad, precio_venta, monto_total, variante_id)
      VALUES (v_cot, d.producto_id, d.nombre_producto, d.imagen, d.unidad,
              d.cantidad, d.precio_venta, round(d.cantidad * d.precio_venta, 2),
              d.variante_id);
    END LOOP;

    SELECT COALESCE(sum(monto_total), 0) INTO v_total
      FROM detalles_cotizaciones WHERE cotizacion_id = v_cot;
    UPDATE cotizaciones SET total = v_total WHERE cotizacion_id = v_cot;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 7. Ajustes del sistema (claves documentadas en README/ajuste_usecases)
-- ---------------------------------------------------------------------
INSERT INTO ajustes (clave, valor) VALUES
  ('nombreTienda',        'Mi Tienda de Prueba'),
  ('tipoPagoPorDefecto',  'EFECTIVO'),
  ('ordenCatalogo',       'destacados'),
  ('stockMinimo',         '5'),
  ('diasVencimiento',     '90'),
  ('porPagina',           '10')
ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor;

-- ---------------------------------------------------------------------
-- 8. Auditoría de muestra
-- ---------------------------------------------------------------------
INSERT INTO auditoria
  (fecha, usuario_id, nombre_usuario, rol, accion, exitoso, entidad, resumen)
SELECT now() - (v.horas || ' hours')::interval, u.usuario_id, u.nombre_usuario,
       r.nombre, v.accion, v.exitoso, v.entidad, v.resumen
  FROM (VALUES
    (  2, 'LOGIN',         true,  NULL,        'Sesión iniciada correctamente'),
    (  6, 'CREAR_PRODUCTO', true,  'productos', 'Alta de "Agua Mineral 600 ml"'),
    ( 26, 'LOGIN_FALLIDO', false, NULL,        'Contraseña incorrecta (3 intentos)'),
    ( 30, 'CREAR_ORDEN',   true,  'ordenes',   'Orden O01 creada en estado PENDIENTE'),
    ( 49, 'PAGAR_ORDEN',   true,  'ordenes',   'Orden O01 cobrada: stock descontado'),
    ( 70, 'CREAR_ORDEN',   true,  'ordenes',   'Orden O02 creada en estado PENDIENTE'),
    ( 66, 'EMITIR_FACTURA',true,  'facturas',  'Factura emitida para la orden O02'),
    ( 96, 'EDITAR_CLIENTE', true,  'clientes',  'Teléfono actualizado'),
    (118, 'CANCELAR_ORDEN',true,  'ordenes',   'Orden O06 cancelada por el cliente'),
    (130, 'LOGIN',         true,  NULL,        'Sesión iniciada correctamente')
  ) AS v(horas, accion, exitoso, entidad, resumen)
  CROSS JOIN LATERAL (
    SELECT usuario_id, nombre_usuario, rol_id FROM usuarios
     WHERE nombre_usuario = 'carlos_admin' LIMIT 1
  ) u
  JOIN roles r ON r.rol_id = u.rol_id
 ORDER BY 1 DESC;

COMMIT;

-- =====================================================================
-- Verificación: todo esto debe volver filas (y las cifras deben cuadrar)
-- =====================================================================

\echo '--- Catálogo sembrado ---'
SELECT (SELECT count(*) FROM categorias)      AS categorias,
       (SELECT count(*) FROM proveedores)     AS proveedores,
       (SELECT count(*) FROM presentaciones)  AS presentaciones,
       (SELECT count(*) FROM empleados)       AS empleados,
       (SELECT count(*) FROM clientes)        AS clientes,
       (SELECT count(*) FROM usuarios)        AS usuarios,
       (SELECT count(*) FROM productos)       AS productos;

\echo '--- Órdenes (total = suma de líneas; pagos = total - rebaja + IVA) ---'
SELECT o.orden_id              AS id,
       to_char(o.fecha_orden, 'YYYY-MM-DD') AS fecha,
       o.estado,
       o.total,
       o.rebaja,
       CASE WHEN o.factura THEN round((o.total - o.rebaja) * 0.1494, 2)
            ELSE 0 END         AS iva,
       (SELECT round(coalesce(sum(monto), 0), 2)
          FROM pagos p WHERE p.orden_id = o.orden_id) AS pagos,
       (SELECT count(*) FROM detalles_ordenes_pedidos d
         WHERE d.orden_id = o.orden_id) AS lineas
  FROM ordenes_pedidos o
 ORDER BY o.fecha_orden;

\echo '--- Cuadre contable (debe ser todo "OK") ---'
SELECT orden_id,
       CASE WHEN total = (SELECT round(coalesce(sum(monto_total), 0), 2)
                            FROM detalles_ordenes_pedidos d
                           WHERE d.orden_id = o.orden_id)
            THEN 'OK' ELSE 'DESDCUADRE total/lineas' END AS cuadre_lineas,
       CASE WHEN abs((SELECT round(coalesce(sum(monto), 0), 2)
                        FROM pagos p WHERE p.orden_id = o.orden_id)
                     - (total - rebaja
                        + CASE WHEN factura
                               THEN round((total - rebaja) * 0.1494, 2)
                               ELSE 0 END)) < 0.01
            THEN 'OK' ELSE 'DESDCUADRE pagos' END AS cuadre_pagos
  FROM ordenes_pedidos o
 ORDER BY orden_id;

\echo '--- Stock actual y kardex (nunca negativo) ---'
SELECT codigo, nombre_producto, unidad, stock, stock_minimo, estado
  FROM productos
 ORDER BY estado, codigo;

\echo '--- Variantes «Único» (su stock debe cuadrar con el producto) ---'
SELECT p.codigo,
       CASE WHEN p.stock = coalesce((SELECT sum(v.stock)
                                       FROM producto_variantes v
                                      WHERE v.producto_id = p.producto_id
                                        AND v.estado <> 'ELIMINADO'), 0)
            THEN 'OK' ELSE 'DESDCUADRE variantes' END AS cuadre
  FROM productos p
 ORDER BY p.codigo;

SELECT motivo, count(*) AS movs
  FROM movimientos_stock
 GROUP BY motivo
 ORDER BY motivo;

\echo '--- Informe de ventas (lo que pinta la pantalla Reportes) ---'
SELECT to_char(o.fecha_orden, 'YYYY-MM')      AS mes,
       count(DISTINCT o.orden_id)             AS ordenes_pagadas,
       sum(d.monto_total)                     AS vendido,
       sum(d.cantidad)                        AS unidades
  FROM ordenes_pedidos o
  JOIN detalles_ordenes_pedidos d ON d.orden_id = o.orden_id
 WHERE o.estado = 'PAGADO' AND d.estado <> 'ELIMINADO'
 GROUP BY 1
 ORDER BY 1;

\echo '--- Facturas y cotizaciones ---'
SELECT factura_numero AS numero, orden_id, estado, subtotal, rebaja, iva,
       subtotal - rebaja + iva AS total
  FROM facturas ORDER BY factura_numero;

SELECT cotizacion_id AS id, estado, total FROM cotizaciones ORDER BY cotizacion_id;
