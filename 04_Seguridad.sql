-- ============================================================================
-- 04_Seguridad.sql
-- Proyecto de Base de Datos para un E-commerce
-- ----------------------------------------------------------------------------
-- Contenido: creación de roles, usuarios y asignación de permisos
-- (CREATE ROLE, CREATE USER, GRANT, REVOKE) y vistas de seguridad.
-- ORDEN DE EJECUCIÓN: ejecutar después de 01_Esquema_y_Datos.sql.
--
-- NOTA: el nombre de la base de datos es 'proyecto' (definido en 01).
--       Todas las referencias usan 'proyecto.<tabla>'.
-- ============================================================================

USE proyecto;


-- ============================================================
-- ROLES Y SUS PERMISOS
-- ============================================================

DROP ROLE IF EXISTS
    'Administrador_Sistema',
    'Gerente_Marketing',
    'Analista_Datos',
    'Empleado_Inventario',
    'Atencion_Cliente',
    'Auditor_Financiero',
    'Visitante';

-- 1. Administrador_Sistema: todos los privilegios.
CREATE ROLE 'Administrador_Sistema';
GRANT ALL PRIVILEGES ON proyecto.* TO 'Administrador_Sistema';

-- 2. Gerente_Marketing: solo lectura sobre ventas y clientes (y productos).
CREATE ROLE 'Gerente_Marketing';
GRANT SELECT ON proyecto.ventas    TO 'Gerente_Marketing';
GRANT SELECT ON proyecto.clientes  TO 'Gerente_Marketing';
GRANT SELECT ON proyecto.productos TO 'Gerente_Marketing';

-- 3. Analista_Datos: solo lectura sobre todas las tablas (excepto auditoría).
CREATE ROLE 'Analista_Datos';
GRANT SELECT ON proyecto.categorias            TO 'Analista_Datos';
GRANT SELECT ON proyecto.proveedores           TO 'Analista_Datos';
GRANT SELECT ON proyecto.clientes              TO 'Analista_Datos';
GRANT SELECT ON proyecto.productos             TO 'Analista_Datos';
GRANT SELECT ON proyecto.ventas                TO 'Analista_Datos';
GRANT SELECT ON proyecto.detalle_ventas        TO 'Analista_Datos';
GRANT SELECT ON proyecto.resumen_ventas_diario TO 'Analista_Datos';
GRANT SELECT ON proyecto.kpis_mensuales        TO 'Analista_Datos';
GRANT SELECT ON proyecto.ranking_productos     TO 'Analista_Datos';
GRANT SELECT ON proyecto.carritos              TO 'Analista_Datos';
GRANT SELECT ON proyecto.resenas_productos     TO 'Analista_Datos';

-- 4. Empleado_Inventario: solo puede modificar la tabla productos (stock y ubicación).
CREATE ROLE 'Empleado_Inventario';
GRANT SELECT ON proyecto.productos   TO 'Empleado_Inventario';
GRANT UPDATE (stock, stock_minimo, peso_kg, activo, fecha_modificacion)
           ON proyecto.productos     TO 'Empleado_Inventario';
GRANT SELECT ON proyecto.categorias    TO 'Empleado_Inventario';
GRANT SELECT ON proyecto.alertas_stock TO 'Empleado_Inventario';

-- 5. Atencion_Cliente: puede ver clientes y ventas, pero no modificar precios.
CREATE ROLE 'Atencion_Cliente';
GRANT SELECT ON proyecto.clientes       TO 'Atencion_Cliente';
GRANT SELECT ON proyecto.ventas         TO 'Atencion_Cliente';
GRANT SELECT ON proyecto.detalle_ventas TO 'Atencion_Cliente';
GRANT SELECT ON proyecto.productos      TO 'Atencion_Cliente';
GRANT UPDATE (estado, notas) ON proyecto.ventas TO 'Atencion_Cliente';

