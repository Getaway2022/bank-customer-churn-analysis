-- =====================================================================
-- 05_pareto_segmentos.sql
-- Proyecto : Bank Customer Churn Analytics
-- Requiere : 01 y 02 ejecutados (vista vw_churn_segmentado)
-- Objetivo : Análisis tipo Pareto: ¿qué pocos segmentos concentran la
--            mayor parte de las fugas (y del saldo en riesgo)?
-- Idea     : ordenar segmentos de mayor a menor número de fugados y
--            calcular el % acumulado con una window function:
--            SUM(...) OVER (ORDER BY ... DESC ROWS UNBOUNDED PRECEDING)
-- Ojo      : el Pareto mide CONCENTRACIÓN de fugas (volumen), no tasa.
--            Un segmento muy grande puede aparecer arriba con tasa normal.
--            Por eso se acompaña siempre de la tasa de fuga.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. PARETO DE SEGMENTOS COMPUESTOS: país x grupo de edad x actividad
--    Un segmento compuesto reparte a TODOS los clientes en grupos que no
--    se solapan (cada cliente cae en uno solo). Así el % acumulado llega
--    exactamente a 100 %. Si mezclaras dimensiones distintas (país, edad...)
--    en una sola lista, un mismo cliente se contaría varias veces.
--    Cambia las columnas del segmento para probar otras combinaciones.
-- ---------------------------------------------------------------------
WITH segmentos AS (
    SELECT
        geography || ' | ' || age_group || ' | ' ||
            CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END AS segmento,
        COUNT(*)                                             AS clientes,
        SUM(exited)                                          AS fugados,
        COALESCE(SUM(balance) FILTER (WHERE exited = 1), 0)  AS saldo_en_riesgo
    FROM vw_churn_segmentado
    GROUP BY geography, age_group, is_active_member
),
pareto AS (
    SELECT
        segmento,
        clientes,
        fugados,
        saldo_en_riesgo,
        -- Desempate por nombre: si dos segmentos empatan en fugados, el orden
        -- (y por tanto el acumulado) queda fijo y repetible.
        ROW_NUMBER() OVER (ORDER BY fugados DESC, segmento)             AS posicion,
        SUM(fugados) OVER (ORDER BY fugados DESC, segmento
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS fugados_acum,
        SUM(fugados) OVER ()                                            AS fugados_total
    FROM segmentos
)
SELECT
    posicion,
    segmento,
    clientes,
    fugados,
    ROUND(100.0 * fugados / clientes, 2)                       AS churn_rate_pct,
    ROUND(100.0 * fugados / NULLIF(fugados_total, 0), 2)       AS pct_de_fugas,
    ROUND(100.0 * fugados_acum / NULLIF(fugados_total, 0), 2)  AS pct_acumulado,
    -- Marca los segmentos necesarios para llegar al 80 % de las fugas
    -- (el que cruza el 80 % también se incluye: se mira el acumulado ANTERIOR).
    CASE WHEN 100.0 * (fugados_acum - fugados) / NULLIF(fugados_total, 0) < 80
         THEN 'Si' ELSE 'No' END                               AS dentro_del_80
FROM pareto
ORDER BY posicion;
-- Cómo leerlo: "los N segmentos marcados 'Si' concentran el 80 % de las fugas".
-- Esa frase (con tus cifras reales) es candidata a resultado del README.


-- ---------------------------------------------------------------------
-- 2. RESUMEN DEL PARETO: ¿cuántos segmentos hacen falta para el 80 %?
-- ---------------------------------------------------------------------
WITH segmentos AS (
    SELECT
        geography || ' | ' || age_group || ' | ' ||
            CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END AS segmento,
        SUM(exited) AS fugados
    FROM vw_churn_segmentado
    GROUP BY geography, age_group, is_active_member
),
pareto AS (
    SELECT
        segmento,
        fugados,
        SUM(fugados) OVER (ORDER BY fugados DESC, segmento
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS fugados_acum,
        SUM(fugados) OVER ()  AS fugados_total
    FROM segmentos
)
SELECT
    COUNT(*)                                       AS segmentos_totales,
    COUNT(*) FILTER (WHERE 100.0 * (fugados_acum - fugados) / NULLIF(fugados_total, 0) < 80)
                                                   AS segmentos_para_80_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE 100.0 * (fugados_acum - fugados) / NULLIF(fugados_total, 0) < 80)
          / COUNT(*), 1)                           AS pct_de_segmentos_para_80_pct_fugas
FROM pareto;


-- ---------------------------------------------------------------------
-- 3. PARETO POR SALDO EN RIESGO (mismos segmentos, orden por dinero)
--    Un segmento con pocas fugas pero saldos altos puede pesar más en
--    dinero que en clientes. Compara este orden con el de la sección 1.
-- ---------------------------------------------------------------------
WITH segmentos AS (
    SELECT
        geography || ' | ' || age_group || ' | ' ||
            CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END AS segmento,
        SUM(exited)                                          AS fugados,
        COALESCE(SUM(balance) FILTER (WHERE exited = 1), 0)  AS saldo_en_riesgo
    FROM vw_churn_segmentado
    GROUP BY geography, age_group, is_active_member
),
pareto AS (
    SELECT
        segmento,
        fugados,
        saldo_en_riesgo,
        ROW_NUMBER() OVER (ORDER BY saldo_en_riesgo DESC, segmento) AS posicion,
        SUM(saldo_en_riesgo) OVER (ORDER BY saldo_en_riesgo DESC, segmento
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS saldo_acum,
        SUM(saldo_en_riesgo) OVER () AS saldo_total_riesgo
    FROM segmentos
)
SELECT
    posicion,
    segmento,
    fugados,
    ROUND(saldo_en_riesgo, 2)                                         AS saldo_en_riesgo,
    ROUND(100.0 * saldo_en_riesgo / NULLIF(saldo_total_riesgo, 0), 2) AS pct_del_saldo_en_riesgo,
    ROUND(100.0 * saldo_acum / NULLIF(saldo_total_riesgo, 0), 2)      AS pct_acumulado
FROM pareto
ORDER BY posicion
LIMIT 15;


-- ---------------------------------------------------------------------
-- 4. PARETO DENTRO DE UNA SOLA DIMENSIÓN (PARTITION BY)
--    Aquí cada dimensión (país, edad, productos...) se analiza por separado
--    y su acumulado llega a 100 % dentro de sí misma. PARTITION BY reinicia
--    el acumulado en cada dimensión.
-- ---------------------------------------------------------------------
WITH segmentos AS (
    SELECT 'Pais'       AS dimension, geography     AS segmento, exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Edad',       age_group,                              exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Antiguedad', tenure_group,                           exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Productos',  num_of_products::TEXT || ' producto(s)', exited FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Actividad',  CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END, exited FROM vw_churn_segmentado
),
por_segmento AS (
    SELECT dimension, segmento, COUNT(*) AS clientes, SUM(exited) AS fugados
    FROM segmentos
    GROUP BY dimension, segmento
)
SELECT
    dimension,
    segmento,
    clientes,
    fugados,
    ROUND(100.0 * fugados / clientes, 2) AS churn_rate_pct,
    ROUND(100.0 * fugados / NULLIF(SUM(fugados) OVER (PARTITION BY dimension), 0), 2) AS pct_de_fugas,
    ROUND(100.0 * SUM(fugados) OVER (PARTITION BY dimension
                                     ORDER BY fugados DESC, segmento
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / NULLIF(SUM(fugados) OVER (PARTITION BY dimension), 0), 2)                  AS pct_acumulado
FROM por_segmento
ORDER BY dimension, fugados DESC, segmento;