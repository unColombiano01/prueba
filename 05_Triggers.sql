-- ============================================================================
-- 05_Triggers.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido: los 20 triggers (disparadores) del sistema.
-- Las tablas de auditoría que usan estos triggers (auditoria_precios,
-- auditoria_clientes, auditoria_estados_venta, alertas_stock,
-- ventas_archivadas, auditoria_permisos) se crean en 01_Esquema_y_Datos.sql.
-- ORDEN DE EJECUCIÓN: ejecutar después de 01_Esquema_y_Datos.sql.
-- ============================================================================

USE proyecto;
DELIMITER $$


-- 1. trg_audit_precio_producto_after_update: guarda un log de cambios de precios.
DROP TRIGGER IF EXISTS trg_audit_precio_producto_after_update$$
CREATE TRIGGER trg_audit_precio_producto_after_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.precio <> NEW.precio THEN
        INSERT INTO auditoria_precios (id_producto, precio_anterior, precio_nuevo, usuario_cambio)
        VALUES (NEW.id_producto, OLD.precio, NEW.precio, CURRENT_USER());
    END IF;
END$$


-- 2. trg_check_stock_before_insert_venta: verifica el stock antes de registrar una venta.
DROP TRIGGER IF EXISTS trg_check_stock_before_insert_venta$$
CREATE TRIGGER trg_check_stock_before_insert_venta
BEFORE INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    DECLARE v_stock_actual INT DEFAULT 0;
    DECLARE v_nombre_producto VARCHAR(255);

    SELECT stock, nombre INTO v_stock_actual, v_nombre_producto
    FROM productos WHERE id_producto = NEW.id_producto;

    IF v_stock_actual < NEW.cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock insuficiente para completar la venta';
    END IF;
END$$


-- 3. trg_update_stock_after_insert_venta: decrementa el stock después de una venta.
DROP TRIGGER IF EXISTS trg_update_stock_after_insert_venta$$
CREATE TRIGGER trg_update_stock_after_insert_venta
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;
END$$


-- 4. trg_prevent_delete_categoria_with_products: impide borrar una categoría con productos.
DROP TRIGGER IF EXISTS trg_prevent_delete_categoria_with_products$$
CREATE TRIGGER trg_prevent_delete_categoria_with_products
BEFORE DELETE ON categorias
FOR EACH ROW
BEGIN
    DECLARE v_count INT DEFAULT 0;

    SELECT COUNT(*) INTO v_count
    FROM productos WHERE id_categoria = OLD.id_categoria;

    IF v_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede eliminar una categoría que tiene productos asociados';
    END IF;
END$$


-- 5. trg_log_new_customer_after_insert: registra en auditoría cada nuevo cliente.
DROP TRIGGER IF EXISTS trg_log_new_customer_after_insert$$
CREATE TRIGGER trg_log_new_customer_after_insert
AFTER INSERT ON clientes
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_clientes (id_cliente, accion, detalle)
    VALUES (NEW.id_cliente, 'INSERT',
            CONCAT('Nuevo cliente: ', NEW.nombre, ' ', NEW.apellido, ' | Email: ', NEW.email));
END$$


-- 6. trg_update_total_gastado_cliente: actualiza total_gastado del cliente tras cada compra.
DROP TRIGGER IF EXISTS trg_update_total_gastado_cliente$$
CREATE TRIGGER trg_update_total_gastado_cliente
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF NEW.estado IN ('Procesando', 'Enviado', 'Entregado') AND
       OLD.estado NOT IN ('Procesando', 'Enviado', 'Entregado') THEN
        UPDATE clientes
        SET total_gastado = (
            SELECT COALESCE(SUM(total), 0)
            FROM ventas
            WHERE id_cliente = NEW.id_cliente
              AND estado NOT IN ('Cancelado', 'Pendiente de Pago')
        )
        WHERE id_cliente = NEW.id_cliente;
    END IF;
END$$


-- 7. trg_set_fecha_modificacion_producto: actualiza la fecha de modificación de un producto.
DROP TRIGGER IF EXISTS trg_set_fecha_modificacion_producto$$
CREATE TRIGGER trg_set_fecha_modificacion_producto
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    SET NEW.fecha_modificacion = NOW();
END$$


