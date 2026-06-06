-- ============================================================================
-- 02_Consultas_Avanzadas.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido: las 20 consultas de análisis y reporteo.
-- Cada consulta está precedida por un comentario con la pregunta de negocio.
-- ORDEN DE EJECUCIÓN: ejecutar después de 01_Esquema_y_Datos.sql.
-- ============================================================================

USE proyecto;


-- 1. Top 10 Productos Más Vendidos: ranking de los 10 productos con más ingresos.
SELECT
    p.id_producto,
    p.nombre                                            AS producto,
    p.sku,
    SUM(dv.cantidad)                                    AS unidades_vendidas,
    SUM(dv.cantidad * dv.precio_unitario_congelado)     AS ingresos_totales,
    RANK() OVER (ORDER BY SUM(dv.cantidad * dv.precio_unitario_congelado) DESC) AS posicion
FROM
    productos p
    INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    INNER JOIN ventas v          ON dv.id_venta   = v.id_venta
WHERE
    v.estado != 'Cancelado'
GROUP BY
    p.id_producto, p.nombre, p.sku
ORDER BY
    ingresos_totales DESC
LIMIT 10;


-- 2. Productos con Bajas Ventas: productos en el 10% inferior de ventas (candidatos a descontinuar).
WITH ventas_por_producto AS (
    SELECT
        p.id_producto,
        p.nombre,
        COALESCE(SUM(dv.cantidad), 0) AS total_vendido
    FROM
        productos p
        LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
        LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
    WHERE
        p.activo = 1
    GROUP BY
        p.id_producto, p.nombre
),
ranking AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY total_vendido ASC) AS decil
    FROM ventas_por_producto
)
SELECT
    id_producto,
    nombre,
    total_vendido,
    decil,
    'Candidato a descontinuar' AS recomendacion
FROM ranking
WHERE decil = 1
ORDER BY total_vendido ASC;


-- 3. Clientes VIP: los 5 clientes con mayor valor de vida (LTV) según su gasto histórico.
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido)               AS nombre_completo,
    c.email,
    COUNT(DISTINCT v.id_venta)                       AS total_compras,
    SUM(v.total)                                     AS gasto_total,
    AVG(v.total)                                     AS ticket_promedio,
    MAX(v.fecha_venta)                               AS ultima_compra
FROM
    clientes c
    INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE
    v.estado NOT IN ('Cancelado', 'Pendiente de Pago')
GROUP BY
    c.id_cliente, c.nombre, c.apellido, c.email
ORDER BY
    gasto_total DESC
LIMIT 5;


-- 4. Análisis de Ventas Mensuales: ventas totales agrupadas por mes y año (con crecimiento).
SELECT
    YEAR(v.fecha_venta)                             AS anio,
    MONTH(v.fecha_venta)                            AS mes,
    DATE_FORMAT(v.fecha_venta, '%Y-%m')             AS periodo,
    COUNT(v.id_venta)                               AS num_ordenes,
    COUNT(DISTINCT v.id_cliente)                    AS clientes_distintos,
    SUM(v.total)                                    AS ingresos_totales,
    AVG(v.total)                                    AS ticket_promedio,
    LAG(SUM(v.total)) OVER (ORDER BY YEAR(v.fecha_venta), MONTH(v.fecha_venta)) AS ingresos_mes_anterior,
    ROUND(
        (SUM(v.total) - LAG(SUM(v.total)) OVER (ORDER BY YEAR(v.fecha_venta), MONTH(v.fecha_venta)))
        / NULLIF(LAG(SUM(v.total)) OVER (ORDER BY YEAR(v.fecha_venta), MONTH(v.fecha_venta)), 0)
        * 100
    , 2)                                            AS crecimiento_pct
FROM
    ventas v
WHERE
    v.estado NOT IN ('Cancelado')
GROUP BY
    YEAR(v.fecha_venta), MONTH(v.fecha_venta)
