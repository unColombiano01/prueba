-- ============================================================================
-- 06_Eventos.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido: activación del event_scheduler y los 20 eventos programados.
-- Las tablas usadas por los eventos (resumen_ventas_diario, kpis_mensuales,
-- lista_reabastecimiento, ranking_productos, log_tamano_db, alertas_fraude,
-- alertas_stock) se crean en 01_Esquema_y_Datos.sql.
-- ORDEN DE EJECUCIÓN: ejecutar después de 01_Esquema_y_Datos.sql.
-- ============================================================================

-- Activa el planificador de eventos (necesario para que los eventos se ejecuten).
SET GLOBAL event_scheduler = ON;

USE proyecto;
DELIMITER $$


-- 1. evt_generate_weekly_sales_report: genera un reporte de ventas semanal.
DROP EVENT IF EXISTS evt_generate_weekly_sales_report$$
CREATE EVENT evt_generate_weekly_sales_report
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(CURDATE(), '06:00:00')
DO BEGIN
    INSERT INTO resumen_ventas_diario (fecha, total_ventas, num_ordenes, num_clientes)
    SELECT
        CURDATE()                   AS fecha,
        COALESCE(SUM(total), 0)     AS total_ventas,
        COUNT(id_venta)             AS num_ordenes,
        COUNT(DISTINCT id_cliente)  AS num_clientes
    FROM ventas
    WHERE fecha_venta >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND estado NOT IN ('Cancelado')
    ON DUPLICATE KEY UPDATE
        total_ventas  = VALUES(total_ventas),
        num_ordenes   = VALUES(num_ordenes),
        num_clientes  = VALUES(num_clientes);
END$$


-- 2. evt_cleanup_temp_tables_daily: borra datos temporales/alertas resueltas diariamente.
DROP EVENT IF EXISTS evt_cleanup_temp_tables_daily$$
CREATE EVENT evt_cleanup_temp_tables_daily
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '02:00:00')
DO BEGIN
    DELETE FROM alertas_stock
    WHERE resuelta = 1
      AND fecha_alerta < DATE_SUB(NOW(), INTERVAL 7 DAY);

    DELETE FROM alertas_fraude
    WHERE resuelta = 1
      AND fecha_alerta < DATE_SUB(NOW(), INTERVAL 30 DAY);
END$$


-- 3. evt_archive_old_logs_monthly: archiva (elimina) logs de más de 6 meses.
DROP EVENT IF EXISTS evt_archive_old_logs_monthly$$
CREATE EVENT evt_archive_old_logs_monthly
ON SCHEDULE EVERY 1 MONTH
    STARTS TIMESTAMP(CURDATE(), '03:00:00')
DO BEGIN
    DELETE FROM auditoria_precios
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    DELETE FROM auditoria_estados_venta
    WHERE fecha_cambio < DATE_SUB(NOW(), INTERVAL 6 MONTH);

    DELETE FROM log_intentos_fallidos
    WHERE fecha_intento < DATE_SUB(NOW(), INTERVAL 6 MONTH);
END$$


-- 4. evt_deactivate_expired_promotions_hourly: desactiva productos sin stock obsoletos.
DROP EVENT IF EXISTS evt_deactivate_expired_promotions_hourly$$
CREATE EVENT evt_deactivate_expired_promotions_hourly
ON SCHEDULE EVERY 1 HOUR
DO BEGIN
    UPDATE productos
    SET activo = 0
    WHERE stock = 0
      AND activo = 1
      AND fecha_modificacion < DATE_SUB(NOW(), INTERVAL 30 DAY);
END$$


-- 5. evt_recalculate_customer_loyalty_tiers_nightly: recalcula el gasto total de cada cliente.
DROP EVENT IF EXISTS evt_recalculate_customer_loyalty_tiers_nightly$$
CREATE EVENT evt_recalculate_customer_loyalty_tiers_nightly
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '01:00:00')
DO BEGIN
    UPDATE clientes c
    SET c.total_gastado = (
        SELECT COALESCE(SUM(v.total), 0)
        FROM ventas v
        WHERE v.id_cliente = c.id_cliente
          AND v.estado NOT IN ('Cancelado', 'Pendiente de Pago')
    );
