-- =====================================================================
-- 01_staging_y_limpieza.sql
-- Proyecto : Bank Customer Churn Analytics
-- Motor    : PostgreSQL
-- Objetivo : (1) chequeos de calidad sobre la tabla staging ya cargada
--            (2) crear la tabla limpia con tipos correctos y PK
--            (3) chequeos de calidad sobre la tabla limpia
-- Requiere : 00_crear_staging.sql ejecutado Y el CSV ya importado en stg_churn.
-- Orden    : 00 -> importar CSV -> 01 -> 02 -> 03 -> ...
-- Este script ya NO crea ni borra stg_churn (antes lo hacía y podía perder datos).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. PROTECCIÓN: no continuar si el staging está vacío
--    Evita crear una tabla limpia vacía por ejecutar este script antes de
--    importar el CSV. Si falla, importa el CSV (ver 00_crear_staging.sql).
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM stg_churn) = 0 THEN
        RAISE EXCEPTION 'stg_churn está vacía: importa el CSV antes de ejecutar este script (ver 00_crear_staging.sql)';
    END IF;
END $$;


-- ---------------------------------------------------------------------
-- 2. CHEQUEO RÁPIDO DE LA CARGA
--    Debe devolver ~10 000 filas. Anota el número en el README.
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS filas_cargadas FROM stg_churn;

-- Vista previa: revisa que las columnas quedaron en su sitio.
SELECT * FROM stg_churn LIMIT 5;


-- ---------------------------------------------------------------------
-- 3. CHEQUEOS DE CALIDAD SOBRE STAGING (antes de convertir tipos)
-- ---------------------------------------------------------------------

-- 3.1 Nulos o vacíos por columna.
--     Un valor "vacío" en un CSV llega como NULL o como cadena ''.
SELECT
    COUNT(*) FILTER (WHERE NULLIF(TRIM(customerid), '')      IS NULL) AS nulos_customerid,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(creditscore), '')     IS NULL) AS nulos_creditscore,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(geography), '')       IS NULL) AS nulos_geography,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(gender), '')          IS NULL) AS nulos_gender,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(age), '')             IS NULL) AS nulos_age,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(tenure), '')          IS NULL) AS nulos_tenure,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(balance), '')         IS NULL) AS nulos_balance,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(numofproducts), '')   IS NULL) AS nulos_numofproducts,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(hascrcard), '')       IS NULL) AS nulos_hascrcard,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(isactivemember), '')  IS NULL) AS nulos_isactivemember,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(estimatedsalary), '') IS NULL) AS nulos_estimatedsalary,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(exited), '')          IS NULL) AS nulos_exited
FROM stg_churn;

-- 3.2 Duplicados por customerid (debe devolver 0 filas si todo está bien).
SELECT customerid, COUNT(*) AS veces
FROM stg_churn
GROUP BY customerid
HAVING COUNT(*) > 1;

-- 3.3 Valores que NO se pueden convertir a número.
--     Patrón: entero con signo opcional (edad, tenure, etc.) o decimal (balance, salario).
SELECT
    COUNT(*) FILTER (WHERE creditscore     !~ '^-?\d+$')            AS creditscore_no_entero,
    COUNT(*) FILTER (WHERE age             !~ '^-?\d+$')            AS age_no_entero,
    COUNT(*) FILTER (WHERE tenure          !~ '^-?\d+$')            AS tenure_no_entero,
    COUNT(*) FILTER (WHERE numofproducts   !~ '^-?\d+$')            AS numofproducts_no_entero,
    COUNT(*) FILTER (WHERE balance         !~ '^-?\d+(\.\d+)?$')    AS balance_no_numerico,
    COUNT(*) FILTER (WHERE estimatedsalary !~ '^-?\d+(\.\d+)?$')    AS salary_no_numerico
FROM stg_churn;
-- Si algún contador sale > 0, inspecciona esas filas antes de seguir
-- (por ejemplo: SELECT * FROM stg_churn WHERE age !~ '^-?\d+$';).

-- 3.4 Valores distintos de las columnas categóricas / binarias.
--     Esperado: exited, hascrcard, isactivemember en {0,1}; 3 países; 2 géneros.
SELECT 'geography' AS columna, geography AS valor, COUNT(*) AS filas FROM stg_churn GROUP BY geography
UNION ALL
SELECT 'gender', gender, COUNT(*) FROM stg_churn GROUP BY gender
UNION ALL
SELECT 'exited', exited, COUNT(*) FROM stg_churn GROUP BY exited
UNION ALL
SELECT 'hascrcard', hascrcard, COUNT(*) FROM stg_churn GROUP BY hascrcard
UNION ALL
SELECT 'isactivemember', isactivemember, COUNT(*) FROM stg_churn GROUP BY isactivemember
UNION ALL
SELECT 'numofproducts', numofproducts, COUNT(*) FROM stg_churn GROUP BY numofproducts
ORDER BY columna, valor;


