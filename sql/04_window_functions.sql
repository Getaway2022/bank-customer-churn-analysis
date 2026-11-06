-- =====================================================================
-- 04_window_functions.sql
-- Proyecto : Bank Customer Churn Analytics
-- Requiere : 01 y 02 ejecutados (vista vw_churn_segmentado)
-- Objetivo : NTILE, PERCENT_RANK, RANK y LAG aplicados al churn.
-- Idea     : una window function calcula sobre un "conjunto de filas
--            relacionadas" SIN colapsarlas (a diferencia de GROUP BY).
--            Sintaxis: función() OVER (PARTITION BY ... ORDER BY ...)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. NTILE(4) SOBRE EL SALDO (cuartiles entre clientes CON saldo)
--    NTILE(4) reparte las filas ordenadas en 4 grupos del mismo tamaño:
--    1 = saldos más bajos ... 4 = saldos más altos.
--    Se excluye balance = 0: hay muchísimos ceros y NTILE los repartiría
--    entre cuartiles distintos con el mismo valor (los empates no se respetan).
--    Los clientes sin saldo se analizan aparte (ver al final de esta sección).
-- ---------------------------------------------------------------------
WITH cuartiles AS (
    SELECT
        customer_id,
        balance,
        exited,
        NTILE(4) OVER (ORDER BY balance) AS cuartil_saldo
    FROM vw_churn_segmentado
    WHERE balance > 0
)
SELECT
    cuartil_saldo,
    COUNT(*)                                 AS clientes,
    MIN(balance)                             AS saldo_min,
    MAX(balance)                             AS saldo_max,
    SUM(exited)                              AS fugados,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
FROM cuartiles
GROUP BY cuartil_saldo
ORDER BY cuartil_saldo;

-- Referencia: clientes sin saldo.
SELECT
    'Sin saldo'                              AS grupo,
    COUNT(*)                                 AS clientes,
    SUM(exited)                              AS fugados,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
FROM vw_churn_segmentado
WHERE balance = 0;


-- ---------------------------------------------------------------------
-- 2. NTILE(4) SOBRE EL CREDIT SCORE (todos los clientes)
--    1 = score más bajo ... 4 = score más alto.
-- ---------------------------------------------------------------------
WITH cuartiles AS (
    SELECT
        customer_id,
        credit_score,
        exited,
        NTILE(4) OVER (ORDER BY credit_score) AS cuartil_score
    FROM vw_churn_segmentado
)
SELECT
    cuartil_score,
    COUNT(*)                                 AS clientes,
    MIN(credit_score)                        AS score_min,
    MAX(credit_score)                        AS score_max,
    SUM(exited)                              AS fugados,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
FROM cuartiles
GROUP BY cuartil_score
ORDER BY cuartil_score;


-- ---------------------------------------------------------------------
-- 3. PERCENT_RANK(): posición relativa de cada cliente (0 a 1)
--    PERCENT_RANK = (posición - 1) / (filas - 1). 0 = el valor más bajo,
--    1 = el más alto. Aquí se agrupa en deciles para ver si la fuga crece
--    o decrece a medida que sube el credit score.
--    decil = parte entera de (percent_rank * 10) + 1; LEAST evita un decil 11
--    para el cliente con percent_rank = 1.
-- ---------------------------------------------------------------------
WITH rangos AS (
    SELECT
        customer_id,
        credit_score,
        exited,
        PERCENT_RANK() OVER (ORDER BY credit_score) AS pr_score
    FROM vw_churn_segmentado
),
deciles AS (
    SELECT
        *,
        LEAST(FLOOR(pr_score * 10)::INT, 9) + 1 AS decil_score
    FROM rangos
)
SELECT
    decil_score,
    COUNT(*)                                 AS clientes,
    MIN(credit_score)                        AS score_min,
    MAX(credit_score)                        AS score_max,
    ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
FROM deciles
GROUP BY decil_score
ORDER BY decil_score;
-- Pregunta de entrevista: ¿por qué NTILE y PERCENT_RANK dan resultados parecidos
-- pero no iguales? (NTILE fuerza grupos de igual tamaño; PERCENT_RANK mide posición
-- y los empates reciben el mismo valor.)


-- ---------------------------------------------------------------------
-- 4. RANK(): ranking de segmentos por tasa de fuga
--    RANK() OVER (PARTITION BY dimension ORDER BY churn DESC) numera los
--    segmentos DENTRO de cada dimensión (PARTITION BY reinicia el ranking).
--    Se exige un tamaño mínimo (HAVING) para no destacar grupos diminutos;
--    ajusta el umbral de 100 clientes si lo ves necesario.
-- ---------------------------------------------------------------------
WITH segmentos AS (
    SELECT 'Pais'       AS dimension, geography     AS segmento, exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Genero',     gender,                                 exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Edad',       age_group,                              exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Saldo',      balance_group,                          exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Antiguedad', tenure_group,                           exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Productos',  num_of_products::TEXT || ' producto(s)', exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Actividad',  CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END, exited FROM vw_churn_segmentado
),
tasas AS (
    SELECT
        dimension,
        segmento,
        COUNT(*)                                 AS clientes,
        SUM(exited)                              AS fugados,
        ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
    FROM segmentos
    GROUP BY dimension, segmento
    HAVING COUNT(*) >= 100
)
SELECT
    dimension,
    segmento,
    clientes,
    fugados,
    churn_rate_pct,
    RANK() OVER (PARTITION BY dimension ORDER BY churn_rate_pct DESC) AS ranking_en_dimension,
    RANK() OVER (ORDER BY churn_rate_pct DESC)                        AS ranking_general
FROM tasas
ORDER BY ranking_general;
-- Los primeros del ranking general son los candidatos a "segmentos con mayor
-- tasa de fuga" para el README. Valídalos con el tamaño (clientes) y el Pareto (script 05).


-- ---------------------------------------------------------------------
-- 5. LAG(): cambio de la tasa de fuga entre años de antigüedad
--    LAG(col) devuelve el valor de la fila anterior según el ORDER BY.
--    Aquí compara cada año de antigüedad con el anterior.
--    OJO: Tenure NO es tiempo calendario (el dataset no tiene fechas);
--    es "años como cliente". No es una tendencia en el tiempo.
-- ---------------------------------------------------------------------
WITH por_tenure AS (
    SELECT
        tenure,
        COUNT(*)                                 AS clientes,
        SUM(exited)                              AS fugados,
        ROUND(100.0 * SUM(exited) / COUNT(*), 2) AS churn_rate_pct
    FROM vw_churn_segmentado
    GROUP BY tenure
)
SELECT
    tenure,
    clientes,
    fugados,
    churn_rate_pct,
    LAG(churn_rate_pct) OVER (ORDER BY tenure)                   AS churn_anio_anterior,
    ROUND(churn_rate_pct - LAG(churn_rate_pct) OVER (ORDER BY tenure), 2) AS variacion_pp
FROM por_tenure
ORDER BY tenure;