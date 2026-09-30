-- 01_event_overview.sql
-- Inventario de eventos: volumen y usuarios únicos por tipo de evento (nov 2020 – ene 2021).
SELECT
  event_name,
  COUNT(*) AS eventos,
  COUNT(DISTINCT user_pseudo_id) AS usuarios_unicos,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct_eventos
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY event_name
ORDER BY eventos DESC;
