-- 05_retencion.sql
-- Pregunta 4: retención de usuarios.
-- Cohorte = semana (lunes) del primer contacto del usuario con la web (user_first_touch_timestamp).
-- Solo usuarios nuevos dentro del periodo (desde el lunes 2 nov 2020) para tener cohortes completas.

CREATE OR REPLACE TABLE `ga4-portfolio-enr.ga4_analysis.retencion_cohortes` AS
WITH actividad AS (
  SELECT DISTINCT
    user_pseudo_id,
    DATE_TRUNC(DATE(TIMESTAMP_MICROS(user_first_touch_timestamp)), WEEK(MONDAY)) AS cohorte_semana,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS semana_actividad
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND user_first_touch_timestamp IS NOT NULL
),
filtrada AS (
  SELECT
    *,
    DATE_DIFF(semana_actividad, cohorte_semana, WEEK(MONDAY)) AS semana_n
  FROM actividad
  WHERE cohorte_semana BETWEEN '2020-11-02' AND '2021-01-25'
),
tamano AS (
  SELECT cohorte_semana, COUNT(DISTINCT user_pseudo_id) AS usuarios_cohorte
  FROM filtrada
  WHERE semana_n = 0
  GROUP BY cohorte_semana
)
SELECT
  f.cohorte_semana,
  f.semana_n,
  t.usuarios_cohorte,
  COUNT(DISTINCT f.user_pseudo_id) AS usuarios_activos,
  ROUND(COUNT(DISTINCT f.user_pseudo_id) / t.usuarios_cohorte * 100, 2) AS retencion_pct
FROM filtrada f
JOIN tamano t USING (cohorte_semana)
WHERE f.semana_n >= 0
GROUP BY f.cohorte_semana, f.semana_n, t.usuarios_cohorte;

-- Conversión según el número de sesión del usuario (1ª visita vs recurrentes)
CREATE OR REPLACE TABLE `ga4-portfolio-enr.ga4_analysis.conversion_por_sesion` AS
WITH sesiones AS (
  SELECT
    CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS session_id,
    MAX((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_number')) AS num_sesion,
    MAX(IF(event_name = 'purchase', 1, 0)) AS compra,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue_in_usd, NULL)) AS ingresos
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY session_id
  HAVING session_id IS NOT NULL AND num_sesion IS NOT NULL
)
SELECT
  CASE
    WHEN num_sesion = 1 THEN '1. Primera sesión'
    WHEN num_sesion = 2 THEN '2. Segunda sesión'
    WHEN num_sesion BETWEEN 3 AND 5 THEN '3. Sesiones 3-5'
    ELSE '4. Sesión 6 o más'
  END AS tipo_sesion,
  COUNT(*) AS sesiones,
  SUM(compra) AS sesiones_con_compra,
  ROUND(SUM(compra) / COUNT(*) * 100, 2) AS tasa_conversion,
  ROUND(IFNULL(SUM(ingresos), 0), 0) AS ingresos_usd,
  ROUND(IFNULL(SUM(ingresos), 0) / SUM(IFNULL(SUM(ingresos), 0)) OVER () * 100, 2) AS pct_ingresos
FROM sesiones
GROUP BY tipo_sesion;

-- Resumen: retención media ponderada por semana desde la adquisición
SELECT
  semana_n,
  COUNT(*) AS cohortes,
  SUM(usuarios_cohorte) AS usuarios_base,
  ROUND(SUM(usuarios_activos) / SUM(usuarios_cohorte) * 100, 2) AS retencion_media_pct
FROM `ga4-portfolio-enr.ga4_analysis.retencion_cohortes`
GROUP BY semana_n
ORDER BY semana_n;
