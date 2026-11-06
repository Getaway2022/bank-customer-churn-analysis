-- =====================================================================
-- 07_resultados_readme.sql
-- Proyecto : Bank Customer Churn Analytics
-- Requiere : 00 a 06 ejecutados (tablas stg_churn y churn_clientes, vistas vw_*)
-- Objetivo : reunir en UNA tabla las cifras que van al README, al CV y a
--            LinkedIn. Es SOLO LECTURA: no crea, borra ni modifica nada,
--            así que puedes ejecutarlo las veces que quieras.
-- Uso      : ejecuta la consulta completa y copia/captura el resultado
--            (3 columnas: seccion, metrica, valor). Todo viene de tus datos.
-- =====================================================================

WITH
-- Calidad del dato crudo (staging). Si stg_churn está vacía, estas cifras salen 0:
-- en ese caso no las uses para el README.
calidad AS (
    SELECT
        (SELECT COUNT(*) FROM stg_churn)                                       AS filas_staging,
        -- filas con al menos un campo nulo o vacío en cualquier columna
        (SELECT COUNT(*) FROM stg_churn t
          WHERE EXISTS (SELECT 1
                        FROM jsonb_each_text(to_jsonb(t)) j
                        WHERE NULLIF(TRIM(j.value), '') IS NULL))              AS filas_con_nulos,
        (SELECT COUNT(*) - COUNT(DISTINCT customerid) FROM stg_churn)          AS duplicados_customerid
),
-- Rangos válidos sobre la tabla limpia (mismas reglas que 01, sección 5.2)
rangos AS (
    SELECT
        COUNT(*)                                                               AS filas_limpias,
        COUNT(*) FILTER (WHERE age NOT BETWEEN 18 AND 100
                            OR credit_score NOT BETWEEN 300 AND 850
                            OR tenure NOT BETWEEN 0 AND 10
                            OR balance < 0
                            OR estimated_salary < 0
                            OR num_of_products NOT BETWEEN 1 AND 4
                            OR exited NOT IN (0, 1)
                            OR has_cr_card NOT IN (0, 1)
                            OR is_active_member NOT IN (0, 1))                 AS filas_fuera_de_rango
    FROM churn_clientes
),
-- KPIs globales
kpi AS (
    SELECT
        COUNT(*)                                                               AS total,
        SUM(exited)                                                            AS fugados,
        SUM(balance)                                                           AS saldo_total,
        COALESCE(SUM(balance) FILTER (WHERE exited = 1), 0)                    AS saldo_riesgo
    FROM churn_clientes
),
-- Pareto: acumulado recalculado desde los fugados enteros (evita errores de redondeo)
pareto AS (
    SELECT
        posicion,
        segmento,
        fugados,
        churn_rate_pct,
        pct_acumulado,
        SUM(fugados) OVER (ORDER BY posicion)  AS fugados_acum,
        SUM(fugados) OVER ()                   AS fugados_total
    FROM vw_pareto_segmentos
),
resumen_pareto AS (
    SELECT
        COUNT(*)                                                               AS segmentos_totales,
        COUNT(*) FILTER (WHERE 100.0 * (fugados_acum - fugados) / fugados_total < 80)
                                                                               AS segmentos_para_80
    FROM pareto
),
-- Segmentos con mayor tasa de fuga (tamaño mínimo 100 clientes, como en 04)
top_tasa AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY churn_rate_pct DESC, clientes DESC) AS puesto,
        dimension, segmento, clientes, fugados, churn_rate_pct, dif_vs_global_pp,
        pct_del_total_de_fugas, pct_del_saldo_en_riesgo
    FROM vw_churn_por_segmento
    WHERE clientes >= 100
)

SELECT 1 AS ord, 'Calidad (script 01)' AS seccion, 'Filas cargadas en staging' AS metrica,
       filas_staging::TEXT AS valor FROM calidad
UNION ALL SELECT 2, 'Calidad (script 01)', 'Filas con algun nulo o vacio',   filas_con_nulos::TEXT        FROM calidad
UNION ALL SELECT 3, 'Calidad (script 01)', 'Duplicados por customerid',       duplicados_customerid::TEXT  FROM calidad
UNION ALL SELECT 4, 'Calidad (script 01)', 'Filas en tabla limpia',           filas_limpias::TEXT          FROM rangos
UNION ALL SELECT 5, 'Calidad (script 01)', 'Filas fuera de rango',            filas_fuera_de_rango::TEXT   FROM rangos

UNION ALL SELECT 10, 'KPIs globales (script 03)', 'Total de clientes',       total::TEXT                  FROM kpi
UNION ALL SELECT 11, 'KPIs globales (script 03)', 'Clientes fugados',         fugados::TEXT                FROM kpi
UNION ALL SELECT 12, 'KPIs globales (script 03)', 'Churn rate global (%)',    ROUND(100.0 * fugados / total, 2)::TEXT FROM kpi
UNION ALL SELECT 13, 'KPIs globales (script 03)', 'Saldo total',              ROUND(saldo_total, 2)::TEXT  FROM kpi
UNION ALL SELECT 14, 'KPIs globales (script 03)', 'Saldo en riesgo',          ROUND(saldo_riesgo, 2)::TEXT FROM kpi
UNION ALL SELECT 15, 'KPIs globales (script 03)', '% del saldo total en riesgo',
       ROUND(100.0 * saldo_riesgo / NULLIF(saldo_total, 0), 2)::TEXT FROM kpi

UNION ALL SELECT 20, 'Pareto (script 05)', 'Segmentos totales (pais | edad | actividad)', segmentos_totales::TEXT FROM resumen_pareto
UNION ALL SELECT 21, 'Pareto (script 05)', 'Segmentos necesarios para el 80 % de las fugas', segmentos_para_80::TEXT FROM resumen_pareto
UNION ALL SELECT 22, 'Pareto (script 05)', '% de segmentos que concentra el 80 % de las fugas',
       ROUND(100.0 * segmentos_para_80 / segmentos_totales, 1)::TEXT FROM resumen_pareto
UNION ALL SELECT 23, 'Pareto (script 05)', '% acumulado de fugas en los primeros 15 segmentos',
       pct_acumulado::TEXT FROM pareto WHERE posicion = 15
UNION ALL SELECT 24 + posicion, 'Pareto (script 05)', 'Segmento #' || posicion,
       segmento || ' | ' || fugados || ' fugados | fuga ' || churn_rate_pct || ' % | acumulado ' || pct_acumulado || ' %'
       FROM pareto WHERE posicion <= 5

UNION ALL SELECT 40 + puesto, 'Mayor tasa de fuga, min. 100 clientes (scripts 03/04)', 'Puesto #' || puesto,
       dimension || ': ' || segmento || ' | ' || clientes || ' clientes | fuga ' || churn_rate_pct ||
       ' % (' || dif_vs_global_pp || ' pp vs global) | ' || pct_del_total_de_fugas || ' % de las fugas | '
       || COALESCE(pct_del_saldo_en_riesgo::TEXT, '0') || ' % del saldo en riesgo'
       FROM top_tasa WHERE puesto <= 5

ORDER BY ord;