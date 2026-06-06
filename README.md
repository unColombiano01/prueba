# Proyecto de Base de Datos para un E-commerce

Diseño del núcleo de una base de datos para una tienda en línea. El sistema
gestiona de forma eficiente y segura toda la información relacionada con los
**productos**, el **inventario**, los **clientes** y el **ciclo de vida de las
ventas**. La estructura es robusta, escalable y garantiza la integridad de los
datos en todo momento.

> **Motor objetivo:** MySQL 8.0+ (se usan CTEs, funciones de ventana, roles,
> triggers, eventos programados y procedimientos almacenados).
> **Nombre de la base de datos:** `proyecto`

---

## Integrantes

- (Completar con los nombres completos de los miembros del equipo)

---

## Descripción del sistema

La base de datos se centra en las siguientes entidades clave:

| Entidad | Propósito |
|---------|-----------|
| **Productos** | Catálogo de artículos disponibles para la venta. |
| **Categorías** | Sistema de clasificación para organizar los productos. |
| **Proveedores** | Entidades que suministran los productos. |
| **Clientes** | Usuarios registrados que realizan compras. |
| **Ventas** | Transacciones comerciales (encabezado de la orden). |
| **Detalle de Ventas** | Desglose de los productos incluidos en cada venta. |

### Relaciones principales

- **Categorías → Productos:** una categoría tiene muchos productos; un producto
  pertenece a una sola categoría (uno a muchos).
- **Proveedores → Productos:** un proveedor suministra muchos productos; un
  producto tiene un solo proveedor (uno a muchos).
- **Clientes → Ventas:** un cliente realiza muchas ventas; cada venta pertenece
  a un solo cliente (uno a muchos).
- **Ventas ↔ Productos:** relación de muchos a muchos resuelta mediante la tabla
  puente **Detalle de Ventas**, que guarda la `cantidad` y el
  `precio_unitario_congelado` (precio histórico en el momento de la compra).

---

## Estructura de archivos

Todos los scripts están en la **raíz** del repositorio. Cada archivo contiene
únicamente el código correspondiente a su nombre:

| # | Archivo | Contenido |
|---|---------|-----------|
| 1 | `01_Esquema_y_Datos.sql` | `CREATE DATABASE` + todas las sentencias `CREATE TABLE` (estructura completa), índices y todos los `INSERT INTO` con datos de ejemplo. |
| 2 | `02_Consultas_Avanzadas.sql` | Las **20 consultas** de análisis y reporteo, cada una precedida por un comentario con la pregunta de negocio que responde. |
| 3 | `03_Funciones.sql` | Las **20 funciones** definidas por el usuario (`CREATE FUNCTION`) + pruebas. |
| 4 | `04_Seguridad.sql` | Creación de roles, usuarios y asignación de permisos (`CREATE ROLE`, `CREATE USER`, `GRANT`, `REVOKE`) y vistas de seguridad. |
| 5 | `05_Triggers.sql` | Los **20 triggers** (`CREATE TRIGGER`). Las tablas de auditoría que usan se crean en el archivo 01. |
| 6 | `06_Eventos.sql` | Activación del `event_scheduler` y los **20 eventos** programados (`CREATE EVENT`). |
| 7 | `07_Procedimientos_Almacenados.sql` | Los **20 procedimientos almacenados** (`CREATE PROCEDURE`) + pruebas. |

### ¿Qué contiene cada archivo en detalle?

- **01 — Esquema y Datos:** tablas principales (`categorias`, `proveedores`,
  `clientes`, `productos`, `ventas`, `detalle_ventas`) y tablas de soporte
  (auditoría, alertas, carritos, reseñas, KPIs, sucursales, etc.), con sus
  claves foráneas, restricciones `CHECK`, índices y datos de prueba.
- **02 — Consultas Avanzadas:** Top productos, clientes VIP, ventas mensuales,
  rotación de inventario, RFM, cohortes, márgenes, predicción de demanda, etc.
- **03 — Funciones:** cálculo de totales, validación de stock, edad del cliente,
  costo de envío, descuentos, IVA, estado de lealtad, validación de email y
  contraseña, etc.
- **04 — Seguridad:** roles `Administrador_Sistema`, `Gerente_Marketing`,
  `Analista_Datos`, `Empleado_Inventario`, `Atencion_Cliente`,
  `Auditor_Financiero`, `Visitante`; usuarios asociados; vistas que ocultan
  información sensible y restricción de root remoto.
- **05 — Triggers:** auditoría de precios, control de stock, recálculo de
  totales, capitalización de nombres, validación de email, contador de
  productos por categoría, etc.
- **06 — Eventos:** reportes semanales/mensuales, limpieza de carritos, listas
  de reabastecimiento, recálculo de lealtad, detección de fraude, backups, etc.
- **07 — Procedimientos:** realizar venta, agregar producto, procesar
  devolución, registrar cliente, dashboard de administración, búsqueda de
  productos, fusionar cuentas, mover productos entre categorías, etc.

---

## Instrucciones de ejecución

El "trainer" puede clonar el repositorio y ejecutar los archivos en secuencia
para recrear la base de datos y validar todas las funcionalidades.

### Desde la terminal

```bash
mysql -u root -p < 01_Esquema_y_Datos.sql
mysql -u root -p < 02_Consultas_Avanzadas.sql
mysql -u root -p < 03_Funciones.sql
mysql -u root -p < 07_Procedimientos_Almacenados.sql   # ver Nota 1
mysql -u root -p < 04_Seguridad.sql
mysql -u root -p < 05_Triggers.sql
mysql -u root -p < 06_Eventos.sql
```

### Desde un cliente SQL (DBeaver / MySQL Workbench)

```sql
SOURCE 01_Esquema_y_Datos.sql;
SOURCE 02_Consultas_Avanzadas.sql;
SOURCE 03_Funciones.sql;
SOURCE 07_Procedimientos_Almacenados.sql;
SOURCE 04_Seguridad.sql;
SOURCE 05_Triggers.sql;
SOURCE 06_Eventos.sql;
```

> En DBeaver, ejecuta cada archivo con **"Execute SQL Script" (`Alt + X`)**,
> nunca con `Ctrl + Enter`, porque los archivos 03–07 usan `DELIMITER $$`.
> Luego pulsa **F5** sobre la base `proyecto` para ver tablas, funciones,
> procedimientos, triggers y eventos.

---

## Notas técnicas

1. **Orden 04 vs 07:** `04_Seguridad.sql` otorga `GRANT EXECUTE` sobre los
   procedimientos `sp_GenerarReporteMensualVentas` y `sp_ObtenerDashboardAdmin`,
   que se crean en `07`. Por eso conviene ejecutar **07 antes que 04**. Si se
   respeta el orden estricto 01→07, solo esos dos `GRANT` fallarían.
2. **Nombre unificado:** toda la base usa `proyecto` (`CREATE DATABASE` y `USE`).
3. **`trg_log_permission_changes`:** MySQL no permite triggers sobre tablas del
   sistema (`mysql.user`); se reimplementó sobre la tabla `usuarios_sistema`.
4. **`evt_suspend_inactive_accounts_quarterly`:** como `clientes` no tiene
   columna `activo`, el evento registra una alerta en lugar de modificar esa
   columna inexistente.
5. **Privilegios:** ejecutar `04_Seguridad.sql` requiere un usuario con permisos
   de administración (crear roles/usuarios y modificar `mysql.user`).