END$$


-- 6. evt_generate_reorder_list_daily: crea la lista de productos a reabastecer.
DROP EVENT IF EXISTS evt_generate_reorder_list_daily$$
CREATE EVENT evt_generate_reorder_list_daily
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '07:00:00')
DO BEGIN
    DELETE FROM lista_reabastecimiento WHERE fecha_lista = CURDATE();

    INSERT INTO lista_reabastecimiento (id_producto, stock_actual, stock_minimo, fecha_lista)
    SELECT id_producto, stock, stock_minimo, CURDATE()
    FROM productos
    WHERE stock <= stock_minimo
      AND activo = 1;
END$$


-- 7. evt_rebuild_indexes_weekly: optimiza (reconstruye) las tablas más usadas.
DROP EVENT IF EXISTS evt_rebuild_indexes_weekly$$
CREATE EVENT evt_rebuild_indexes_weekly
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(CURDATE(), '04:00:00')
DO BEGIN
    OPTIMIZE TABLE productos;
    OPTIMIZE TABLE ventas;
    OPTIMIZE TABLE detalle_ventas;
    OPTIMIZE TABLE clientes;
END$$


-- 8. evt_suspend_inactive_accounts_quarterly: detecta cuentas inactivas (>1 año).
-- NOTA: la tabla 'clientes' no tiene columna 'activo', por lo que en lugar de
-- desactivar la cuenta se registra una alerta para revisión manual.
DROP EVENT IF EXISTS evt_suspend_inactive_accounts_quarterly$$
CREATE EVENT evt_suspend_inactive_accounts_quarterly
ON SCHEDULE EVERY 3 MONTH
    STARTS TIMESTAMP(CURDATE(), '03:30:00')
DO BEGIN
    INSERT INTO alertas_fraude (id_cliente, descripcion)
    SELECT
        id_cliente,
        CONCAT('Cuenta inactiva (sin compras > 1 año): ', nombre, ' ', apellido)
    FROM clientes
    WHERE (ultima_compra < DATE_SUB(NOW(), INTERVAL 1 YEAR)
           OR ultima_compra IS NULL)
      AND fecha_registro < DATE_SUB(NOW(), INTERVAL 1 YEAR);
END$$


-- 9. evt_aggregate_daily_sales_data: agrega los datos de ventas del día anterior.
DROP EVENT IF EXISTS evt_aggregate_daily_sales_data$$
CREATE EVENT evt_aggregate_daily_sales_data
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '00:05:00')
DO BEGIN
    INSERT INTO resumen_ventas_diario (fecha, total_ventas, num_ordenes, num_clientes)
    SELECT
        DATE(fecha_venta),
        COALESCE(SUM(total), 0),
        COUNT(id_venta),
        COUNT(DISTINCT id_cliente)
    FROM ventas
    WHERE DATE(fecha_venta) = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
      AND estado NOT IN ('Cancelado')
    GROUP BY DATE(fecha_venta)
    ON DUPLICATE KEY UPDATE
        total_ventas = VALUES(total_ventas),
        num_ordenes  = VALUES(num_ordenes),
        num_clientes = VALUES(num_clientes);
END$$


-- 10. evt_check_data_consistency_nightly: busca inconsistencias (ventas sin detalles).
DROP EVENT IF EXISTS evt_check_data_consistency_nightly$$
CREATE EVENT evt_check_data_consistency_nightly
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '02:30:00')
DO BEGIN
    INSERT INTO alertas_fraude (id_cliente, descripcion)
    SELECT v.id_cliente,
           CONCAT('Venta ID ', v.id_venta, ' no tiene detalles asociados')
    FROM ventas v
    LEFT JOIN detalle_ventas dv ON v.id_venta = dv.id_venta
    WHERE dv.id_detalle IS NULL
      AND v.estado NOT IN ('Cancelado');

    UPDATE productos SET stock = 0 WHERE stock < 0;
END$$