ORDER BY
    anio, mes;


-- 5. Crecimiento de Clientes: número de nuevos clientes registrados por trimestre.
SELECT
    YEAR(fecha_registro)                            AS anio,
    QUARTER(fecha_registro)                         AS trimestre,
    CONCAT('Q', QUARTER(fecha_registro), '-', YEAR(fecha_registro)) AS periodo,
    COUNT(id_cliente)                               AS nuevos_clientes,
    SUM(COUNT(id_cliente)) OVER (
        ORDER BY YEAR(fecha_registro), QUARTER(fecha_registro)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS clientes_acumulados
FROM
    clientes
GROUP BY
    YEAR(fecha_registro), QUARTER(fecha_registro)
ORDER BY
    anio, trimestre;


-- 6. Tasa de Compra Repetida: porcentaje de clientes que ha realizado más de una compra.
WITH compras_por_cliente AS (
    SELECT
        id_cliente,
        COUNT(id_venta) AS num_compras
    FROM ventas
    WHERE estado NOT IN ('Cancelado', 'Pendiente de Pago')
    GROUP BY id_cliente
)
SELECT
    COUNT(*)                                        AS total_clientes_con_compras,
    SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) AS clientes_recurrentes,
    SUM(CASE WHEN num_compras = 1 THEN 1 ELSE 0 END) AS clientes_solo_una_vez,
    ROUND(
        SUM(CASE WHEN num_compras > 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
    , 2)                                            AS tasa_compra_repetida_pct
FROM compras_por_cliente;


-- 7. Productos Comprados Juntos Frecuentemente: pares de productos comprados en la misma transacción.
SELECT
    p1.nombre                                       AS producto_a,
    p2.nombre                                       AS producto_b,
    COUNT(*)                                        AS veces_comprados_juntos
FROM
    detalle_ventas dv1
    INNER JOIN detalle_ventas dv2 ON dv1.id_venta = dv2.id_venta
                                 AND dv1.id_producto < dv2.id_producto
    INNER JOIN productos p1 ON dv1.id_producto = p1.id_producto
    INNER JOIN productos p2 ON dv2.id_producto = p2.id_producto
GROUP BY
    p1.nombre, p2.nombre
HAVING
    COUNT(*) >= 1
ORDER BY
    veces_comprados_juntos DESC
LIMIT 20;


-- 8. Rotación de Inventario: tasa de rotación de stock para cada categoría de producto.
SELECT
    cat.nombre                                      AS categoria,
    SUM(p.stock)                                    AS stock_actual_total,
    COALESCE(SUM(dv.cantidad), 0)                   AS unidades_vendidas,
    ROUND(
        COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0)
    , 2)                                            AS tasa_rotacion,
    CASE
        WHEN COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0) > 2
            THEN 'Alta rotación'
        WHEN COALESCE(SUM(dv.cantidad), 0) / NULLIF(SUM(p.stock), 0) > 1
            THEN 'Rotación media'
        ELSE 'Baja rotación'
    END                                             AS clasificacion
FROM
    categorias cat
    LEFT JOIN productos p   ON cat.id_categoria  = p.id_categoria
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY
    cat.id_categoria, cat.nombre
ORDER BY
    tasa_rotacion DESC;


-- 9. Productos que Necesitan Reabastecimiento: stock actual por debajo del umbral mínimo.
SELECT
    p.id_producto,
    p.sku,
    p.nombre,
    cat.nombre                                      AS categoria,
    prov.nombre                                     AS proveedor,
    prov.email_contacto                             AS contacto_proveedor,
    p.stock                                         AS stock_actual,
    p.stock_minimo,
    (p.stock_minimo - p.stock)                      AS unidades_a_pedir,
    CASE
        WHEN p.stock = 0       THEN 'URGENTE - Sin stock'
        WHEN p.stock <= p.stock_minimo THEN 'Reabastecimiento necesario'
        ELSE 'OK'
    END                                             AS estado_stock
