-- ============================================================================
-- 01_Esquema_y_Datos.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido:
--   * Creación de la base de datos.
--   * Todas las sentencias CREATE TABLE (estructura completa).
--   * ALTER TABLE e índices.
--   * Todas las sentencias INSERT INTO (datos de ejemplo).
-- ORDEN DE EJECUCIÓN: este archivo SIEMPRE se ejecuta primero.
-- ============================================================================

DROP DATABASE IF EXISTS proyecto;
CREATE DATABASE proyecto;
USE proyecto;


-- ============================================================
-- TABLAS PRINCIPALES
-- ============================================================

CREATE TABLE categorias (
    id_categoria    INT             NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(150)    NOT NULL,
    descripcion     TEXT            NULL,
    total_productos INT             NOT NULL DEFAULT 0,
    PRIMARY KEY (id_categoria),
    UNIQUE KEY uq_categoria_nombre (nombre)
);


CREATE TABLE proveedores (
    id_proveedor       INT             NOT NULL AUTO_INCREMENT,
    nombre             VARCHAR(200)    NOT NULL,
    email_contacto     VARCHAR(255)    NULL,
    telefono_contacto  VARCHAR(30)     NULL,
    PRIMARY KEY (id_proveedor),
    UNIQUE KEY uq_proveedor_email (email_contacto)
);


CREATE TABLE clientes (
    id_cliente         INT             NOT NULL AUTO_INCREMENT,
    nombre             VARCHAR(100)    NOT NULL,
    apellido           VARCHAR(100)    NOT NULL,
    email              VARCHAR(255)    NOT NULL,
    contrasena         VARCHAR(255)    NOT NULL,
    direccion_envio    TEXT            NULL,
    fecha_registro     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_nacimiento   DATE            NULL,
    total_gastado      DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    ultima_compra      DATETIME        NULL,
    id_referido_por    INT             NULL,
    PRIMARY KEY (id_cliente),
    UNIQUE KEY uq_cliente_email (email),
    CONSTRAINT fk_cliente_referido
        FOREIGN KEY (id_referido_por)
        REFERENCES clientes (id_cliente)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);


CREATE TABLE productos (
    id_producto        INT             NOT NULL AUTO_INCREMENT,
    nombre             VARCHAR(255)    NOT NULL,
    descripcion        TEXT            NULL,
    precio             DECIMAL(10,2)   NOT NULL,
    costo              DECIMAL(10,2)   NOT NULL,
    stock              INT             NOT NULL DEFAULT 0,
    stock_minimo       INT             NOT NULL DEFAULT 5,
    sku                VARCHAR(100)    NOT NULL,
    fecha_creacion     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_modificacion DATETIME        NULL,
    activo             TINYINT(1)      NOT NULL DEFAULT 1,
    id_categoria       INT             NULL,
    id_proveedor       INT             NULL,
    peso_kg            DECIMAL(8,2)    NULL DEFAULT 0.00,
    PRIMARY KEY (id_producto),
    UNIQUE KEY uq_producto_nombre (nombre),
    UNIQUE KEY uq_producto_sku (sku),
    CONSTRAINT fk_producto_categoria
        FOREIGN KEY (id_categoria)
        REFERENCES categorias (id_categoria)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    CONSTRAINT fk_producto_proveedor
        FOREIGN KEY (id_proveedor)
        REFERENCES proveedores (id_proveedor)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    CONSTRAINT chk_precio_positivo   CHECK (precio > 0),
    CONSTRAINT chk_costo_positivo    CHECK (costo >= 0),
    CONSTRAINT chk_stock_no_negativo CHECK (stock >= 0)
);


CREATE TABLE ventas (
    id_venta     INT          NOT NULL AUTO_INCREMENT,
    fecha_venta  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado       ENUM(
                    'Pendiente de Pago',
                    'Procesando',
                    'Enviado',
                    'Entregado',
                    'Cancelado',
                    'Devuelto'
                 ) NOT NULL DEFAULT 'Pendiente de Pago',
    total        DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    id_cliente   INT           NOT NULL,
    id_sucursal  INT           NULL,
    notas        TEXT          NULL,
    PRIMARY KEY (id_venta),
    CONSTRAINT fk_venta_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente)
        ON DELETE RESTRICT
        ON UPDATE CASCADE
);


CREATE TABLE detalle_ventas (
    id_detalle                INT           NOT NULL AUTO_INCREMENT,
    cantidad                  INT           NOT NULL,
    precio_unitario_congelado DECIMAL(10,2) NOT NULL,
    id_venta                  INT           NOT NULL,
    id_producto               INT           NOT NULL,
    PRIMARY KEY (id_detalle),
    CONSTRAINT fk_detalle_venta
        FOREIGN KEY (id_venta)
        REFERENCES ventas (id_venta)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_detalle_producto
        FOREIGN KEY (id_producto)
        REFERENCES productos (id_producto)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    CONSTRAINT chk_cantidad_positiva   CHECK (cantidad > 0),
    CONSTRAINT chk_precio_congelado_ok CHECK (precio_unitario_congelado > 0)
);