-- 6. Auditor_Financiero: solo lectura sobre ventas, productos y logs de precios.
CREATE ROLE 'Auditor_Financiero';
GRANT SELECT ON proyecto.ventas            TO 'Auditor_Financiero';
GRANT SELECT ON proyecto.detalle_ventas    TO 'Auditor_Financiero';
GRANT SELECT ON proyecto.productos         TO 'Auditor_Financiero';
GRANT SELECT ON proyecto.auditoria_precios TO 'Auditor_Financiero';
GRANT SELECT ON proyecto.kpis_mensuales    TO 'Auditor_Financiero';

-- 17. Visitante: solo puede ver la tabla productos (y categorías).
CREATE ROLE 'Visitante';
GRANT SELECT ON proyecto.productos   TO 'Visitante';
GRANT SELECT ON proyecto.categorias  TO 'Visitante';


-- ============================================================
-- USUARIOS Y ASIGNACIÓN DE ROLES
-- (incluye política de contraseñas seguras: expiración y bloqueo)
-- ============================================================

-- 7. admin_user -> Administrador_Sistema
DROP USER IF EXISTS 'admin_user'@'localhost';
CREATE USER 'admin_user'@'localhost'
    IDENTIFIED BY 'Admin@Secure2024!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
GRANT 'Administrador_Sistema' TO 'admin_user'@'localhost';
SET DEFAULT ROLE 'Administrador_Sistema' TO 'admin_user'@'localhost';

-- 8. marketing_user -> Gerente_Marketing
DROP USER IF EXISTS 'marketing_user'@'%';
CREATE USER 'marketing_user'@'%'
    IDENTIFIED BY 'Market@Pass2024!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
GRANT 'Gerente_Marketing' TO 'marketing_user'@'%';
SET DEFAULT ROLE 'Gerente_Marketing' TO 'marketing_user'@'%';

-- 9. inventario_user -> Empleado_Inventario
DROP USER IF EXISTS 'inventario_user'@'%';
CREATE USER 'inventario_user'@'%'
    IDENTIFIED BY 'Invent@Pass2024!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
GRANT 'Empleado_Inventario' TO 'inventario_user'@'%';
SET DEFAULT ROLE 'Empleado_Inventario' TO 'inventario_user'@'%';

-- 10. support_user -> Atencion_Cliente
DROP USER IF EXISTS 'support_user'@'%';
CREATE USER 'support_user'@'%'
    IDENTIFIED BY 'Support@Pass2024!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
GRANT 'Atencion_Cliente' TO 'support_user'@'%';
SET DEFAULT ROLE 'Atencion_Cliente' TO 'support_user'@'%';

-- analista_user -> Analista_Datos
DROP USER IF EXISTS 'analista_user'@'%';
CREATE USER 'analista_user'@'%'
    IDENTIFIED BY 'Analyst@Pass2024!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
GRANT 'Analista_Datos' TO 'analista_user'@'%';
SET DEFAULT ROLE 'Analista_Datos' TO 'analista_user'@'%';

-- auditor_user -> Auditor_Financiero
DROP USER IF EXISTS 'auditor_user'@'%';
CREATE USER 'auditor_user'@'%'
    IDENTIFIED BY 'Audit@Pass2024!'
    PASSWORD EXPIRE INTERVAL 90 DAY
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1;
GRANT 'Auditor_Financiero' TO 'auditor_user'@'%';
SET DEFAULT ROLE 'Auditor_Financiero' TO 'auditor_user'@'%';


-- ============================================================
-- RESTRICCIONES Y PERMISOS ESPECÍFICOS
-- ============================================================

-- 11. Impedir que Analista_Datos ejecute DELETE (ni TRUNCATE, que requiere DROP).
REVOKE DELETE ON proyecto.* FROM 'Analista_Datos';

-- 12. Permitir a Gerente_Marketing ejecutar procedimientos de reportes de marketing.
--     (Estos procedimientos se crean en 07_Procedimientos_Almacenados.sql)
GRANT EXECUTE ON PROCEDURE proyecto.sp_GenerarReporteMensualVentas TO 'Gerente_Marketing';
GRANT EXECUTE ON PROCEDURE proyecto.sp_ObtenerDashboardAdmin        TO 'Gerente_Marketing';