FROM
    productos p
    LEFT JOIN categorias  cat  ON p.id_categoria  = cat.id_categoria
    LEFT JOIN proveedores prov ON p.id_proveedor  = prov.id_proveedor
WHERE
    p.stock <= p.stock_minimo
    AND p.activo = 1
ORDER BY
    p.stock ASC;


-- 10. Análisis de Carrito Abandonado (Simulado): clientes que agregaron productos pero no compraron.
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido)              AS cliente,
    c.email,
    COUNT(DISTINCT ca.id_producto)                  AS productos_en_carrito,
    SUM(ca.cantidad * p.precio)                     AS valor_potencial,
    MIN(ca.fecha_agregado)                          AS primer_producto_agregado,
    TIMESTAMPDIFF(HOUR, MIN(ca.fecha_agregado), NOW()) AS horas_abandonado
FROM
    carritos ca
    INNER JOIN clientes  c ON ca.id_cliente  = c.id_cliente
    INNER JOIN productos p ON ca.id_producto = p.id_producto
WHERE
    ca.fecha_agregado < DATE_SUB(NOW(), INTERVAL 1 HOUR)
    AND ca.fecha_agregado > DATE_SUB(NOW(), INTERVAL 72 HOUR)
    AND c.id_cliente NOT IN (
        SELECT DISTINCT id_cliente
        FROM ventas
        WHERE fecha_venta > DATE_SUB(NOW(), INTERVAL 72 HOUR)
          AND estado NOT IN ('Cancelado', 'Pendiente de Pago')
    )
GROUP BY
    c.id_cliente, c.nombre, c.apellido, c.email
ORDER BY
    valor_potencial DESC;


-- 11. Rendimiento de Proveedores: clasificación según el volumen de ventas de sus productos.
SELECT
    prov.id_proveedor,
    prov.nombre                                     AS proveedor,
    prov.email_contacto,
    COUNT(DISTINCT p.id_producto)                   AS num_productos,
    COALESCE(SUM(dv.cantidad), 0)                   AS unidades_vendidas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos_generados,
    RANK() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) DESC)
                                                    AS ranking
FROM
    proveedores prov
    LEFT JOIN productos p   ON prov.id_proveedor = p.id_proveedor
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
GROUP BY
    prov.id_proveedor, prov.nombre, prov.email_contacto
ORDER BY
    ingresos_generados DESC;


-- 12. Análisis Geográfico de Ventas: ventas agrupadas por ciudad o región del cliente.
SELECT
    TRIM(SUBSTRING_INDEX(c.direccion_envio, ',', -1)) AS ciudad_region,
    COUNT(DISTINCT v.id_venta)                      AS num_ventas,
    COUNT(DISTINCT c.id_cliente)                    AS num_clientes,
    SUM(v.total)                                    AS ingresos_totales,
    ROUND(AVG(v.total), 2)                          AS ticket_promedio
FROM
    clientes c
    INNER JOIN ventas v ON c.id_cliente = v.id_cliente
WHERE
    v.estado NOT IN ('Cancelado')
    AND c.direccion_envio IS NOT NULL
GROUP BY
    ciudad_region
ORDER BY
    ingresos_totales DESC;


-- 13. Ventas por Hora del Día: horas pico de compras para optimizar campañas de marketing.
SELECT
    HOUR(v.fecha_venta)                             AS hora_del_dia,
    CONCAT(LPAD(HOUR(v.fecha_venta), 2, '0'), ':00 - ',
           LPAD(HOUR(v.fecha_venta) + 1, 2, '0'), ':00') AS rango_hora,
    COUNT(v.id_venta)                               AS num_ventas,
    SUM(v.total)                                    AS ingresos,
    ROUND(COUNT(v.id_venta) * 100.0 /
        (SELECT COUNT(*) FROM ventas WHERE estado != 'Cancelado'), 2)
                                                    AS pct_del_total
FROM
    ventas v