-- 8. trg_prevent_negative_stock: impide que el stock se actualice a un valor negativo.
DROP TRIGGER IF EXISTS trg_prevent_negative_stock$$
CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El stock no puede ser negativo';
    END IF;
END$$


-- 9. trg_capitalize_nombre_cliente: capitaliza nombre y apellido al insertar un cliente.
DROP TRIGGER IF EXISTS trg_capitalize_nombre_cliente$$
CREATE TRIGGER trg_capitalize_nombre_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    SET NEW.nombre   = CONCAT(UPPER(LEFT(NEW.nombre, 1)),   LOWER(SUBSTRING(NEW.nombre,   2)));
    SET NEW.apellido = CONCAT(UPPER(LEFT(NEW.apellido, 1)), LOWER(SUBSTRING(NEW.apellido, 2)));
END$$


-- 10. trg_recalculate_total_venta_on_detalle_change: recalcula el total de la venta.
DROP TRIGGER IF EXISTS trg_recalculate_total_venta_on_detalle_change$$
CREATE TRIGGER trg_recalculate_total_venta_on_detalle_change
AFTER INSERT ON detalle_ventas
FOR EACH ROW
BEGIN
    UPDATE ventas
    SET total = (
        SELECT COALESCE(SUM(cantidad * precio_unitario_congelado), 0)
        FROM detalle_ventas
        WHERE id_venta = NEW.id_venta
    )
    WHERE id_venta = NEW.id_venta;
END$$


-- 11. trg_log_order_status_change: audita cada cambio de estado en un pedido.
DROP TRIGGER IF EXISTS trg_log_order_status_change$$
CREATE TRIGGER trg_log_order_status_change
AFTER UPDATE ON ventas
FOR EACH ROW
BEGIN
    IF OLD.estado <> NEW.estado THEN
        INSERT INTO auditoria_estados_venta (id_venta, estado_anterior, estado_nuevo)
        VALUES (NEW.id_venta, OLD.estado, NEW.estado);
    END IF;
END$$


-- 12. trg_prevent_price_zero_or_less: impide que el precio sea cero o negativo.
DROP TRIGGER IF EXISTS trg_prevent_price_zero_or_less$$
CREATE TRIGGER trg_prevent_price_zero_or_less
BEFORE UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.precio <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El precio del producto debe ser mayor que cero';
    END IF;
END$$


-- 13. trg_send_stock_alert_on_low_stock: inserta una alerta si el stock baja del umbral.
DROP TRIGGER IF EXISTS trg_send_stock_alert_on_low_stock$$
CREATE TRIGGER trg_send_stock_alert_on_low_stock
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF NEW.stock <= NEW.stock_minimo AND OLD.stock > OLD.stock_minimo THEN
        INSERT INTO alertas_stock (id_producto, stock_actual, stock_minimo)
        VALUES (NEW.id_producto, NEW.stock, NEW.stock_minimo);
    END IF;
END$$


-- 14. trg_archive_deleted_venta: archiva una venta eliminada en lugar de borrarla.
DROP TRIGGER IF EXISTS trg_archive_deleted_venta$$
CREATE TRIGGER trg_archive_deleted_venta
BEFORE DELETE ON ventas
FOR EACH ROW
BEGIN
    INSERT INTO ventas_archivadas (id_venta, id_cliente, total, estado, fecha_venta)
    VALUES (OLD.id_venta, OLD.id_cliente, OLD.total, OLD.estado, OLD.fecha_venta);
END$$


