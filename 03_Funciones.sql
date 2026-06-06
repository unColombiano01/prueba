-- ============================================================================
-- 03_Funciones.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido: las 20 funciones definidas por el usuario (UDFs).
-- ORDEN DE EJECUCIÓN: ejecutar después de 01_Esquema_y_Datos.sql.
-- ============================================================================

USE proyecto;
DELIMITER $$


-- 1. fn_CalcularTotalVenta: calcula el monto total de una venta específica.
DROP FUNCTION IF EXISTS fn_CalcularTotalVenta$$
CREATE FUNCTION fn_CalcularTotalVenta(p_id_venta INT)
RETURNS DECIMAL(12,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0.00)
    INTO v_total
    FROM detalle_ventas
    WHERE id_venta = p_id_venta;

    RETURN v_total;
END$$


-- 2. fn_VerificarDisponibilidadStock: valida si hay stock suficiente para un producto.
DROP FUNCTION IF EXISTS fn_VerificarDisponibilidadStock$$
CREATE FUNCTION fn_VerificarDisponibilidadStock(
    p_id_producto INT,
    p_cantidad_solicitada INT
)
RETURNS TINYINT(1)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_stock_actual INT DEFAULT 0;

    SELECT stock
    INTO v_stock_actual
    FROM productos
    WHERE id_producto = p_id_producto;

    RETURN IF(v_stock_actual >= p_cantidad_solicitada, 1, 0);
END$$