-- 14. Revocar UPDATE sobre la columna precio de productos a Empleado_Inventario.
--     (El rol ya solo recibió UPDATE sobre stock/stock_minimo/peso_kg/activo,
--      por lo que nunca tuvo permiso sobre 'precio'. Se reafirma el alcance.)
REVOKE UPDATE ON proyecto.productos FROM 'Empleado_Inventario';
GRANT UPDATE (stock, stock_minimo, peso_kg, activo, fecha_modificacion)
    ON proyecto.productos TO 'Empleado_Inventario';


-- ============================================================
-- 13. VISTA QUE OCULTA INFORMACIÓN SENSIBLE DE CLIENTES
-- ============================================================
DROP VIEW IF EXISTS v_info_clientes_basica;
CREATE VIEW v_info_clientes_basica AS
    SELECT
        id_cliente,
        nombre,
        apellido,
        CONCAT(LEFT(email, 1), '***', SUBSTRING(email, LOCATE('@', email))) AS email_parcial,
        direccion_envio,
        fecha_registro,
        total_gastado,
        ultima_compra
    FROM clientes;

GRANT SELECT ON proyecto.v_info_clientes_basica TO 'Atencion_Cliente';


-- ============================================================
-- 16. ASEGURAR QUE root NO SE USE DESDE CONEXIONES REMOTAS
-- ============================================================
-- Elimina cualquier cuenta root cuyo host no sea localhost.
DELETE FROM mysql.user
    WHERE User = 'root' AND Host != 'localhost';

ALTER USER 'root'@'localhost'
    IDENTIFIED BY 'R00t@VerySecure2024!'
    PASSWORD EXPIRE INTERVAL 180 DAY;

FLUSH PRIVILEGES;


-- ============================================================
-- 18. LIMITAR CONSULTAS POR HORA PARA Analista_Datos
-- ============================================================
ALTER USER 'analista_user'@'%'
    WITH MAX_QUERIES_PER_HOUR 500
         MAX_CONNECTIONS_PER_HOUR 10
         MAX_USER_CONNECTIONS 3;


-- ============================================================
-- 19. VISTA POR SUCURSAL: cada usuario solo ve las ventas de su sucursal
-- ============================================================
DROP VIEW IF EXISTS v_ventas_por_sucursal;
CREATE VIEW v_ventas_por_sucursal AS
    SELECT
        v.id_venta,
        v.fecha_venta,
        v.estado,
        v.total,
        v.id_cliente,
        v.id_sucursal,
        s.nombre AS nombre_sucursal
    FROM ventas v
    INNER JOIN sucursales s ON v.id_sucursal = s.id_sucursal
    WHERE v.id_sucursal = (
        SELECT id_sucursal
        FROM usuarios_sistema
        WHERE username = CURRENT_USER()
        LIMIT 1
    );

GRANT SELECT ON proyecto.v_ventas_por_sucursal TO 'Atencion_Cliente';
GRANT SELECT ON proyecto.v_ventas_por_sucursal TO 'Gerente_Marketing';


-- ============================================================
-- 20. AUDITORÍA DE INTENTOS DE INICIO DE SESIÓN FALLIDOS
-- ============================================================
-- La tabla log_intentos_fallidos se crea en 01_Esquema_y_Datos.sql.
-- (En producción, los intentos fallidos se capturan con el plugin de
--  auditoría de MySQL Enterprise o con el componente audit_log.)
CREATE TABLE IF NOT EXISTS log_intentos_fallidos (
    id_log        INT          NOT NULL AUTO_INCREMENT,
    usuario       VARCHAR(100) NOT NULL,
    host_origen   VARCHAR(100) NOT NULL,
    fecha_intento TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_log)
) ENGINE=InnoDB;


-- ============================================================
-- CONSULTAS DE VERIFICACIÓN DE SEGURIDAD
-- ============================================================

SELECT User, Host, account_locked, password_expired
FROM mysql.user
WHERE User IN ('admin_user','marketing_user','inventario_user',
               'support_user','analista_user','auditor_user')
ORDER BY User;

SHOW GRANTS FOR 'Gerente_Marketing';
SHOW GRANTS FOR 'marketing_user'@'%';

SELECT TABLE_NAME, VIEW_DEFINITION
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'proyecto';
