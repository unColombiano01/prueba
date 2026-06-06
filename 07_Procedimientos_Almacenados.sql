-- ============================================================================
-- 07_Procedimientos_Almacenados.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido: los 20 procedimientos almacenados (operaciones complejas
-- y transaccionales).
-- ORDEN DE EJECUCIÓN: ejecutar después de 01_Esquema_y_Datos.sql y
-- 03_Funciones.sql (algunos procedimientos usan funciones del archivo 03).
-- ============================================================================

USE proyecto;
DELIMITER $$


-- 1. sp_RealizarNuevaVenta: procesa una nueva venta de forma transaccional.
DROP PROCEDURE IF EXISTS sp_RealizarNuevaVenta$$
CREATE PROCEDURE sp_RealizarNuevaVenta(
    IN  p_id_cliente   INT,
    IN  p_id_producto  INT,
    IN  p_cantidad     INT,
    IN  p_id_sucursal  INT,
    OUT p_id_venta     INT,
    OUT p_mensaje      VARCHAR(255)
)
BEGIN
    DECLARE v_precio       DECIMAL(10,2);
    DECLARE v_stock        INT;
    DECLARE v_error        TINYINT DEFAULT 0;

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

    START TRANSACTION;

    SELECT precio, stock INTO v_precio, v_stock
    FROM productos WHERE id_producto = p_id_producto AND activo = 1
    FOR UPDATE;

    IF v_stock < p_cantidad THEN
        SET p_mensaje = 'Error: Stock insuficiente';
        ROLLBACK;
    ELSE
        INSERT INTO ventas (id_cliente, estado, id_sucursal)
        VALUES (p_id_cliente, 'Procesando', p_id_sucursal);

        SET p_id_venta = LAST_INSERT_ID();

        INSERT INTO detalle_ventas (id_venta, id_producto, cantidad, precio_unitario_congelado)
        VALUES (p_id_venta, p_id_producto, p_cantidad, v_precio);

        IF v_error = 1 THEN
            SET p_mensaje = 'Error al procesar la venta';
            ROLLBACK;
        ELSE
            COMMIT;
            SET p_mensaje = CONCAT('Venta #', p_id_venta, ' creada exitosamente');
        END IF;
    END IF;
END$$


-- 2. sp_AgregarNuevoProducto: inserta un nuevo producto y sus atributos iniciales.
DROP PROCEDURE IF EXISTS sp_AgregarNuevoProducto$$
CREATE PROCEDURE sp_AgregarNuevoProducto(
    IN  p_nombre        VARCHAR(255),
    IN  p_precio        DECIMAL(10,2),
    IN  p_costo         DECIMAL(10,2),
    IN  p_id_categoria  INT,
    IN  p_id_proveedor  INT,
    IN  p_sku           VARCHAR(100),
    OUT p_id_producto   INT,
    OUT p_mensaje       VARCHAR(255)
)
BEGIN
    DECLARE v_sku_final    VARCHAR(100);
    DECLARE v_nom_cat      VARCHAR(150);

    IF p_precio <= 0 THEN
        SET p_mensaje = 'Error: El precio debe ser mayor que cero';
        SET p_id_producto = -1;
    ELSEIF p_costo < 0 THEN
        SET p_mensaje = 'Error: El costo no puede ser negativo';
        SET p_id_producto = -1;
    ELSE
        IF p_sku IS NULL OR p_sku = '' THEN
            SELECT nombre INTO v_nom_cat FROM categorias WHERE id_categoria = p_id_categoria;
            SET v_sku_final = fn_GenerarSKU(p_nombre, COALESCE(v_nom_cat, 'GEN'));
        ELSE
            SET v_sku_final = p_sku;
        END IF;

        INSERT INTO productos (nombre, precio, costo, id_categoria, id_proveedor, sku)
        VALUES (p_nombre, p_precio, p_costo, p_id_categoria, p_id_proveedor, v_sku_final);

        SET p_id_producto = LAST_INSERT_ID();
        SET p_mensaje = CONCAT('Producto creado con ID: ', p_id_producto, ' | SKU: ', v_sku_final);
    END IF;