-- ============================================================
-- TABLAS DE AUDITORÍA Y SOPORTE
-- (necesarias para triggers, eventos y seguridad)
-- ============================================================

CREATE TABLE auditoria_precios (
    id_auditoria    INT           NOT NULL AUTO_INCREMENT,
    id_producto     INT           NOT NULL,
    precio_anterior DECIMAL(10,2) NOT NULL,
    precio_nuevo    DECIMAL(10,2) NOT NULL,
    fecha_cambio    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_cambio  VARCHAR(100)  NULL,
    PRIMARY KEY (id_auditoria)
);


CREATE TABLE auditoria_clientes (
    id_auditoria   INT           NOT NULL AUTO_INCREMENT,
    id_cliente     INT           NOT NULL,
    accion         VARCHAR(50)   NOT NULL,
    fecha_accion   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    detalle        TEXT          NULL,
    PRIMARY KEY (id_auditoria)
);


CREATE TABLE auditoria_estados_venta (
    id_auditoria    INT           NOT NULL AUTO_INCREMENT,
    id_venta        INT           NOT NULL,
    estado_anterior VARCHAR(50)   NULL,
    estado_nuevo    VARCHAR(50)   NOT NULL,
    fecha_cambio    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_auditoria)
);


CREATE TABLE alertas_stock (
    id_alerta      INT           NOT NULL AUTO_INCREMENT,
    id_producto    INT           NOT NULL,
    stock_actual   INT           NOT NULL,
    stock_minimo   INT           NOT NULL,
    fecha_alerta   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelta       TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (id_alerta)
);


CREATE TABLE ventas_archivadas (
    id_venta        INT           NOT NULL,
    id_cliente      INT           NOT NULL,
    total           DECIMAL(12,2) NOT NULL,
    estado          VARCHAR(50)   NOT NULL,
    fecha_venta     DATETIME      NOT NULL,
    fecha_archivado TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_venta)
);


CREATE TABLE auditoria_permisos (
    id_auditoria   INT           NOT NULL AUTO_INCREMENT,
    usuario        VARCHAR(100)  NOT NULL,
    accion         VARCHAR(255)  NOT NULL,
    fecha_cambio   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_auditoria)
);


CREATE TABLE resumen_ventas_diario (
    id_resumen     INT           NOT NULL AUTO_INCREMENT,
    fecha          DATE          NOT NULL,
    total_ventas   DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    num_ordenes    INT           NOT NULL DEFAULT 0,
    num_clientes   INT           NOT NULL DEFAULT 0,
    PRIMARY KEY (id_resumen),
    UNIQUE KEY uq_resumen_fecha (fecha)
);


CREATE TABLE kpis_mensuales (
    id_kpi          INT           NOT NULL AUTO_INCREMENT,
    anio            INT           NOT NULL,
    mes             INT           NOT NULL,
    total_ingresos  DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    num_ventas      INT           NOT NULL DEFAULT 0,
    nuevos_clientes INT           NOT NULL DEFAULT 0,
    ticket_promedio DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    fecha_calculo   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_kpi),
    UNIQUE KEY uq_kpi_periodo (anio, mes)
);


CREATE TABLE resenas_productos (
    id_resena      INT           NOT NULL AUTO_INCREMENT,
    id_producto    INT           NOT NULL,
    id_cliente     INT           NOT NULL,
    calificacion   TINYINT       NOT NULL,
    comentario     TEXT          NULL,
    fecha_resena   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_resena),
    CONSTRAINT chk_calificacion CHECK (calificacion BETWEEN 1 AND 5),
    CONSTRAINT fk_resena_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE,
    CONSTRAINT fk_resena_cliente  FOREIGN KEY (id_cliente)  REFERENCES clientes(id_cliente)  ON DELETE CASCADE
);


CREATE TABLE carritos (
    id_carrito     INT           NOT NULL AUTO_INCREMENT,
    id_cliente     INT           NOT NULL,
    id_producto    INT           NOT NULL,
    cantidad       INT           NOT NULL DEFAULT 1,
    fecha_agregado TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_carrito),
    CONSTRAINT fk_carrito_cliente  FOREIGN KEY (id_cliente)  REFERENCES clientes(id_cliente)  ON DELETE CASCADE,
    CONSTRAINT fk_carrito_producto FOREIGN KEY (id_producto) REFERENCES productos(id_producto) ON DELETE CASCADE
);