-- 15. trg_validate_email_format_on_customer: valida el formato del email
--     antes de insertar o actualizar un cliente (se implementa con 2 triggers).
DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer_insert$$
CREATE TRIGGER trg_validate_email_format_on_customer_insert
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NOT (NEW.email REGEXP '^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_validate_email_format_on_customer_update$$
CREATE TRIGGER trg_validate_email_format_on_customer_update
BEFORE UPDATE ON clientes
FOR EACH ROW
BEGIN
    IF NOT (NEW.email REGEXP '^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El formato del correo electrónico no es válido';
    END IF;
END$$


-- 16. trg_update_last_order_date_customer: actualiza la fecha del último pedido del cliente.
DROP TRIGGER IF EXISTS trg_update_last_order_date_customer$$
CREATE TRIGGER trg_update_last_order_date_customer
AFTER INSERT ON ventas
FOR EACH ROW
BEGIN
    UPDATE clientes
    SET ultima_compra = NEW.fecha_venta
    WHERE id_cliente = NEW.id_cliente;
END$$


-- 17. trg_prevent_self_referral: impide que un cliente se refiera a sí mismo.
DROP TRIGGER IF EXISTS trg_prevent_self_referral$$
CREATE TRIGGER trg_prevent_self_referral
BEFORE INSERT ON clientes
FOR EACH ROW
BEGIN
    IF NEW.id_referido_por IS NOT NULL AND NEW.id_referido_por = NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Un cliente no puede referirse a sí mismo';
    END IF;
END$$


-- 18. trg_log_permission_changes: audita los cambios en los permisos de los usuarios.
-- IMPORTANTE: MySQL NO permite crear triggers sobre tablas del sistema (mysql.user).
-- Por ello esta auditoría se simula registrando en auditoria_permisos cuando se
-- crea/actualiza un usuario_sistema. (El trigger original sobre mysql.user fallaría.)
DROP TRIGGER IF EXISTS trg_log_permission_changes$$
CREATE TRIGGER trg_log_permission_changes
AFTER INSERT ON usuarios_sistema
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_permisos (usuario, accion)
    VALUES (NEW.username, CONCAT('Alta de usuario de sistema: ', NEW.username));
END$$


-- 19. trg_assign_default_category_on_null: asigna la categoría "General" si es NULL.
DROP TRIGGER IF EXISTS trg_assign_default_category_on_null$$
CREATE TRIGGER trg_assign_default_category_on_null
BEFORE INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NULL THEN
        SELECT id_categoria INTO NEW.id_categoria
        FROM categorias
        WHERE nombre = 'General'
        LIMIT 1;
    END IF;
END$$


-- 20. trg_update_producto_count_in_categoria: mantiene el contador de productos por categoría.
-- Se implementa con 3 triggers (INSERT, DELETE, UPDATE) sobre productos.
DROP TRIGGER IF EXISTS trg_update_count_on_insert$$
CREATE TRIGGER trg_update_count_on_insert
AFTER INSERT ON productos
FOR EACH ROW
BEGIN
    IF NEW.id_categoria IS NOT NULL THEN
        UPDATE categorias
        SET total_productos = total_productos + 1
        WHERE id_categoria = NEW.id_categoria;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_update_count_on_delete$$
CREATE TRIGGER trg_update_count_on_delete
AFTER DELETE ON productos
FOR EACH ROW
BEGIN
    IF OLD.id_categoria IS NOT NULL THEN
        UPDATE categorias
        SET total_productos = total_productos - 1
        WHERE id_categoria = OLD.id_categoria;
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_update_count_on_update$$
CREATE TRIGGER trg_update_count_on_update
AFTER UPDATE ON productos
FOR EACH ROW
BEGIN
    IF OLD.id_categoria <> NEW.id_categoria OR
       (OLD.id_categoria IS NULL AND NEW.id_categoria IS NOT NULL) OR
       (OLD.id_categoria IS NOT NULL AND NEW.id_categoria IS NULL) THEN

        IF OLD.id_categoria IS NOT NULL THEN
            UPDATE categorias SET total_productos = total_productos - 1
            WHERE id_categoria = OLD.id_categoria;
        END IF;

        IF NEW.id_categoria IS NOT NULL THEN
            UPDATE categorias SET total_productos = total_productos + 1
            WHERE id_categoria = NEW.id_categoria;
        END IF;
    END IF;
END$$


DELIMITER ;


-- ============================================================
-- VERIFICACIÓN DE LOS TRIGGERS CREADOS
-- ============================================================

SELECT
    TRIGGER_NAME        AS nombre,
    EVENT_MANIPULATION  AS evento,
    EVENT_OBJECT_TABLE  AS tabla,
    ACTION_TIMING       AS momento
FROM INFORMATION_SCHEMA.TRIGGERS
WHERE TRIGGER_SCHEMA = 'proyecto'
ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING, EVENT_MANIPULATION;
