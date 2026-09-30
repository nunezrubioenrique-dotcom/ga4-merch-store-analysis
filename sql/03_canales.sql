-- 03_canales.sql
-- Pregunta 2: rendimiento por canal de adquisición.
-- Nota: el export de GA4 de 2020 solo trae traffic_source (canal con el que se adquirió al usuario),
-- no la fuente de cada sesión. Cada sesión hereda el canal de primera adquisición del usuario.

CREATE TEMP TABLE sesiones_canal AS
WITH base AS (
  SELECT
    user_pseudo_id,
    CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    PARSE_DATE('%Y%m%d', event_date) AS fecha,
    traffic_source.source AS source,
    traffic_source.medium AS medium,
    event_name,
    ecommerce.purchase_revenue_in_usd AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
sesiones AS (
  SELECT
    session_id,
    ANY_VALUE(user_pseudo_id) AS user_pseudo_id,
    MIN(fecha) AS fecha,
    ANY_VALUE(source) AS source,
    ANY_VALUE(medium) AS medium,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS add_to_cart,
    COUNTIF(event_name = 'purchase') AS compras,
    SUM(IF(event_name = 'purchase', revenue, NULL)) AS ingresos
  FROM base
  WHERE session_id IS NOT NULL
  GROUP BY session_id
)
SELECT
  *,
  CASE
    WHEN source = '(direct)' AND medium IN ('(none)', '(not set)') THEN 'Direct'
    WHEN medium = 'organic' THEN 'Organic Search'
    WHEN medium IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
    WHEN medium = 'referral' AND source = 'shop.googlemerchandisestore.com' THEN 'Referral (dominio propio)'
    WHEN medium = 'referral' THEN 'Referral'
    ELSE 'Sin clasificar (ofuscado)'
  END AS canal
FROM sesiones;

-- Tabla resumen por canal (para tabla y barras en Looker Studio)
CREATE OR REPLACE TABLE `ga4-portfolio-enr.ga4_analysis.canales` AS
SELECT
  canal,
  COUNT(DISTINCT user_pseudo_id) AS usuarios,
  COUNT(*) AS sesiones,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct_sesiones,
  COUNTIF(add_to_cart = 1) AS sesiones_con_carrito,
  COUNTIF(compras > 0) AS sesiones_con_compra,
  ROUND(SAFE_DIVIDE(COUNTIF(compras > 0), COUNT(*)) * 100, 2) AS tasa_conversion,
  SUM(compras) AS compras,
  ROUND(IFNULL(SUM(ingresos), 0), 2) AS ingresos_usd,
  ROUND(SAFE_DIVIDE(IFNULL(SUM(ingresos), 0), SUM(compras)), 2) AS ticket_medio_usd,
  ROUND(SAFE_DIVIDE(IFNULL(SUM(ingresos), 0), COUNT(*)), 3) AS ingreso_por_sesion_usd,
  ROUND(IFNULL(SUM(ingresos), 0) / SUM(IFNULL(SUM(ingresos), 0)) OVER () * 100, 2) AS pct_ingresos
FROM sesiones_canal
GROUP BY canal;

-- Tabla diaria por canal (para series temporales en Looker Studio)
CREATE OR REPLACE TABLE `ga4-portfolio-enr.ga4_analysis.canales_diario` AS
SELECT
  fecha,
  canal,
  COUNT(*) AS sesiones,
  COUNTIF(compras > 0) AS sesiones_con_compra,
  SUM(compras) AS compras,
  ROUND(IFNULL(SUM(ingresos), 0), 2) AS ingresos_usd
FROM sesiones_canal
GROUP BY fecha, canal;

SELECT * FROM `ga4-portfolio-enr.ga4_analysis.canales` ORDER BY sesiones DESC;