WHERE
    v.estado != 'Cancelado'
GROUP BY
    HOUR(v.fecha_venta)
ORDER BY
    num_ventas DESC;


-- 14. Impacto de Promociones: comparar ventas de un producto antes, durante y después de un descuento.
SET @id_producto_promo = 3;
SET @inicio_promo      = '2025-05-01';
SET @fin_promo         = '2025-05-31';

SELECT
    periodo,
    num_ventas,
    unidades_vendidas,
    ingresos_totales,
    precio_promedio_venta
FROM (
    SELECT
        'Antes de la promoción'     AS periodo,
        COUNT(dv.id_detalle)        AS num_ventas,
        SUM(dv.cantidad)            AS unidades_vendidas,
        SUM(dv.cantidad * dv.precio_unitario_congelado) AS ingresos_totales,
        ROUND(AVG(dv.precio_unitario_congelado), 2)     AS precio_promedio_venta,
        1                           AS orden
    FROM detalle_ventas dv
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE dv.id_producto = @id_producto_promo
      AND v.fecha_venta BETWEEN DATE_SUB(@inicio_promo, INTERVAL 30 DAY) AND @inicio_promo
      AND v.estado != 'Cancelado'

    UNION ALL

    SELECT
        'Durante la promoción',
        COUNT(dv.id_detalle),
        SUM(dv.cantidad),
        SUM(dv.cantidad * dv.precio_unitario_congelado),
        ROUND(AVG(dv.precio_unitario_congelado), 2),
        2
    FROM detalle_ventas dv
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE dv.id_producto = @id_producto_promo
      AND v.fecha_venta BETWEEN @inicio_promo AND @fin_promo
      AND v.estado != 'Cancelado'

    UNION ALL

    SELECT
        'Después de la promoción',
        COUNT(dv.id_detalle),
        SUM(dv.cantidad),
        SUM(dv.cantidad * dv.precio_unitario_congelado),
        ROUND(AVG(dv.precio_unitario_congelado), 2),
        3
    FROM detalle_ventas dv
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE dv.id_producto = @id_producto_promo
      AND v.fecha_venta BETWEEN @fin_promo AND DATE_ADD(@fin_promo, INTERVAL 30 DAY)
      AND v.estado != 'Cancelado'
) AS comparativa
ORDER BY orden;


-- 15. Análisis de Cohort: retención de clientes mes a mes desde su primera compra.
WITH primera_compra AS (
    SELECT
        id_cliente,
        DATE_FORMAT(MIN(fecha_venta), '%Y-%m') AS cohorte_mes
    FROM ventas
    WHERE estado NOT IN ('Cancelado', 'Pendiente de Pago')
    GROUP BY id_cliente
),
actividad AS (
    SELECT
        pc.id_cliente,
        pc.cohorte_mes,
        DATE_FORMAT(v.fecha_venta, '%Y-%m') AS mes_actividad,
        TIMESTAMPDIFF(MONTH,
            STR_TO_DATE(CONCAT(pc.cohorte_mes, '-01'), '%Y-%m-%d'),
            STR_TO_DATE(CONCAT(DATE_FORMAT(v.fecha_venta, '%Y-%m'), '-01'), '%Y-%m-%d')
        ) AS mes_numero
    FROM primera_compra pc
    INNER JOIN ventas v ON pc.id_cliente = v.id_cliente
    WHERE v.estado NOT IN ('Cancelado', 'Pendiente de Pago')
)
SELECT
    cohorte_mes                                     AS cohorte,
    COUNT(DISTINCT CASE WHEN mes_numero = 0 THEN id_cliente END) AS mes_0_nuevos,
    COUNT(DISTINCT CASE WHEN mes_numero = 1 THEN id_cliente END) AS mes_1_retornaron,
    COUNT(DISTINCT CASE WHEN mes_numero = 2 THEN id_cliente END) AS mes_2_retornaron,
    COUNT(DISTINCT CASE WHEN mes_numero = 3 THEN id_cliente END) AS mes_3_retornaron,
    ROUND(
        COUNT(DISTINCT CASE WHEN mes_numero = 1 THEN id_cliente END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN mes_numero = 0 THEN id_cliente END), 0)
    , 1)                                            AS retencion_mes1_pct