END$$


-- 3. sp_ActualizarDireccionCliente: actualiza la dirección de un cliente.
DROP PROCEDURE IF EXISTS sp_ActualizarDireccionCliente$$
CREATE PROCEDURE sp_ActualizarDireccionCliente(
    IN  p_id_cliente      INT,
    IN  p_nueva_direccion TEXT,
    OUT p_mensaje         VARCHAR(255)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM clientes WHERE id_cliente = p_id_cliente;

    IF v_existe = 0 THEN
        SET p_mensaje = 'Error: Cliente no encontrado';
    ELSE
        UPDATE clientes
        SET direccion_envio = p_nueva_direccion
        WHERE id_cliente = p_id_cliente;

        SET p_mensaje = 'Dirección actualizada correctamente';
    END IF;
END$$


-- 4. sp_ProcesarDevolucion: gestiona la devolución de un producto y ajusta el stock.
DROP PROCEDURE IF EXISTS sp_ProcesarDevolucion$$
CREATE PROCEDURE sp_ProcesarDevolucion(
    IN  p_id_venta  INT,
    IN  p_motivo    TEXT,
    OUT p_mensaje   VARCHAR(255)
)
BEGIN
    DECLARE v_estado_actual VARCHAR(50);
    DECLARE v_error TINYINT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

    SELECT estado INTO v_estado_actual FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado_actual IS NULL THEN
        SET p_mensaje = 'Error: Venta no encontrada';
    ELSEIF v_estado_actual IN ('Cancelado', 'Devuelto') THEN
        SET p_mensaje = 'Error: La venta ya fue cancelada o devuelta';
    ELSE
        START TRANSACTION;

        UPDATE productos p
        INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
        SET p.stock = p.stock + dv.cantidad
        WHERE dv.id_venta = p_id_venta;

        UPDATE ventas SET estado = 'Devuelto' WHERE id_venta = p_id_venta;

        IF v_error = 1 THEN
            ROLLBACK;
            SET p_mensaje = 'Error al procesar la devolución';
        ELSE
            COMMIT;
            SET p_mensaje = CONCAT('Devolución de venta #', p_id_venta, ' procesada. Motivo: ', p_motivo);
        END IF;
    END IF;
END$$


-- 5. sp_ObtenerHistorialComprasCliente: devuelve el historial completo de compras.
DROP PROCEDURE IF EXISTS sp_ObtenerHistorialComprasCliente$$
CREATE PROCEDURE sp_ObtenerHistorialComprasCliente(
    IN p_id_cliente INT
)
BEGIN
    SELECT
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        fn_CalcularCostoEnvio(v.id_venta) AS costo_envio
    FROM ventas v
    WHERE v.id_cliente = p_id_cliente
    ORDER BY v.fecha_venta DESC;

    SELECT
        dv.id_venta,
        p.nombre        AS producto,
        dv.cantidad,
        dv.precio_unitario_congelado AS precio_unitario,
        (dv.cantidad * dv.precio_unitario_congelado) AS subtotal
    FROM detalle_ventas dv
    INNER JOIN ventas v    ON dv.id_venta    = v.id_venta
    INNER JOIN productos p ON dv.id_producto = p.id_producto
    WHERE v.id_cliente = p_id_cliente
    ORDER BY dv.id_venta DESC;
END$$


-- 6. sp_AjustarNivelStock: ajusta manualmente el stock de un producto y registra el motivo.
DROP PROCEDURE IF EXISTS sp_AjustarNivelStock$$
CREATE PROCEDURE sp_AjustarNivelStock(
    IN  p_id_producto  INT,
    IN  p_nuevo_stock  INT,
    IN  p_motivo       VARCHAR(255),
    OUT p_mensaje      VARCHAR(255)
)
BEGIN
    DECLARE v_stock_anterior INT;

    IF p_nuevo_stock < 0 THEN
        SET p_mensaje = 'Error: El stock no puede ser negativo';
    ELSE
        SELECT stock INTO v_stock_anterior FROM productos WHERE id_producto = p_id_producto;

        UPDATE productos SET stock = p_nuevo_stock WHERE id_producto = p_id_producto;

        INSERT INTO auditoria_precios (id_producto, precio_anterior, precio_nuevo, usuario_cambio)
        VALUES (p_id_producto, v_stock_anterior, p_nuevo_stock,
                CONCAT(CURRENT_USER(), ' | Ajuste stock: ', p_motivo));

        SET p_mensaje = CONCAT('Stock ajustado de ', v_stock_anterior, ' a ', p_nuevo_stock);
    END IF;
END$$


-- 7. sp_EliminarClienteDeFormaSegura: anonimiza los datos del cliente (no los borra).
DROP PROCEDURE IF EXISTS sp_EliminarClienteDeFormaSegura$$
CREATE PROCEDURE sp_EliminarClienteDeFormaSegura(
    IN  p_id_cliente INT,
    OUT p_mensaje    VARCHAR(255)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM clientes WHERE id_cliente = p_id_cliente;

    IF v_existe = 0 THEN
        SET p_mensaje = 'Error: Cliente no encontrado';
    ELSE
        UPDATE clientes SET
            nombre          = 'Usuario',
            apellido        = 'Eliminado',
            email           = CONCAT('deleted_', id_cliente, '@removed.com'),
            contrasena      = 'ANONIMIZADO',
            direccion_envio = NULL,
            fecha_nacimiento = NULL
        WHERE id_cliente = p_id_cliente;

        SET p_mensaje = CONCAT('Cliente #', p_id_cliente, ' anonimizado correctamente');
    END IF;
END$$


-- 8. sp_AplicarDescuentoPorCategoria: aplica un descuento a todos los productos de una categoría.
DROP PROCEDURE IF EXISTS sp_AplicarDescuentoPorCategoria$$
CREATE PROCEDURE sp_AplicarDescuentoPorCategoria(
    IN  p_id_categoria  INT,
    IN  p_descuento_pct DECIMAL(5,2),
    OUT p_productos_afectados INT,
    OUT p_mensaje       VARCHAR(255)
)
BEGIN
    IF p_descuento_pct <= 0 OR p_descuento_pct >= 100 THEN
        SET p_mensaje = 'Error: El descuento debe estar entre 0 y 100';
        SET p_productos_afectados = 0;
    ELSE
        UPDATE productos
        SET precio = ROUND(precio * (1 - p_descuento_pct / 100), 2)
        WHERE id_categoria = p_id_categoria AND activo = 1;

        SET p_productos_afectados = ROW_COUNT();
        SET p_mensaje = CONCAT('Descuento de ', p_descuento_pct, '% aplicado a ',
                               p_productos_afectados, ' productos');
    END IF;
END$$


-- 9. sp_GenerarReporteMensualVentas: genera un reporte completo de ventas de un mes/año.
DROP PROCEDURE IF EXISTS sp_GenerarReporteMensualVentas$$
CREATE PROCEDURE sp_GenerarReporteMensualVentas(
    IN p_anio INT,
    IN p_mes  INT
)
BEGIN
    SELECT
        COUNT(id_venta)            AS total_ordenes,
        COUNT(DISTINCT id_cliente) AS clientes_unicos,
        SUM(total)                 AS ingresos_totales,
        AVG(total)                 AS ticket_promedio,
        MAX(total)                 AS venta_maxima,
        MIN(total)                 AS venta_minima
    FROM ventas
    WHERE YEAR(fecha_venta) = p_anio
      AND MONTH(fecha_venta) = p_mes
      AND estado NOT IN ('Cancelado');

    SELECT
        p.nombre                                            AS producto,
        SUM(dv.cantidad)                                    AS unidades,
        SUM(dv.cantidad * dv.precio_unitario_congelado)     AS ingresos
    FROM detalle_ventas dv
    INNER JOIN ventas v    ON dv.id_venta    = v.id_venta
    INNER JOIN productos p ON dv.id_producto = p.id_producto
    WHERE YEAR(v.fecha_venta)  = p_anio
      AND MONTH(v.fecha_venta) = p_mes
      AND v.estado NOT IN ('Cancelado')
    GROUP BY p.id_producto, p.nombre
    ORDER BY ingresos DESC LIMIT 5;

    SELECT
        CONCAT(c.nombre, ' ', c.apellido) AS cliente,
        COUNT(v.id_venta)                 AS compras,
        SUM(v.total)                      AS gasto_total
    FROM ventas v
    INNER JOIN clientes c ON v.id_cliente = c.id_cliente
    WHERE YEAR(v.fecha_venta)  = p_anio
      AND MONTH(v.fecha_venta) = p_mes
      AND v.estado NOT IN ('Cancelado')
    GROUP BY c.id_cliente, c.nombre, c.apellido
    ORDER BY gasto_total DESC LIMIT 5;
END$$


-- 10. sp_CambiarEstadoPedido: cambia el estado de un pedido con validaciones.
DROP PROCEDURE IF EXISTS sp_CambiarEstadoPedido$$
CREATE PROCEDURE sp_CambiarEstadoPedido(
    IN  p_id_venta    INT,
    IN  p_nuevo_estado VARCHAR(50),
    OUT p_mensaje     VARCHAR(255)
)
BEGIN
    DECLARE v_estado_actual VARCHAR(50);

    SELECT estado INTO v_estado_actual FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado_actual IS NULL THEN
        SET p_mensaje = 'Error: Venta no encontrada';
    ELSEIF v_estado_actual = 'Entregado' THEN
        SET p_mensaje = 'Error: Un pedido entregado no puede cambiar de estado';
    ELSEIF v_estado_actual = 'Cancelado' AND p_nuevo_estado != 'Devuelto' THEN
        SET p_mensaje = 'Error: Un pedido cancelado solo puede pasar a Devuelto';
    ELSE
        UPDATE ventas SET estado = p_nuevo_estado WHERE id_venta = p_id_venta;
        SET p_mensaje = CONCAT('Estado cambiado de "', v_estado_actual, '" a "', p_nuevo_estado, '"');
    END IF;
END$$


-- 11. sp_RegistrarNuevoCliente: registra un cliente validando email y contraseña.
DROP PROCEDURE IF EXISTS sp_RegistrarNuevoCliente$$
CREATE PROCEDURE sp_RegistrarNuevoCliente(
    IN  p_nombre     VARCHAR(100),
    IN  p_apellido   VARCHAR(100),
    IN  p_email      VARCHAR(255),
    IN  p_contrasena VARCHAR(255),
    OUT p_id_cliente INT,
    OUT p_mensaje    VARCHAR(255)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM clientes WHERE email = p_email;

    IF v_existe > 0 THEN
        SET p_mensaje = 'Error: El email ya está registrado';
        SET p_id_cliente = -1;
    ELSEIF fn_ValidarFormatoEmail(p_email) = 0 THEN
        SET p_mensaje = 'Error: Formato de email inválido';
        SET p_id_cliente = -1;
    ELSEIF fn_ValidarComplejidadContrasena(p_contrasena) = 0 THEN
        SET p_mensaje = 'Error: La contraseña no cumple los requisitos de seguridad';
        SET p_id_cliente = -1;
    ELSE
        INSERT INTO clientes (nombre, apellido, email, contrasena)
        VALUES (p_nombre, p_apellido, p_email, p_contrasena);

        SET p_id_cliente = LAST_INSERT_ID();
        SET p_mensaje = CONCAT('Cliente registrado con ID: ', p_id_cliente);
    END IF;
END$$


-- 12. sp_ObtenerDetallesProductoCompleto: devuelve toda la info de un producto (proveedor/categoría).
DROP PROCEDURE IF EXISTS sp_ObtenerDetallesProductoCompleto$$
CREATE PROCEDURE sp_ObtenerDetallesProductoCompleto(
    IN p_id_producto INT
)
BEGIN
    SELECT
        p.id_producto, p.nombre, p.descripcion, p.sku,
        p.precio, p.costo,
        ROUND((p.precio - p.costo) / p.precio * 100, 2) AS margen_pct,
        p.stock, p.stock_minimo, p.activo,
        p.fecha_creacion, p.fecha_modificacion,
        cat.nombre       AS categoria,
        prov.nombre      AS proveedor,
        prov.email_contacto AS contacto_proveedor,
        fn_ObtenerStockTotalPorCategoria(p.id_categoria) AS stock_total_categoria
    FROM productos p
    LEFT JOIN categorias  cat  ON p.id_categoria  = cat.id_categoria
    LEFT JOIN proveedores prov ON p.id_proveedor  = prov.id_proveedor
    WHERE p.id_producto = p_id_producto;
END$$


-- 13. sp_FusionarCuentasCliente: fusiona dos cuentas de cliente duplicadas en una.
DROP PROCEDURE IF EXISTS sp_FusionarCuentasCliente$$
CREATE PROCEDURE sp_FusionarCuentasCliente(
    IN  p_id_cliente_principal  INT,
    IN  p_id_cliente_secundario INT,
    OUT p_mensaje               VARCHAR(255)
)
BEGIN
    DECLARE v_error TINYINT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

    IF p_id_cliente_principal = p_id_cliente_secundario THEN
        SET p_mensaje = 'Error: Los IDs de cliente no pueden ser iguales';
    ELSE
        START TRANSACTION;

        UPDATE ventas
        SET id_cliente = p_id_cliente_principal
        WHERE id_cliente = p_id_cliente_secundario;

        CALL sp_EliminarClienteDeFormaSegura(p_id_cliente_secundario, @msg);

        IF v_error = 1 THEN
            ROLLBACK;
            SET p_mensaje = 'Error al fusionar las cuentas';
        ELSE
            COMMIT;
            SET p_mensaje = CONCAT('Cuentas fusionadas. Cliente principal: #', p_id_cliente_principal);
        END IF;
    END IF;
END$$


-- 14. sp_AsignarProductoAProveedor: asigna o cambia el proveedor de un producto.
DROP PROCEDURE IF EXISTS sp_AsignarProductoAProveedor$$
CREATE PROCEDURE sp_AsignarProductoAProveedor(
    IN  p_id_producto  INT,
    IN  p_id_proveedor INT,
    OUT p_mensaje      VARCHAR(255)
)
BEGIN
    DECLARE v_prod_existe INT DEFAULT 0;
    DECLARE v_prov_existe INT DEFAULT 0;

    SELECT COUNT(*) INTO v_prod_existe FROM productos   WHERE id_producto  = p_id_producto;
    SELECT COUNT(*) INTO v_prov_existe FROM proveedores WHERE id_proveedor = p_id_proveedor;

    IF v_prod_existe = 0 THEN
        SET p_mensaje = 'Error: Producto no encontrado';
    ELSEIF v_prov_existe = 0 THEN
        SET p_mensaje = 'Error: Proveedor no encontrado';
    ELSE
        UPDATE productos SET id_proveedor = p_id_proveedor WHERE id_producto = p_id_producto;
        SET p_mensaje = CONCAT('Proveedor #', p_id_proveedor, ' asignado al producto #', p_id_producto);
    END IF;
END$$


-- 15. sp_BuscarProductos: búsqueda avanzada con filtros opcionales.
DROP PROCEDURE IF EXISTS sp_BuscarProductos$$
CREATE PROCEDURE sp_BuscarProductos(
    IN p_nombre        VARCHAR(255),
    IN p_id_categoria  INT,
    IN p_precio_min    DECIMAL(10,2),
    IN p_precio_max    DECIMAL(10,2)
)
BEGIN
    SELECT
        p.id_producto, p.nombre, p.sku, p.precio,
        p.stock, cat.nombre AS categoria,
        prov.nombre AS proveedor
    FROM productos p
    LEFT JOIN categorias  cat  ON p.id_categoria  = cat.id_categoria
    LEFT JOIN proveedores prov ON p.id_proveedor  = prov.id_proveedor
    WHERE p.activo = 1
      -- Si el parámetro es NULL, esa condición se ignora
      AND (p_nombre       IS NULL OR p.nombre      LIKE CONCAT('%', p_nombre, '%'))
      AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
      AND (p_precio_min   IS NULL OR p.precio      >= p_precio_min)
      AND (p_precio_max   IS NULL OR p.precio      <= p_precio_max)
    ORDER BY p.nombre;
END$$


-- 16. sp_ObtenerDashboardAdmin: KPIs para un panel de administración.
DROP PROCEDURE IF EXISTS sp_ObtenerDashboardAdmin$$
CREATE PROCEDURE sp_ObtenerDashboardAdmin()
BEGIN
    SELECT
        COUNT(id_venta)                                     AS ventas_hoy,
        COALESCE(SUM(total), 0)                             AS ingresos_hoy,
        COUNT(DISTINCT id_cliente)                          AS clientes_activos_hoy
    FROM ventas
    WHERE DATE(fecha_venta) = CURDATE()
      AND estado NOT IN ('Cancelado');

    SELECT COUNT(*) AS nuevos_clientes_hoy
    FROM clientes WHERE DATE(fecha_registro) = CURDATE();

    SELECT id_producto, nombre, stock, stock_minimo
    FROM productos
    WHERE stock <= stock_minimo AND activo = 1
    ORDER BY stock ASC LIMIT 10;

    SELECT COUNT(*) AS alertas_pendientes FROM alertas_stock  WHERE resuelta = 0;
    SELECT COUNT(*) AS fraudes_pendientes  FROM alertas_fraude WHERE resuelta = 0;
END$$


-- 17. sp_ProcesarPago: simula el procesamiento de un pago y actualiza el estado.
DROP PROCEDURE IF EXISTS sp_ProcesarPago$$
CREATE PROCEDURE sp_ProcesarPago(
    IN  p_id_venta       INT,
    IN  p_metodo_pago    VARCHAR(50),
    OUT p_mensaje        VARCHAR(255)
)
BEGIN
    DECLARE v_estado VARCHAR(50);
    DECLARE v_total  DECIMAL(12,2);

    SELECT estado, total INTO v_estado, v_total
    FROM ventas WHERE id_venta = p_id_venta;

    IF v_estado IS NULL THEN
        SET p_mensaje = 'Error: Venta no encontrada';
    ELSEIF v_estado != 'Pendiente de Pago' THEN
        SET p_mensaje = CONCAT('Error: La venta está en estado "', v_estado, '", no se puede pagar');
    ELSE
        UPDATE ventas SET estado = 'Procesando' WHERE id_venta = p_id_venta;
        SET p_mensaje = CONCAT('Pago de $', v_total, ' procesado con ', p_metodo_pago,
                               ' para venta #', p_id_venta);
    END IF;
END$$


-- 18. sp_AnadirResenaProducto: permite a un cliente reseñar un producto que ha comprado.
DROP PROCEDURE IF EXISTS sp_AnadirResenaProducto$$
CREATE PROCEDURE sp_AnadirResenaProducto(
    IN  p_id_cliente   INT,
    IN  p_id_producto  INT,
    IN  p_calificacion TINYINT,
    IN  p_comentario   TEXT,
    OUT p_mensaje      VARCHAR(255)
)
BEGIN
    DECLARE v_compro INT DEFAULT 0;

    SELECT COUNT(*) INTO v_compro
    FROM detalle_ventas dv
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE v.id_cliente   = p_id_cliente
      AND dv.id_producto = p_id_producto
      AND v.estado       = 'Entregado';

    IF v_compro = 0 THEN
        SET p_mensaje = 'Error: Solo puedes reseñar productos que hayas comprado y recibido';
    ELSEIF p_calificacion NOT BETWEEN 1 AND 5 THEN
        SET p_mensaje = 'Error: La calificación debe estar entre 1 y 5';
    ELSE
        INSERT INTO resenas_productos (id_producto, id_cliente, calificacion, comentario)
        VALUES (p_id_producto, p_id_cliente, p_calificacion, p_comentario);

        SET p_mensaje = 'Reseña registrada correctamente. ¡Gracias!';
    END IF;
END$$


-- 19. sp_ObtenerProductosRelacionados: productos relacionados según compras conjuntas.
DROP PROCEDURE IF EXISTS sp_ObtenerProductosRelacionados$$
CREATE PROCEDURE sp_ObtenerProductosRelacionados(
    IN  p_id_producto INT,
    IN  p_limite      INT
)
BEGIN
    SELECT
        p.id_producto,
        p.nombre,
        p.precio,
        COUNT(*) AS veces_comprado_junto
    FROM detalle_ventas dv1
    INNER JOIN detalle_ventas dv2 ON dv1.id_venta    = dv2.id_venta
                                 AND dv2.id_producto != p_id_producto
    INNER JOIN productos p        ON dv2.id_producto  = p.id_producto
    WHERE dv1.id_producto = p_id_producto
      AND p.activo = 1
    GROUP BY p.id_producto, p.nombre, p.precio
    ORDER BY veces_comprado_junto DESC
    LIMIT p_limite;
END$$


-- 20. sp_MoverProductosEntreCategorias: mueve productos de una categoría a otra de forma segura.
DROP PROCEDURE IF EXISTS sp_MoverProductosEntreCategorias$$
CREATE PROCEDURE sp_MoverProductosEntreCategorias(
    IN  p_id_categoria_origen  INT,
    IN  p_id_categoria_destino INT,
    OUT p_productos_movidos    INT,
    OUT p_mensaje              VARCHAR(255)
)
BEGIN
    DECLARE v_origen_existe  INT DEFAULT 0;
    DECLARE v_destino_existe INT DEFAULT 0;
    DECLARE v_error TINYINT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

    SELECT COUNT(*) INTO v_origen_existe  FROM categorias WHERE id_categoria = p_id_categoria_origen;
    SELECT COUNT(*) INTO v_destino_existe FROM categorias WHERE id_categoria = p_id_categoria_destino;

    IF v_origen_existe = 0 THEN
        SET p_mensaje = 'Error: Categoría de origen no encontrada';
        SET p_productos_movidos = 0;
    ELSEIF v_destino_existe = 0 THEN
        SET p_mensaje = 'Error: Categoría de destino no encontrada';
        SET p_productos_movidos = 0;
    ELSEIF p_id_categoria_origen = p_id_categoria_destino THEN
        SET p_mensaje = 'Error: Las categorías de origen y destino son iguales';
        SET p_productos_movidos = 0;
    ELSE
        START TRANSACTION;

        UPDATE productos
        SET id_categoria = p_id_categoria_destino
        WHERE id_categoria = p_id_categoria_origen;

        SET p_productos_movidos = ROW_COUNT();

        IF v_error = 1 THEN
            ROLLBACK;
            SET p_mensaje = 'Error al mover los productos';
            SET p_productos_movidos = 0;
        ELSE
            COMMIT;
            SET p_mensaje = CONCAT(p_productos_movidos, ' productos movidos correctamente');
        END IF;
    END IF;
END$$


DELIMITER ;


-- ============================================================
-- PRUEBAS DE LOS PROCEDIMIENTOS
-- ============================================================

CALL sp_RealizarNuevaVenta(1, 3, 2, 1, @id_venta, @msg);
SELECT @id_venta AS nueva_venta, @msg AS resultado;

CALL sp_ActualizarDireccionCliente(1, 'Calle 20 #10-50, Bogotá', @msg);
SELECT @msg;

CALL sp_GenerarReporteMensualVentas(2026, 6);

CALL sp_RegistrarNuevoCliente('Juan', 'Torres', 'juan@test.com', 'MiClave#2024', @id, @msg);
SELECT @id AS id_nuevo_cliente, @msg AS resultado;

CALL sp_BuscarProductos('Laptop', NULL, NULL, NULL);
CALL sp_BuscarProductos(NULL, 1, 100000, 2000000);

CALL sp_ObtenerDashboardAdmin();

CALL sp_ProcesarPago(5, 'Tarjeta de crédito', @msg);
SELECT @msg;

CALL sp_ObtenerProductosRelacionados(1, 5);

-- Listado de todos los procedimientos creados
SELECT ROUTINE_NAME, ROUTINE_TYPE, CREATED
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = 'proyecto'
  AND ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME;