CREATE TABLE lista_reabastecimiento (
    id_item        INT           NOT NULL AUTO_INCREMENT,
    id_producto    INT           NOT NULL,
    stock_actual   INT           NOT NULL,
    stock_minimo   INT           NOT NULL,
    fecha_lista    DATE          NOT NULL,
    PRIMARY KEY (id_item)
);


CREATE TABLE ranking_productos (
    id_ranking           INT           NOT NULL AUTO_INCREMENT,
    id_producto          INT           NOT NULL,
    total_vendido        INT           NOT NULL DEFAULT 0,
    ingresos_total       DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    posicion             INT           NOT NULL DEFAULT 0,
    ultima_actualizacion TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id_ranking),
    UNIQUE KEY uq_ranking_producto (id_producto)
);


CREATE TABLE log_tamano_db (
    id_log         INT           NOT NULL AUTO_INCREMENT,
    fecha_log      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tamano_mb      DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (id_log)
);


CREATE TABLE alertas_fraude (
    id_alerta      INT           NOT NULL AUTO_INCREMENT,
    id_cliente     INT           NULL,
    descripcion    TEXT          NOT NULL,
    fecha_alerta   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelta       TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (id_alerta)
);


CREATE TABLE sucursales (
    id_sucursal    INT           NOT NULL AUTO_INCREMENT,
    nombre         VARCHAR(150)  NOT NULL,
    ciudad         VARCHAR(100)  NULL,
    PRIMARY KEY (id_sucursal)
);


-- La FK de ventas hacia sucursales se agrega después de crear ambas tablas.
ALTER TABLE ventas
    ADD CONSTRAINT fk_venta_sucursal
    FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
    ON DELETE SET NULL ON UPDATE CASCADE;


CREATE TABLE usuarios_sistema (
    id_usuario     INT           NOT NULL AUTO_INCREMENT,
    username       VARCHAR(100)  NOT NULL,
    id_sucursal    INT           NULL,
    PRIMARY KEY (id_usuario),
    UNIQUE KEY uq_username (username),
    CONSTRAINT fk_usuario_sucursal FOREIGN KEY (id_sucursal) REFERENCES sucursales(id_sucursal)
);


-- Tabla de auditoría de inicios de sesión fallidos (requisito de seguridad #20)
CREATE TABLE IF NOT EXISTS log_intentos_fallidos (
    id_log        INT          NOT NULL AUTO_INCREMENT,
    usuario       VARCHAR(100) NOT NULL,
    host_origen   VARCHAR(100) NOT NULL,
    fecha_intento TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_log)
) ENGINE=InnoDB;


-- ============================================================
-- ÍNDICES PARA OPTIMIZACIÓN DE CONSULTAS
-- ============================================================

CREATE INDEX idx_productos_categoria ON productos (id_categoria);
CREATE INDEX idx_productos_proveedor ON productos (id_proveedor);
CREATE INDEX idx_productos_activo    ON productos (activo);
CREATE INDEX idx_ventas_cliente      ON ventas (id_cliente);
CREATE INDEX idx_ventas_fecha        ON ventas (fecha_venta);
CREATE INDEX idx_ventas_estado       ON ventas (estado);
CREATE INDEX idx_detalle_venta       ON detalle_ventas (id_venta);
CREATE INDEX idx_detalle_producto    ON detalle_ventas (id_producto);
CREATE INDEX idx_clientes_email      ON clientes (email);


-- ============================================================
-- INSERCIÓN DE DATOS DE EJEMPLO
-- ============================================================

INSERT INTO sucursales (nombre, ciudad) VALUES
    ('Sucursal Central', 'Bogotá'),
    ('Sucursal Norte', 'Medellín');


INSERT INTO categorias (nombre, descripcion) VALUES
    ('Electrónica',   'Dispositivos electrónicos y accesorios'),
    ('Ropa',          'Prendas de vestir para todas las edades'),
    ('Hogar',         'Artículos para el hogar y decoración'),
    ('General',       'Categoría por defecto');


INSERT INTO proveedores (nombre, email_contacto, telefono_contacto) VALUES
    ('TechSupply S.A.',   'ventas@techsupply.com',  '+57 310 1234567'),
    ('ModaTotal Ltda.',   'pedidos@modatotal.com',  '+57 311 7654321'),
    ('HomeGoods Corp.',   'contacto@homegoods.com', '+57 312 9876543');


INSERT INTO clientes (nombre, apellido, email, contrasena, direccion_envio, fecha_nacimiento) VALUES
    ('Carlos',    'Ramírez',  'carlos@email.com',   '$2b$12$examplehash1', 'Calle 10 #5-20, Bogotá',    '1990-03-15'),
    ('María',     'González', 'maria@email.com',    '$2b$12$examplehash2', 'Carrera 7 #80-45, Medellín','1985-07-22'),
    ('Andrés',    'López',    'andres@email.com',   '$2b$12$examplehash3', 'Av. 68 #30-15, Bogotá',     '2000-11-08'),
    ('Lucía',     'Martínez', 'lucia@email.com',    '$2b$12$examplehash4', 'Calle 50 #20-33, Cali',     '1995-01-30'),
    ('Roberto',   'Pérez',    'roberto@email.com',  '$2b$12$examplehash5', 'Carrera 15 #90-10, Bogotá', '1978-09-05');


