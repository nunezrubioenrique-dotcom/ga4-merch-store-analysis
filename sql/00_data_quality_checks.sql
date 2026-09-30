-- 00_data_quality_checks.sql
-- Comprobaciones de calidad de datos que condicionan el análisis.
-- Dataset: bigquery-public-data.ga4_obfuscated_sample_ecommerce (nov 2020 – ene 2021)

-- 1) Volumen diario: confirma que no faltan días en el rango.
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS fecha,
  COUNT(*) AS eventos,
  COUNT(DISTINCT user_pseudo_id) AS usuarios
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY fecha
ORDER BY fecha;

-- 2) Fuente de tráfico: los parámetros 'source'/'medium' de evento vienen a NULL,
--    solo existe traffic_source (canal de primera adquisición del usuario).
SELECT
  traffic_source.source AS ts_source,
  traffic_source.medium AS ts_medium,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source') AS ep_source,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS ep_medium,
  COUNT(*) AS sesiones
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'session_start'
GROUP BY 1, 2, 3, 4
ORDER BY sesiones DESC;

-- 3) Número de productos por evento: view_item y add_to_cart suelen traer 12 productos
--    (relleno), por lo que no se puede contar "vistas por producto" directamente.
SELECT
  event_name,
  COUNT(*) AS eventos,
  ROUND(AVG(ARRAY_LENGTH(items)), 2) AS items_medios,
  APPROX_QUANTILES(ARRAY_LENGTH(items), 4) AS cuartiles_items,
  MAX(ARRAY_LENGTH(items)) AS max_items
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
GROUP BY event_name;

-- 4) En add_to_cart, el producto realmente añadido es el único con quantity > 0.
--    Resultado: 37.257 eventos con exactamente 1 producto identificable, 21.286 con ninguno.
SELECT
  (SELECT COUNTIF(i.quantity > 0) FROM UNNEST(items) i) AS items_con_quantity,
  COUNT(*) AS eventos_add_to_cart
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'add_to_cart'
GROUP BY 1
ORDER BY 1;
