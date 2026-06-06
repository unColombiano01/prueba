# Proyecto de Base de Datos para un E-commerce

Base de datos `proyecto` para una tienda en línea: gestiona productos, inventario,
clientes y el ciclo de vida de las ventas, con consultas analíticas, funciones,
seguridad, triggers, eventos y procedimientos almacenados.

> Motor objetivo: **MySQL 8.0+** (se usan CTEs, funciones de ventana, roles y eventos).

## Integrantes

- (Completar con los nombres del equipo)

## Estructura de archivos

Todos los scripts están en la raíz y deben ejecutarse **en orden numérico**:

| Orden | Archivo | Contenido |
|-------|---------|-----------|
| 1 | `01_Esquema_y_Datos.sql` | `CREATE DATABASE`, todas las tablas, índices y datos de ejemplo (`INSERT`). |
| 2 | `02_Consultas_Avanzadas.sql` | Las 20 consultas de análisis y reporteo. |
| 3 | `03_Funciones.sql` | Las 20 funciones definidas por el usuario (UDFs). |
| 4 | `04_Seguridad.sql` | Roles, usuarios, permisos (`GRANT`/`REVOKE`) y vistas de seguridad. |
| 5 | `05_Triggers.sql` | Los 20 triggers (más tablas de auditoría ya creadas en el paso 1). |
| 6 | `06_Eventos.sql` | Activación del `event_scheduler` y los 20 eventos programados. |
| 7 | `07_Procedimientos_Almacenados.sql` | Los 20 procedimientos almacenados. |

## Instrucciones de ejecución

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql   # ver nota 1
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
```

O dentro del cliente MySQL:

```sql
SOURCE 01_Esquema_y_Datos.sql;
SOURCE 02_Consultas_Avanzadas.sql;
SOURCE 03_Funciones.sql;
SOURCE 07_Procedimientos_Almacenados.sql;
SOURCE 04_Seguridad.sql;
SOURCE 05_Triggers.sql;
SOURCE 06_Eventos.sql;
```

## Notas técnicas (correcciones aplicadas al código original)

1. **Orden 04 vs 07:** `04_Seguridad.sql` otorga `GRANT EXECUTE` sobre los
   procedimientos `sp_GenerarReporteMensualVentas` y `sp_ObtenerDashboardAdmin`.
   Esos procedimientos se crean en `07`, por lo que conviene ejecutar **07 antes
   que 04** (como se muestra arriba). Si se respeta el orden 01→07 estricto del
   documento, esos dos `GRANT` fallarían por procedimiento inexistente.
2. **Nombre de la base de datos:** el código original mezclaba `proyecto`
   (en `CREATE DATABASE` / `USE`) con `ecommerce_db` (en seguridad, eventos y
   verificaciones). Se unificó **todo a `proyecto`** para que sea ejecutable.
3. **Trigger de permisos (`trg_log_permission_changes`):** MySQL **no permite**
   crear triggers sobre tablas del sistema (`mysql.user`). Se reimplementó como
   trigger `AFTER INSERT` sobre `usuarios_sistema`, registrando en
   `auditoria_permisos`.
4. **Evento `evt_suspend_inactive_accounts_quarterly`:** la tabla `clientes` no
   tiene columna `activo`; el evento ahora registra una alerta de cuenta inactiva
   en lugar de actualizar una columna inexistente.
5. **Privilegios:** ejecutar `04_Seguridad.sql` requiere un usuario con permisos
   de administración (crear roles/usuarios y modificar `mysql.user`).