-- 3. fn_ObtenerPrecioProducto: devuelve el precio actual de un producto.
DROP FUNCTION IF EXISTS fn_ObtenerPrecioProducto$$
CREATE FUNCTION fn_ObtenerPrecioProducto(p_id_producto INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_precio DECIMAL(10,2) DEFAULT 0.00;

    SELECT precio
    INTO v_precio
    FROM productos
    WHERE id_producto = p_id_producto
      AND activo = 1;    -- Solo productos activos

    RETURN v_precio;
END$$


-- 4. fn_CalcularEdadCliente: calcula la edad de un cliente a partir de su fecha de nacimiento.
DROP FUNCTION IF EXISTS fn_CalcularEdadCliente$$
CREATE FUNCTION fn_CalcularEdadCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_fecha_nac DATE;
    DECLARE v_edad INT DEFAULT 0;

    SELECT fecha_nacimiento
    INTO v_fecha_nac
    FROM clientes
    WHERE id_cliente = p_id_cliente;

    IF v_fecha_nac IS NULL THEN
        RETURN -1;
    END IF;

    SET v_edad = TIMESTAMPDIFF(YEAR, v_fecha_nac, CURDATE());

    RETURN v_edad;
END$$


-- 5. fn_FormatearNombreCompleto: devuelve el nombre del cliente en un formato estandarizado.
DROP FUNCTION IF EXISTS fn_FormatearNombreCompleto$$
CREATE FUNCTION fn_FormatearNombreCompleto(p_id_cliente INT)
RETURNS VARCHAR(255)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_nombre   VARCHAR(100);
    DECLARE v_apellido VARCHAR(100);

    SELECT nombre, apellido
    INTO v_nombre, v_apellido
    FROM clientes
    WHERE id_cliente = p_id_cliente;

    IF v_nombre IS NULL THEN
        RETURN 'Cliente no encontrado';
    END IF;

    RETURN CONCAT(UPPER(v_apellido), ', ', v_nombre);
END$$


-- 6. fn_EsClienteNuevo: VERDADERO si el cliente realizó su primera compra en los últimos 30 días.
DROP FUNCTION IF EXISTS fn_EsClienteNuevo$$
CREATE FUNCTION fn_EsClienteNuevo(p_id_cliente INT)
RETURNS TINYINT(1)
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_primera_compra DATETIME;

    SELECT MIN(fecha_venta)
    INTO v_primera_compra
    FROM ventas
    WHERE id_cliente = p_id_cliente
      AND estado NOT IN ('Cancelado', 'Pendiente de Pago');

    IF v_primera_compra IS NULL THEN
        RETURN 0;
    END IF;

    RETURN IF(v_primera_compra >= DATE_SUB(NOW(), INTERVAL 30 DAY), 1, 0);
END$$


-- 7. fn_CalcularCostoEnvio: calcula el costo de envío según el peso total de la venta.
DROP FUNCTION IF EXISTS fn_CalcularCostoEnvio$$
CREATE FUNCTION fn_CalcularCostoEnvio(p_id_venta INT)
RETURNS DECIMAL(10,2)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_peso_total DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_costo_envio DECIMAL(10,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(p.peso_kg * dv.cantidad), 0)
    INTO v_peso_total
    FROM detalle_ventas dv
    INNER JOIN productos p ON dv.id_producto = p.id_producto
    WHERE dv.id_venta = p_id_venta;

    IF v_peso_total <= 1 THEN
        SET v_costo_envio = 5000.00;
    ELSEIF v_peso_total <= 5 THEN
        SET v_costo_envio = 10000.00;
    ELSEIF v_peso_total <= 20 THEN
        SET v_costo_envio = 20000.00;
    ELSE
        SET v_costo_envio = 35000.00;
    END IF;

    RETURN v_costo_envio;
END$$


-- 8. fn_AplicarDescuento: aplica un porcentaje de descuento a un monto dado.
DROP FUNCTION IF EXISTS fn_AplicarDescuento$$
CREATE FUNCTION fn_AplicarDescuento(
    p_monto        DECIMAL(12,2),
    p_porcentaje   DECIMAL(5,2)
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_porcentaje < 0 OR p_porcentaje > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El porcentaje debe estar entre 0 y 100';
    END IF;

    RETURN ROUND(p_monto * (1 - p_porcentaje / 100), 2);
END$$


-- 9. fn_ObtenerUltimaFechaCompra: devuelve la fecha de la última compra de un cliente.
DROP FUNCTION IF EXISTS fn_ObtenerUltimaFechaCompra$$
CREATE FUNCTION fn_ObtenerUltimaFechaCompra(p_id_cliente INT)
RETURNS DATETIME
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_ultima_fecha DATETIME;

    SELECT MAX(fecha_venta)
    INTO v_ultima_fecha
    FROM ventas
    WHERE id_cliente = p_id_cliente
      AND estado NOT IN ('Cancelado', 'Pendiente de Pago');

    RETURN v_ultima_fecha;
END$$


-- 10. fn_ValidarFormatoEmail: comprueba si una cadena tiene formato de correo válido.
DROP FUNCTION IF EXISTS fn_ValidarFormatoEmail$$
CREATE FUNCTION fn_ValidarFormatoEmail(p_email VARCHAR(255))
RETURNS TINYINT(1)
DETERMINISTIC
NO SQL
BEGIN
    RETURN p_email REGEXP '^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$';
END$$


-- 11. fn_ObtenerNombreCategoria: devuelve el nombre de la categoría a partir del ID de un producto.
DROP FUNCTION IF EXISTS fn_ObtenerNombreCategoria$$
CREATE FUNCTION fn_ObtenerNombreCategoria(p_id_producto INT)
RETURNS VARCHAR(150)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_nombre_categoria VARCHAR(150);

    SELECT cat.nombre
    INTO v_nombre_categoria
    FROM productos p
    INNER JOIN categorias cat ON p.id_categoria = cat.id_categoria
    WHERE p.id_producto = p_id_producto;

    RETURN COALESCE(v_nombre_categoria, 'Sin categoría');
END$$


-- 12. fn_ContarVentasCliente: cuenta el número total de compras realizadas por un cliente.
DROP FUNCTION IF EXISTS fn_ContarVentasCliente$$
CREATE FUNCTION fn_ContarVentasCliente(p_id_cliente INT)
RETURNS INT
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_total_ventas INT DEFAULT 0;

    SELECT COUNT(id_venta)
    INTO v_total_ventas
    FROM ventas
    WHERE id_cliente = p_id_cliente
      AND estado NOT IN ('Cancelado', 'Pendiente de Pago');

    RETURN v_total_ventas;
END$$


-- 13. fn_CalcularDiasDesdeUltimaCompra: días transcurridos desde la última compra de un cliente.
DROP FUNCTION IF EXISTS fn_CalcularDiasDesdeUltimaCompra$$
CREATE FUNCTION fn_CalcularDiasDesdeUltimaCompra(p_id_cliente INT)
RETURNS INT
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_ultima_fecha DATETIME;

    SET v_ultima_fecha = fn_ObtenerUltimaFechaCompra(p_id_cliente);

    IF v_ultima_fecha IS NULL THEN
        RETURN -1;
    END IF;

    RETURN DATEDIFF(NOW(), v_ultima_fecha);
END$$


-- 14. fn_DeterminarEstadoLealtad: asigna estado de lealtad (Bronce, Plata, Oro) según el gasto total.
DROP FUNCTION IF EXISTS fn_DeterminarEstadoLealtad$$
CREATE FUNCTION fn_DeterminarEstadoLealtad(p_id_cliente INT)
RETURNS VARCHAR(20)
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_total_gastado DECIMAL(12,2) DEFAULT 0.00;

    SELECT COALESCE(SUM(total), 0)
    INTO v_total_gastado
    FROM ventas
    WHERE id_cliente = p_id_cliente
      AND estado NOT IN ('Cancelado', 'Pendiente de Pago');

    RETURN CASE
        WHEN v_total_gastado >= 2000000 THEN 'Oro'
        WHEN v_total_gastado >= 500000  THEN 'Plata'
        ELSE                                 'Bronce'
    END;
END$$


-- 15. fn_GenerarSKU: genera un código de producto (SKU) basado en su nombre y categoría.
DROP FUNCTION IF EXISTS fn_GenerarSKU$$
CREATE FUNCTION fn_GenerarSKU(
    p_nombre_producto  VARCHAR(255),
    p_nombre_categoria VARCHAR(150)
)
RETURNS VARCHAR(20)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_prefijo_cat  VARCHAR(3);
    DECLARE v_prefijo_prod VARCHAR(3);
    DECLARE v_numero       VARCHAR(3);

    SET v_prefijo_cat  = UPPER(LEFT(REPLACE(p_nombre_categoria, ' ', ''), 3));
    SET v_prefijo_prod = UPPER(LEFT(REPLACE(p_nombre_producto,  ' ', ''), 3));
    SET v_numero = LPAD(FLOOR(RAND() * 900) + 100, 3, '0');

    RETURN CONCAT(v_prefijo_cat, '-', v_prefijo_prod, '-', v_numero);
END$$


-- 16. fn_CalcularIVA: calcula el impuesto (IVA) sobre un subtotal.
DROP FUNCTION IF EXISTS fn_CalcularIVA$$
CREATE FUNCTION fn_CalcularIVA(
    p_subtotal     DECIMAL(12,2),
    p_tasa_iva_pct DECIMAL(5,2)    -- Ej: 19.00 para 19%
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
NO SQL
BEGIN
    IF p_tasa_iva_pct < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La tasa de IVA no puede ser negativa';
    END IF;

    RETURN ROUND(p_subtotal * (p_tasa_iva_pct / 100), 2);
END$$


-- 17. fn_ObtenerStockTotalPorCategoria: suma el stock de todos los productos de una categoría.
DROP FUNCTION IF EXISTS fn_ObtenerStockTotalPorCategoria$$
CREATE FUNCTION fn_ObtenerStockTotalPorCategoria(p_id_categoria INT)
RETURNS INT
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_stock_total INT DEFAULT 0;

    SELECT COALESCE(SUM(stock), 0)
    INTO v_stock_total
    FROM productos
    WHERE id_categoria = p_id_categoria
      AND activo = 1;

    RETURN v_stock_total;
END$$


-- 18. fn_EstimarFechaEntrega: estima la fecha de entrega según la ubicación del cliente.
DROP FUNCTION IF EXISTS fn_EstimarFechaEntrega$$
CREATE FUNCTION fn_EstimarFechaEntrega(p_id_venta INT)
RETURNS DATE
READS SQL DATA
NOT DETERMINISTIC
BEGIN
    DECLARE v_direccion    TEXT;
    DECLARE v_dias_entrega INT DEFAULT 5;
    DECLARE v_ciudad       VARCHAR(100);

    SELECT c.direccion_envio
    INTO v_direccion
    FROM ventas v
    INNER JOIN clientes c ON v.id_cliente = c.id_cliente
    WHERE v.id_venta = p_id_venta;

    IF v_direccion IS NULL THEN
        RETURN NULL;
    END IF;

    SET v_ciudad = TRIM(SUBSTRING_INDEX(v_direccion, ',', -1));

    IF v_ciudad IN ('Bogotá', 'Medellín', 'Cali', 'Barranquilla') THEN
        SET v_dias_entrega = 2;
    ELSE
        SET v_dias_entrega = 5;
    END IF;

    RETURN DATE_ADD(CURDATE(), INTERVAL v_dias_entrega DAY);
END$$


-- 19. fn_ConvertirMoneda: convierte un monto a otra moneda usando una tasa fija.
DROP FUNCTION IF EXISTS fn_ConvertirMoneda$$
CREATE FUNCTION fn_ConvertirMoneda(
    p_monto          DECIMAL(14,2),
    p_moneda_destino VARCHAR(3)
)
RETURNS DECIMAL(14,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_tasa DECIMAL(10,6) DEFAULT 1.000000;

    CASE UPPER(p_moneda_destino)
        WHEN 'USD' THEN SET v_tasa = 0.000238;
        WHEN 'EUR' THEN SET v_tasa = 0.000220;
        WHEN 'BRL' THEN SET v_tasa = 0.001190;
        WHEN 'COP' THEN SET v_tasa = 1.000000;
        ELSE
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Moneda no soportada. Use: USD, EUR, BRL, COP';
    END CASE;

    RETURN ROUND(p_monto * v_tasa, 2);
END$$


-- 20. fn_ValidarComplejidadContrasena: verifica que una contraseña cumpla criterios de seguridad.
DROP FUNCTION IF EXISTS fn_ValidarComplejidadContrasena$$
CREATE FUNCTION fn_ValidarComplejidadContrasena(p_contrasena VARCHAR(255))
RETURNS TINYINT(1)
DETERMINISTIC
NO SQL
BEGIN
    IF LENGTH(p_contrasena) < 8 THEN
        RETURN 0;
    END IF;

    IF p_contrasena NOT REGEXP '[A-Z]' THEN
        RETURN 0;
    END IF;

    IF p_contrasena NOT REGEXP '[a-z]' THEN
        RETURN 0;
    END IF;

    IF p_contrasena NOT REGEXP '[0-9]' THEN
        RETURN 0;
    END IF;

    IF p_contrasena NOT REGEXP '[!@#$%^&*()_+\\-=\\[\\]{};:\'"\\\\|,.<>\\/?]' THEN
        RETURN 0;
    END IF;

    RETURN 1;
END$$


DELIMITER ;


-- ============================================================
-- PRUEBAS DE LAS FUNCIONES
-- ============================================================

SELECT fn_CalcularTotalVenta(1) AS total_venta_1;
SELECT fn_VerificarDisponibilidadStock(1, 5) AS hay_stock;
SELECT fn_ObtenerPrecioProducto(2) AS precio_actual;
SELECT fn_CalcularEdadCliente(1) AS edad_cliente;
SELECT fn_FormatearNombreCompleto(2) AS nombre_formal;
SELECT fn_EsClienteNuevo(1) AS es_nuevo;
SELECT fn_CalcularCostoEnvio(1) AS costo_envio;
SELECT fn_AplicarDescuento(500000, 20) AS precio_con_descuento;
SELECT fn_ObtenerUltimaFechaCompra(1) AS ultima_compra;
SELECT fn_ValidarFormatoEmail('carlos@email.com') AS email_valido;
SELECT fn_ValidarFormatoEmail('correo_invalido')  AS email_invalido;
SELECT fn_ObtenerNombreCategoria(1) AS categoria;
SELECT fn_ContarVentasCliente(1) AS num_ventas;
SELECT fn_CalcularDiasDesdeUltimaCompra(1) AS dias;
SELECT fn_DeterminarEstadoLealtad(1) AS lealtad;
SELECT fn_GenerarSKU('Teclado Mecánico', 'Electrónica') AS nuevo_sku;
SELECT fn_CalcularIVA(1000000, 19) AS iva;
SELECT fn_ObtenerStockTotalPorCategoria(1) AS stock_total;
SELECT fn_EstimarFechaEntrega(1) AS fecha_entrega;
SELECT fn_ConvertirMoneda(500000, 'USD') AS en_dolares;
SELECT fn_ValidarComplejidadContrasena('abc123')          AS invalida;  -- 0
SELECT fn_ValidarComplejidadContrasena('MiClave#2024')    AS valida;    -- 1

-- Reporte combinado usando varias funciones
SELECT
    c.id_cliente,
    fn_FormatearNombreCompleto(c.id_cliente)          AS nombre_formal,
    fn_CalcularEdadCliente(c.id_cliente)              AS edad,
    fn_ContarVentasCliente(c.id_cliente)              AS num_compras,
    fn_DeterminarEstadoLealtad(c.id_cliente)          AS nivel_lealtad,
    fn_CalcularDiasDesdeUltimaCompra(c.id_cliente)    AS dias_sin_comprar,
    fn_EsClienteNuevo(c.id_cliente)                   AS es_nuevo
FROM clientes c
ORDER BY c.id_cliente;
