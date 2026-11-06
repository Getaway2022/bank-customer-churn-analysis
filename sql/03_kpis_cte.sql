-- =====================================================================
-- 03_kpis_cte.sql
-- Proyecto : Bank Customer Churn Analytics
-- Requiere : 01 y 02 ejecutados (vista vw_churn_segmentado)
-- Objetivo : KPIs globales y tasa de fuga por segmento usando CTEs.
-- Idea     : una CTE (WITH ...) es una consulta con nombre que se usa
--            como si fuera una tabla temporal dentro de la misma consulta.
-- Nota     : "tasa de fuga" = fugados / total. No es una probabilidad
--            individual (eso exigiría un modelo, fase opcional).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. KPIs GLOBALES
-- ---------------------------------------------------------------------
WITH kpi AS (
    SELECT
        COUNT(*)                                         AS total_clientes,
        SUM(exited)                                      AS clientes_fugados,
        SUM(balance)                                     AS saldo_total,
        COALESCE(SUM(balance) FILTER (WHERE exited = 1), 0) AS saldo_en_riesgo
    FROM vw_churn_segmentado
)
SELECT
    total_clientes,
    clientes_fugados,
    total_clientes - clientes_fugados                          AS clientes_retenidos,
    ROUND(100.0 * clientes_fugados / total_clientes, 2)        AS churn_rate_pct,
    ROUND(saldo_total, 2)                                      AS saldo_total,
    ROUND(saldo_en_riesgo, 2)                                  AS saldo_en_riesgo,
    ROUND(100.0 * saldo_en_riesgo / NULLIF(saldo_total, 0), 2) AS pct_saldo_en_riesgo
FROM kpi;
-- NULLIF(x, 0) devuelve NULL si x es 0: evita el error de división por cero
-- (es el equivalente en SQL de usar DIVIDE en DAX).


-- ---------------------------------------------------------------------
-- 2. TASA DE FUGA POR SEGMENTO (todas las dimensiones en una sola tabla)
--    Paso a paso:
--      segmentos    -> pone cada dimensión en formato largo (dimension, segmento)
--      por_segmento -> cuenta clientes, fugados y saldo en riesgo por segmento
--      global       -> KPIs globales para comparar
--    Resultado: cada segmento con su diferencia en puntos porcentuales (pp)
--    frente al global, su peso en el total de fugas y en el saldo en riesgo.
-- ---------------------------------------------------------------------
WITH segmentos AS (
    SELECT 'Pais'          AS dimension, geography                AS segmento, exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Genero',        gender,                                           exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Edad',          age_group,                                        exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Saldo',         balance_group,                                    exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Antiguedad',    tenure_group,                                     exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Productos',     num_of_products::TEXT || ' producto(s)',          exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Actividad',     CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END,
                                                                              exited, balance FROM vw_churn_segmentado
    UNION ALL
    SELECT 'Tarjeta',       CASE WHEN has_cr_card = 1 THEN 'Con tarjeta' ELSE 'Sin tarjeta' END,
                                                                              exited, balance FROM vw_churn_segmentado
),
por_segmento AS (
    SELECT
        dimension,
        segmento,
        COUNT(*)                                             AS clientes,
        SUM(exited)                                          AS fugados,
        COALESCE(SUM(balance) FILTER (WHERE exited = 1), 0)  AS saldo_en_riesgo
    FROM segmentos
    GROUP BY dimension, segmento
),
global AS (
    SELECT
        COUNT(*)                                             AS total,
        SUM(exited)                                          AS fugados,
        100.0 * SUM(exited) / COUNT(*)                       AS churn_pct,
        COALESCE(SUM(balance) FILTER (WHERE exited = 1), 0)  AS saldo_en_riesgo
    FROM vw_churn_segmentado
)
SELECT
    p.dimension,
    p.segmento,
    p.clientes,
    p.fugados,
    ROUND(100.0 * p.fugados / p.clientes, 2)                       AS churn_rate_pct,
    ROUND(100.0 * p.fugados / p.clientes - g.churn_pct, 2)         AS dif_vs_global_pp,
    ROUND(100.0 * p.fugados / NULLIF(g.fugados, 0), 2)             AS pct_del_total_de_fugas,
    ROUND(p.saldo_en_riesgo, 2)                                    AS saldo_en_riesgo,
    ROUND(100.0 * p.saldo_en_riesgo / NULLIF(g.saldo_en_riesgo, 0), 2) AS pct_del_saldo_en_riesgo
FROM por_segmento p
CROSS JOIN global g
ORDER BY p.dimension, churn_rate_pct DESC;
-- Cómo leerla: dif_vs_global_pp positivo = fuga por encima del promedio.
-- Mira SIEMPRE "clientes" junto a la tasa: una tasa alta en un grupo
-- diminuto no sostiene una recomendación.


-- ---------------------------------------------------------------------
-- 3. PERFIL: FUGADOS vs RETENIDOS (promedios)
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN exited = 1 THEN 'Fugado' ELSE 'Retenido' END AS estado,
    COUNT(*)                              AS clientes,
    ROUND(AVG(age), 1)                    AS edad_prom,
    ROUND(AVG(credit_score), 1)           AS score_prom,
    ROUND(AVG(tenure), 2)                 AS antiguedad_prom,
    ROUND(AVG(balance), 2)                AS saldo_prom,
    ROUND(AVG(estimated_salary), 2)       AS salario_est_prom,
    ROUND(AVG(num_of_products), 2)        AS productos_prom,
    ROUND(100.0 * AVG(is_active_member), 1) AS pct_activos
FROM vw_churn_segmentado
GROUP BY exited
ORDER BY exited DESC;
-- Promedios pueden esconder diferencias (el saldo tiene muchos ceros):
-- por eso el EDA en Python añade histogramas y boxplots.


-- ---------------------------------------------------------------------
-- 4. CRUCE DE DOS DIMENSIONES: país x actividad
--    Sirve para ver si un efecto (p. ej. país) se mantiene o desaparece
--    al separar por otra variable. Cambia las columnas para probar otros cruces.
-- ---------------------------------------------------------------------
WITH cruce AS (
    SELECT
        geography,
        CASE WHEN is_active_member = 1 THEN 'Activo' ELSE 'Inactivo' END AS actividad,
        COUNT(*)    AS clientes,
        SUM(exited) AS fugados
    FROM vw_churn_segmentado
    GROUP BY geography, is_active_member
)
SELECT
    geography,
    actividad,
    clientes,
    fugados,
    ROUND(100.0 * fugados / clientes, 2) AS churn_rate_pct
FROM cruce
ORDER BY geography, actividad;