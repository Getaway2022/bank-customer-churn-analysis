-- =====================================================================
-- 00_crear_staging.sql
-- Proyecto : Bank Customer Churn Analytics
-- Motor    : PostgreSQL
-- Objetivo : crear la tabla staging (todo TEXT) y cargar el CSV crudo.
--
-- ORDEN CORRECTO (importante):
--   1) Ejecutar ESTE script           -> crea stg_churn VACÍA
--   2) Importar el CSV en stg_churn    -> (ver opciones abajo)
--   3) Comprobar que hay ~10 000 filas -> consulta del final de este script
--   4) Recién entonces ejecutar 01_staging_y_limpieza.sql, 02, 03, ...
--
-- Este script NO borra nada: usa CREATE TABLE IF NOT EXISTS. Si ya cargaste
-- el CSV, volver a ejecutarlo no pierde datos.
-- =====================================================================

CREATE TABLE IF NOT EXISTS stg_churn (
    rownumber        TEXT,
    customerid       TEXT,
    surname          TEXT,
    creditscore      TEXT,
    geography        TEXT,
    gender           TEXT,
    age              TEXT,
    tenure           TEXT,
    balance          TEXT,
    numofproducts    TEXT,
    hascrcard        TEXT,
    isactivemember   TEXT,
    estimatedsalary  TEXT,
    exited           TEXT
);

-- ---------------------------------------------------------------------
-- CARGA DEL CSV: elige UNA de las dos opciones.
--
-- Opción A: \copy en psql (lee el archivo desde TU computadora).
--   Quita el -- del inicio y ajusta la ruta:
--
--   \copy stg_churn FROM 'data/Churn_Modelling.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
--
-- Opción B: asistente de importación de pgAdmin / DBeaver sobre stg_churn
--   (con encabezado, separador coma, codificación UTF8).
--
-- CUIDADO con importar dos veces: duplicarías las filas (20 000 en vez de
-- 10 000). Si necesitas recargar, primero vacía la tabla:
--
--   TRUNCATE stg_churn;
-- ---------------------------------------------------------------------

-- Comprobación posterior a la carga: debe devolver ~10 000.
SELECT COUNT(*) AS filas_en_staging FROM stg_churn;