-- 11. evt_send_birthday_greetings_daily: genera lista de clientes que cumplen años.
DROP EVENT IF EXISTS evt_send_birthday_greetings_daily$$
CREATE EVENT evt_send_birthday_greetings_daily
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '08:00:00')
DO BEGIN
    INSERT INTO alertas_fraude (id_cliente, descripcion)
    SELECT id_cliente,
           CONCAT('CUMPLEAÑOS: Enviar cupón a ', nombre, ' ', apellido, ' (', email, ')')
    FROM clientes
    WHERE DAY(fecha_nacimiento)   = DAY(CURDATE())
      AND MONTH(fecha_nacimiento) = MONTH(CURDATE())
      AND fecha_nacimiento IS NOT NULL;
END$$


-- 12. evt_update_product_rankings_hourly: actualiza el ranking de productos más populares.
DROP EVENT IF EXISTS evt_update_product_rankings_hourly$$
CREATE EVENT evt_update_product_rankings_hourly
ON SCHEDULE EVERY 1 HOUR
DO BEGIN
    TRUNCATE TABLE ranking_productos;

    INSERT INTO ranking_productos (id_producto, total_vendido, ingresos_total, posicion)
    SELECT
        p.id_producto,
        COALESCE(SUM(dv.cantidad), 0),
        COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0),
        RANK() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) DESC)
    FROM productos p
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
    WHERE p.activo = 1
    GROUP BY p.id_producto;
END$$


-- 13. evt_backup_critical_tables_daily: backup lógico de las tablas más importantes.
DROP EVENT IF EXISTS evt_backup_critical_tables_daily$$
CREATE EVENT evt_backup_critical_tables_daily
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '23:00:00')
DO BEGIN
    DROP TABLE IF EXISTS backup_ventas;
    CREATE TABLE backup_ventas AS SELECT * FROM ventas;

    DROP TABLE IF EXISTS backup_clientes;
    CREATE TABLE backup_clientes AS SELECT * FROM clientes;

    DROP TABLE IF EXISTS backup_productos;
    CREATE TABLE backup_productos AS SELECT * FROM productos;
END$$


-- 14. evt_clear_abandoned_carts_daily: vacía los carritos abandonados (>72h).
DROP EVENT IF EXISTS evt_clear_abandoned_carts_daily$$
CREATE EVENT evt_clear_abandoned_carts_daily
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '03:00:00')
DO BEGIN
    DELETE FROM carritos
    WHERE fecha_agregado < DATE_SUB(NOW(), INTERVAL 72 HOUR);
END$$


-- 15. evt_calculate_monthly_kpis: calcula los KPIs del mes anterior.
DROP EVENT IF EXISTS evt_calculate_monthly_kpis$$
CREATE EVENT evt_calculate_monthly_kpis
ON SCHEDULE EVERY 1 MONTH
    STARTS TIMESTAMP(CURDATE(), '05:00:00')