FROM actividad
GROUP BY cohorte_mes
ORDER BY cohorte_mes;


-- 16. Margen de Beneficio por Producto: margen calculado a partir de precio y costo.
SELECT
    p.id_producto,
    p.nombre,
    cat.nombre                                      AS categoria,
    p.precio,
    p.costo,
    (p.precio - p.costo)                            AS ganancia_unitaria,
    ROUND((p.precio - p.costo) / p.precio * 100, 2) AS margen_pct,
    COALESCE(SUM(dv.cantidad), 0)                   AS unidades_vendidas,
    COALESCE(SUM(dv.cantidad) * (p.precio - p.costo), 0) AS ganancia_total,
    CASE
        WHEN (p.precio - p.costo) / p.precio * 100 >= 50 THEN 'Margen alto'
        WHEN (p.precio - p.costo) / p.precio * 100 >= 30 THEN 'Margen medio'
        ELSE 'Margen bajo'
    END                                             AS clasificacion_margen
FROM
    productos p
    LEFT JOIN categorias cat ON p.id_categoria = cat.id_categoria
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
WHERE
    p.activo = 1
GROUP BY
    p.id_producto, p.nombre, cat.nombre, p.precio, p.costo
ORDER BY
    margen_pct DESC;


-- 17. Tiempo Promedio Entre Compras: tiempo medio que tarda un cliente en volver a comprar.
WITH compras_ordenadas AS (
    SELECT
        id_cliente,
        fecha_venta,
        LAG(fecha_venta) OVER (PARTITION BY id_cliente ORDER BY fecha_venta) AS compra_anterior
    FROM ventas
    WHERE estado NOT IN ('Cancelado', 'Pendiente de Pago')
)
SELECT
    c.id_cliente,
    CONCAT(c.nombre, ' ', c.apellido)              AS cliente,
    COUNT(co.fecha_venta)                           AS total_compras,
    ROUND(AVG(DATEDIFF(co.fecha_venta, co.compra_anterior)), 0) AS dias_promedio_entre_compras,
    MIN(co.fecha_venta)                             AS primera_compra,
    MAX(co.fecha_venta)                             AS ultima_compra
FROM
    compras_ordenadas co
    INNER JOIN clientes c ON co.id_cliente = c.id_cliente
WHERE
    co.compra_anterior IS NOT NULL
GROUP BY
    c.id_cliente, c.nombre, c.apellido
HAVING
    COUNT(co.fecha_venta) >= 2
ORDER BY
    dias_promedio_entre_compras ASC;


-- 18. Productos Más Vistos vs. Comprados: comparar ranking de compras con precio/stock.
SELECT
    p.id_producto,
    p.nombre,
    RANK() OVER (ORDER BY COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) DESC)
                                                    AS ranking_compras,
    COALESCE(SUM(dv.cantidad), 0)                   AS unidades_vendidas,
    COALESCE(SUM(dv.cantidad * dv.precio_unitario_congelado), 0) AS ingresos,
    RANK() OVER (ORDER BY p.precio DESC)            AS ranking_precio,
    p.precio,
    p.stock,
    CASE
        WHEN COALESCE(SUM(dv.cantidad), 0) = 0 AND p.stock > 0
            THEN 'Visible pero no comprado'
        WHEN COALESCE(SUM(dv.cantidad), 0) > 0
            THEN 'Activo'
        ELSE 'Sin actividad'
    END                                             AS estado_comercial
FROM
    productos p
    LEFT JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    LEFT JOIN ventas v ON dv.id_venta = v.id_venta AND v.estado != 'Cancelado'
WHERE
    p.activo = 1