INSERT INTO productos (nombre, descripcion, precio, costo, stock, stock_minimo, sku, id_categoria, id_proveedor, peso_kg) VALUES
    ('Laptop ProMax 15"',     'Laptop de alto rendimiento con 16GB RAM',          2500000.00, 1800000.00, 20, 5,  'TECH-LAP-001', 1, 1, 2.5),
    ('Smartphone Galaxy X',   'Teléfono inteligente 5G, 128GB',                   1200000.00,  850000.00, 35, 8,  'TECH-PHN-002', 1, 1, 0.2),
    ('Camiseta Clásica',      'Algodón 100%, disponible en varios colores',         45000.00,   18000.00, 100, 20, 'ROPA-CAM-003', 2, 2, 0.2),
    ('Silla Ergonómica',      'Silla de oficina con soporte lumbar',               350000.00,  200000.00, 15, 3,  'HOGA-SIL-004', 3, 3, 8.0),
    ('Audífonos Bluetooth',   'Audífonos inalámbricos con cancelación de ruido',   180000.00,   95000.00, 50, 10, 'TECH-AUD-005', 1, 1, 0.3),
    ('Pantalón Deportivo',    'Ideal para ejercicio, tela transpirable',            65000.00,   28000.00, 80, 15, 'ROPA-PAN-006', 2, 2, 0.4),
    ('Lámpara LED Escritorio','Luz ajustable con puerto USB',                       85000.00,   40000.00, 3,  5,  'HOGA-LAM-007', 3, 3, 0.8);


INSERT INTO ventas (id_cliente, estado, id_sucursal) VALUES
    (1, 'Entregado',  1),
    (2, 'Enviado',    2),
    (1, 'Procesando', 1),
    (3, 'Entregado',  1),
    (4, 'Pendiente de Pago', 2);


INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
    (1, 1, 1, 2500000.00),
    (1, 5, 1,  180000.00);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
    (2, 3, 2,  45000.00),
    (2, 6, 1,  65000.00);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
    (3, 2, 1, 1200000.00);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
    (4, 4, 1, 350000.00),
    (4, 7, 1,  85000.00);

INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado) VALUES
    (5, 3, 3, 45000.00);


-- Totales de cada venta (calculados a partir del detalle)
UPDATE ventas SET total = 2680000.00 WHERE id_venta = 1;
UPDATE ventas SET total =  155000.00 WHERE id_venta = 2;
UPDATE ventas SET total = 1200000.00 WHERE id_venta = 3;
UPDATE ventas SET total =  435000.00 WHERE id_venta = 4;
UPDATE ventas SET total =  135000.00 WHERE id_venta = 5;


-- Gasto total acumulado por cliente
UPDATE clientes SET total_gastado = 3880000.00 WHERE id_cliente = 1;
UPDATE clientes SET total_gastado =  155000.00 WHERE id_cliente = 2;
UPDATE clientes SET total_gastado =  435000.00 WHERE id_cliente = 3;
UPDATE clientes SET total_gastado =  135000.00 WHERE id_cliente = 4;


-- ============================================================
-- CONSULTAS DE VERIFICACIÓN DEL ESQUEMA Y LOS DATOS
-- ============================================================

-- Conteo de registros por tabla principal
SELECT 'categorias'     AS tabla, COUNT(*) AS registros FROM categorias    UNION ALL
SELECT 'proveedores',             COUNT(*)               FROM proveedores   UNION ALL
SELECT 'clientes',                COUNT(*)               FROM clientes      UNION ALL
SELECT 'productos',               COUNT(*)               FROM productos     UNION ALL
SELECT 'ventas',                  COUNT(*)               FROM ventas        UNION ALL
SELECT 'detalle_ventas',          COUNT(*)               FROM detalle_ventas;


-- Verificación de las relaciones (claves foráneas) de la base de datos
SELECT
    TABLE_NAME             AS 'Tabla',
    COLUMN_NAME            AS 'Columna (FK)',
    REFERENCED_TABLE_NAME  AS 'Tabla Referenciada',
    REFERENCED_COLUMN_NAME AS 'Columna Referenciada',
    CONSTRAINT_NAME        AS 'Nombre de la Restricción'
FROM
    INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE
    TABLE_SCHEMA = 'proyecto'
    AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY
    TABLE_NAME, COLUMN_NAME;