DO BEGIN
    INSERT INTO kpis_mensuales (anio, mes, total_ingresos, num_ventas, nuevos_clientes, ticket_promedio)
    SELECT
        YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH)),
        COALESCE(SUM(v.total), 0),
        COUNT(DISTINCT v.id_venta),
        (SELECT COUNT(*) FROM clientes
         WHERE YEAR(fecha_registro)  = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
           AND MONTH(fecha_registro) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))),
        COALESCE(AVG(v.total), 0)
    FROM ventas v
    WHERE YEAR(v.fecha_venta)  = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
      AND MONTH(v.fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
      AND v.estado NOT IN ('Cancelado')
    ON DUPLICATE KEY UPDATE
        total_ingresos  = VALUES(total_ingresos),
        num_ventas      = VALUES(num_ventas),
        nuevos_clientes = VALUES(nuevos_clientes),
        ticket_promedio = VALUES(ticket_promedio);
END$$


-- 16. evt_refresh_materialized_views_nightly: refresca el resumen de los últimos 7 días.
DROP EVENT IF EXISTS evt_refresh_materialized_views_nightly$$
CREATE EVENT evt_refresh_materialized_views_nightly
ON SCHEDULE EVERY 1 DAY
    STARTS TIMESTAMP(CURDATE(), '01:30:00')
DO BEGIN
    INSERT INTO resumen_ventas_diario (fecha, total_ventas, num_ordenes, num_clientes)
    SELECT
        DATE(fecha_venta),
        COALESCE(SUM(total), 0),
        COUNT(id_venta),
        COUNT(DISTINCT id_cliente)
    FROM ventas
    WHERE DATE(fecha_venta) >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      AND estado NOT IN ('Cancelado')
    GROUP BY DATE(fecha_venta)
    ON DUPLICATE KEY UPDATE
        total_ventas = VALUES(total_ventas),
        num_ordenes  = VALUES(num_ordenes),
        num_clientes = VALUES(num_clientes);
END$$


-- 17. evt_log_database_size_weekly: registra el tamaño de la base de datos.
DROP EVENT IF EXISTS evt_log_database_size_weekly$$
CREATE EVENT evt_log_database_size_weekly
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(CURDATE(), '05:00:00')
DO BEGIN
    INSERT INTO log_tamano_db (tamano_mb)
    SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema = 'proyecto';
END$$


-- 18. evt_detect_fraudulent_activity_hourly: detecta patrones sospechosos (pedidos cancelados).
DROP EVENT IF EXISTS evt_detect_fraudulent_activity_hourly$$
CREATE EVENT evt_detect_fraudulent_activity_hourly
ON SCHEDULE EVERY 1 HOUR
DO BEGIN
    INSERT INTO alertas_fraude (id_cliente, descripcion)
    SELECT
        id_cliente,
        CONCAT('Posible fraude: ', COUNT(*), ' pedidos cancelados en las últimas 24 horas')
    FROM ventas
    WHERE estado = 'Cancelado'
      AND fecha_venta >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    GROUP BY id_cliente
    HAVING COUNT(*) > 5;
END$$


-- 19. evt_generate_supplier_performance_report_monthly: reporte mensual de proveedores.
DROP EVENT IF EXISTS evt_generate_supplier_performance_report_monthly$$
CREATE EVENT evt_generate_supplier_performance_report_monthly
ON SCHEDULE EVERY 1 MONTH
    STARTS TIMESTAMP(CURDATE(), '06:00:00')
DO BEGIN
    INSERT INTO alertas_fraude (id_cliente, descripcion)
    SELECT
        NULL,
        CONCAT('Proveedor: ', prov.nombre,
               ' | Ventas mes anterior: $', COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0),
               ' | Unidades: ', COALESCE(SUM(dv.cantidad), 0))
    FROM proveedores prov
    LEFT JOIN productos p ON prov.id_proveedor = p.id_proveedor
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta
        AND YEAR(v.fecha_venta)  = YEAR(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
        AND MONTH(v.fecha_venta) = MONTH(DATE_SUB(CURDATE(), INTERVAL 1 MONTH))
        AND v.estado != 'Cancelado'
    GROUP BY prov.id_proveedor, prov.nombre;
END$$


-- 20. evt_purge_soft_deleted_records_weekly: elimina productos inactivos nunca vendidos.
DROP EVENT IF EXISTS evt_purge_soft_deleted_records_weekly$$
CREATE EVENT evt_purge_soft_deleted_records_weekly
ON SCHEDULE EVERY 1 WEEK
    STARTS TIMESTAMP(CURDATE(), '04:30:00')
DO BEGIN
    DELETE p FROM productos p
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    WHERE p.activo = 0
      AND p.fecha_modificacion < DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND dv.id_detalle IS NULL;  -- Solo si nunca fue vendido
END$$


DELIMITER ;


-- ============================================================
-- VERIFICACIÓN DE LOS EVENTOS CREADOS
-- ============================================================

SELECT
    EVENT_NAME           AS nombre,
    STATUS               AS estado,
    EVENT_TYPE           AS tipo,
    INTERVAL_VALUE       AS intervalo,
    INTERVAL_FIELD       AS unidad,
    LAST_EXECUTED        AS ultima_ejecucion,
    NEXT_NOT_FOR_REPLICA AS proxima_ejecucion
FROM INFORMATION_SCHEMA.EVENTS
WHERE EVENT_SCHEMA = 'proyecto'
ORDER BY EVENT_NAME;