GROUP BY
    p.id_producto, p.nombre, p.precio, p.stock
ORDER BY
    ranking_compras;


-- 19. Segmentación de Clientes (RFM): clasificación por Recencia, Frecuencia y Monetario.
WITH metricas_rfm AS (
    SELECT
        c.id_cliente,
        CONCAT(c.nombre, ' ', c.apellido)           AS cliente,
        c.email,
        DATEDIFF(NOW(), MAX(v.fecha_venta))          AS dias_desde_ultima_compra,
        COUNT(DISTINCT v.id_venta)                   AS frecuencia,
        SUM(v.total)                                 AS monetario
    FROM clientes c
    INNER JOIN ventas v ON c.id_cliente = v.id_cliente
    WHERE v.estado NOT IN ('Cancelado', 'Pendiente de Pago')
    GROUP BY c.id_cliente, c.nombre, c.apellido, c.email
),
puntuaciones AS (
    SELECT
        *,
        NTILE(3) OVER (ORDER BY dias_desde_ultima_compra DESC)  AS score_r,
        NTILE(3) OVER (ORDER BY frecuencia ASC)                 AS score_f,
        NTILE(3) OVER (ORDER BY monetario ASC)                  AS score_m
    FROM metricas_rfm
)
SELECT
    id_cliente,
    cliente,
    email,
    dias_desde_ultima_compra,
    frecuencia,
    ROUND(monetario, 2)                             AS monetario,
    score_r,
    score_f,
    score_m,
    (score_r + score_f + score_m)                   AS rfm_total,
    CASE
        WHEN (score_r + score_f + score_m) = 9       THEN 'Campeones'
        WHEN (score_r + score_f + score_m) >= 7      THEN 'Leales'
        WHEN (score_r + score_f + score_m) >= 5      THEN 'En riesgo'
        WHEN score_r = 3 AND score_f <= 2            THEN 'Prometedores'
        ELSE                                              'Hibernando'
    END                                             AS segmento_rfm
FROM puntuaciones
ORDER BY rfm_total DESC;


-- 20. Predicción de Demanda Simple: proyección de ventas del próximo mes por categoría (promedio móvil).
WITH ventas_mensuales_cat AS (
    SELECT
        cat.id_categoria,
        cat.nombre                                  AS categoria,
        YEAR(v.fecha_venta)                         AS anio,
        MONTH(v.fecha_venta)                        AS mes,
        SUM(dv.cantidad)                            AS unidades_mes
    FROM categorias cat
    INNER JOIN productos p   ON cat.id_categoria  = p.id_categoria
    INNER JOIN detalle_ventas dv ON p.id_producto = dv.id_producto
    INNER JOIN ventas v ON dv.id_venta = v.id_venta
    WHERE v.estado NOT IN ('Cancelado')
    GROUP BY cat.id_categoria, cat.nombre, YEAR(v.fecha_venta), MONTH(v.fecha_venta)
),
promedios AS (
    SELECT
        id_categoria,
        categoria,
        ROUND(AVG(unidades_mes) OVER (
            PARTITION BY id_categoria
            ORDER BY anio, mes
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 0)                                       AS promedio_movil_3m,
        anio,
        mes,
        unidades_mes,
        ROW_NUMBER() OVER (PARTITION BY id_categoria ORDER BY anio DESC, mes DESC) AS fila
    FROM ventas_mensuales_cat
)
SELECT
    id_categoria,
    categoria,
    anio                                            AS ultimo_anio_datos,
    mes                                             AS ultimo_mes_datos,
    unidades_mes                                    AS ventas_ultimo_mes,
    promedio_movil_3m                               AS prediccion_proximo_mes,
    ROUND((promedio_movil_3m - unidades_mes) / NULLIF(unidades_mes, 0) * 100, 1)
                                                    AS variacion_esperada_pct
FROM promedios
WHERE fila = 1
ORDER BY prediccion_proximo_mes DESC;