-- ---------------------------------------------------------------------
-- 4. TABLA LIMPIA con tipos correctos y PRIMARY KEY
--    Se descartan rownumber (índice sin significado) y surname (no aporta
--    al análisis y es un dato personal innecesario).
--    Si los chequeos 3.x encontraron problemas, decide aquí cómo tratarlos
--    y documenta la decisión en el README.
-- ---------------------------------------------------------------------
-- CASCADE elimina también las vistas que dependen de la tabla (vw_churn_segmentado
-- de 02 y las vw_* de 06). Si rehaces la limpieza, vuelve a ejecutar 02 y 06.
-- El staging (stg_churn) NO se toca.
DROP TABLE IF EXISTS churn_clientes CASCADE;

CREATE TABLE churn_clientes (
    customer_id       INTEGER       PRIMARY KEY,
    credit_score      SMALLINT      NOT NULL,
    geography         VARCHAR(20)   NOT NULL,
    gender            VARCHAR(10)   NOT NULL,
    age               SMALLINT      NOT NULL,
    tenure            SMALLINT      NOT NULL,
    balance           NUMERIC(12,2) NOT NULL,
    num_of_products   SMALLINT      NOT NULL,
    has_cr_card       SMALLINT      NOT NULL,
    is_active_member  SMALLINT      NOT NULL,
    estimated_salary  NUMERIC(12,2) NOT NULL,
    exited            SMALLINT      NOT NULL
);

INSERT INTO churn_clientes
SELECT
    TRIM(customerid)::INTEGER,
    TRIM(creditscore)::SMALLINT,
    TRIM(geography),
    TRIM(gender),
    TRIM(age)::SMALLINT,
    TRIM(tenure)::SMALLINT,
    TRIM(balance)::NUMERIC(12,2),
    TRIM(numofproducts)::SMALLINT,
    TRIM(hascrcard)::SMALLINT,
    TRIM(isactivemember)::SMALLINT,
    TRIM(estimatedsalary)::NUMERIC(12,2),
    TRIM(exited)::SMALLINT
FROM stg_churn;
-- Si este INSERT falla por una conversión o por la PK duplicada, vuelve a
-- los chequeos 3.2 y 3.3: ahí está la fila problemática.


-- ---------------------------------------------------------------------
-- 5. CHEQUEOS DE CALIDAD SOBRE LA TABLA LIMPIA
-- ---------------------------------------------------------------------

-- 5.1 Conteo final (compara con filas_cargadas del paso 2).
SELECT COUNT(*) AS filas_limpias FROM churn_clientes;

-- 5.2 Rangos válidos. Todos los contadores deben salir en 0.
--     Los umbrales son razonables para este dataset; si algún rango real
--     difiere (p. ej. edad máxima), justifica el criterio en el README.
SELECT
    COUNT(*) FILTER (WHERE age NOT BETWEEN 18 AND 100)            AS age_fuera_rango,
    COUNT(*) FILTER (WHERE credit_score NOT BETWEEN 300 AND 850)  AS score_fuera_rango,
    COUNT(*) FILTER (WHERE tenure NOT BETWEEN 0 AND 10)           AS tenure_fuera_rango,
    COUNT(*) FILTER (WHERE balance < 0)                           AS balance_negativo,
    COUNT(*) FILTER (WHERE estimated_salary < 0)                  AS salario_negativo,
    COUNT(*) FILTER (WHERE num_of_products NOT BETWEEN 1 AND 4)   AS productos_fuera_rango,
    COUNT(*) FILTER (WHERE exited          NOT IN (0, 1))         AS exited_invalido,
    COUNT(*) FILTER (WHERE has_cr_card     NOT IN (0, 1))         AS crcard_invalido,
    COUNT(*) FILTER (WHERE is_active_member NOT IN (0, 1))        AS active_invalido
FROM churn_clientes;

-- 5.3 Mínimos y máximos reales de las variables numéricas
--     (para conocer el dataset y fijar los cortes de segmentación en 02).
SELECT
    MIN(age) AS age_min, MAX(age) AS age_max,
    MIN(credit_score) AS score_min, MAX(credit_score) AS score_max,
    MIN(tenure) AS tenure_min, MAX(tenure) AS tenure_max,
    MIN(balance) AS balance_min, MAX(balance) AS balance_max,
    MIN(estimated_salary) AS salary_min, MAX(estimated_salary) AS salary_max,
    MIN(num_of_products) AS productos_min, MAX(num_of_products) AS productos_max
FROM churn_clientes;

-- 5.4 Churn global (punto de referencia para todo el proyecto).
SELECT
    COUNT(*)                                   AS total_clientes,
    SUM(exited)                                AS clientes_fugados,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2)   AS churn_rate_pct
FROM churn_clientes;

-- ---------------------------------------------------------------------
-- RESULTADOS PARA EL README (completa tú tras ejecutar):
--   filas cargadas       : ____
--   nulos                : ____
--   duplicados           : ____
--   fuera de rango       : ____
--   churn global         : ____ %
-- Aunque den "sin problemas", documéntalo.
-- ---------------------------------------------------------------------