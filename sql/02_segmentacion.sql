-- =====================================================================
-- 02_segmentacion.sql
-- Proyecto : Bank Customer Churn Analytics
-- Requiere : 01_staging_y_limpieza.sql ejecutado (tabla churn_clientes)
-- Objetivo : crear los grupos con CASE WHEN (edad, saldo, antigüedad)
--            y dejarlos en una vista base reutilizable por 03-06.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. ANTES DE FIJAR CORTES: mira la distribución real
--    Los cortes de saldo (bajo / medio / alto) no deben ser a ojo.
-- ---------------------------------------------------------------------

-- 1.1 ¿Cuántos clientes tienen saldo exactamente 0?
SELECT
    COUNT(*) FILTER (WHERE balance = 0) AS sin_saldo,
    COUNT(*) FILTER (WHERE balance > 0) AS con_saldo,
    ROUND(100.0 * COUNT(*) FILTER (WHERE balance = 0) / COUNT(*), 2) AS pct_sin_saldo
FROM churn_clientes;

-- 1.2 Percentiles del saldo entre quienes SÍ tienen saldo.
--     Úsalos para decidir los umbrales bajo / medio / alto.
SELECT
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY balance)::NUMERIC, 2) AS p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY balance)::NUMERIC, 2) AS p50,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY balance)::NUMERIC, 2) AS p75
FROM churn_clientes
WHERE balance > 0;

-- Los umbrales de abajo (100 000 y 140 000) son un PUNTO DE PARTIDA.
-- Cámbialos si los percentiles de 1.2 sugieren otros cortes razonables
-- y anota el criterio en el README.


-- ---------------------------------------------------------------------
-- 2. VISTA BASE CON SEGMENTOS
--    CASE WHEN evalúa en orden y se queda con el primer caso verdadero.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS vw_churn_segmentado;

CREATE VIEW vw_churn_segmentado AS
SELECT
    c.*,

    -- Grupo de edad
    CASE
        WHEN c.age <= 30 THEN '18-30'
        WHEN c.age <= 40 THEN '31-40'
        WHEN c.age <= 50 THEN '41-50'
        WHEN c.age <= 60 THEN '51-60'
        ELSE '60+'
    END AS age_group,

    -- Grupo de saldo ("Sin saldo" separado: es un grupo grande y distinto)
    CASE
        WHEN c.balance = 0        THEN '1-Sin saldo'
        WHEN c.balance < 100000   THEN '2-Bajo'
        WHEN c.balance < 140000   THEN '3-Medio'
        ELSE                           '4-Alto'
    END AS balance_group,

    -- Grupo de antigüedad (años en el banco)
    CASE
        WHEN c.tenure <= 2 THEN '0-2'
        WHEN c.tenure <= 5 THEN '3-5'
        WHEN c.tenure <= 8 THEN '6-8'
        ELSE '9-10'
    END AS tenure_group
FROM churn_clientes c;
-- Nota: el prefijo numérico en balance_group ("1-", "2-"...) solo sirve para
-- que se ordene bien en gráficos y tablas; puedes quitarlo en Power BI.


-- ---------------------------------------------------------------------
-- 3. VERIFICACIONES
-- ---------------------------------------------------------------------

-- 3.1 La vista debe tener las mismas filas que la tabla limpia.
SELECT
    (SELECT COUNT(*) FROM churn_clientes)     AS filas_tabla,
    (SELECT COUNT(*) FROM vw_churn_segmentado) AS filas_vista;

-- 3.2 Ningún cliente sin grupo (los CASE no dejan NULL por el ELSE; confirma).
SELECT
    COUNT(*) FILTER (WHERE age_group      IS NULL) AS sin_age_group,
    COUNT(*) FILTER (WHERE balance_group  IS NULL) AS sin_balance_group,
    COUNT(*) FILTER (WHERE tenure_group   IS NULL) AS sin_tenure_group
FROM vw_churn_segmentado;

-- 3.3 Tamaño de cada grupo (evita conclusiones sobre grupos diminutos).
SELECT 'age_group' AS dimension, age_group AS grupo, COUNT(*) AS clientes
FROM vw_churn_segmentado GROUP BY age_group
UNION ALL
SELECT 'balance_group', balance_group, COUNT(*)
FROM vw_churn_segmentado GROUP BY balance_group
UNION ALL
SELECT 'tenure_group', tenure_group, COUNT(*)
FROM vw_churn_segmentado GROUP BY tenure_group
ORDER BY dimension, grupo;

-- 3.4 Primera mirada: tasa de fuga por grupo de edad (adelanto del script 03).
SELECT
    age_group,
    COUNT(*)                                 AS clientes,
    SUM(exited)                              AS fugados,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
FROM vw_churn_segmentado
GROUP BY age_group
ORDER BY age_group;
-- Interpreta tú el resultado antes de seguir: ¿qué grupo destaca y por qué crees
-- que ocurre? Eso alimenta los hallazgos del README (con tus cifras reales).