-- 02_funnel.sql
-- Pregunta 1: embudo de conversión cerrado por sesión.
-- Cada paso solo cuenta sesiones que también completaron todos los pasos anteriores.
-- Crea el dataset de trabajo (ubicación US, igual que el dataset público) y la tabla para Looker Studio.

CREATE SCHEMA IF NOT EXISTS `ga4-portfolio-enr.ga4_analysis`
OPTIONS (location = 'US');

CREATE OR REPLACE TABLE `ga4-portfolio-enr.ga4_analysis.funnel_sesiones` AS
WITH eventos AS (
  SELECT
    CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN ('session_start','view_item','add_to_cart','begin_checkout','add_payment_info','purchase')
),
sesiones AS (
  SELECT
    session_id,
    MAX(IF(event_name = 'view_item', 1, 0))        AS view_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0))      AS add_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0))   AS begin_checkout,
    MAX(IF(event_name = 'add_payment_info', 1, 0)) AS add_payment_info,
    MAX(IF(event_name = 'purchase', 1, 0))         AS purchase
  FROM eventos
  GROUP BY session_id
),
totales AS (
  SELECT
    COUNT(*) AS s_total,
    SUM(view_item) AS s_view,
    SUM(view_item * add_to_cart) AS s_cart,
    SUM(view_item * add_to_cart * begin_checkout) AS s_checkout,
    SUM(view_item * add_to_cart * begin_checkout * add_payment_info) AS s_payment,
    SUM(view_item * add_to_cart * begin_checkout * add_payment_info * purchase) AS s_purchase
  FROM sesiones
)
SELECT
  paso_orden,
  paso,
  sesiones,
  ROUND(SAFE_DIVIDE(sesiones, LAG(sesiones) OVER (ORDER BY paso_orden)) * 100, 2) AS tasa_paso_anterior,
  ROUND(SAFE_DIVIDE(sesiones, FIRST_VALUE(sesiones) OVER (ORDER BY paso_orden)) * 100, 2) AS tasa_desde_inicio
FROM totales,
UNNEST([
  STRUCT(1 AS paso_orden, '1. Sesión' AS paso, s_total AS sesiones),
  STRUCT(2, '2. Ver producto', s_view),
  STRUCT(3, '3. Añadir al carrito', s_cart),
  STRUCT(4, '4. Iniciar checkout', s_checkout),
  STRUCT(5, '5. Añadir pago', s_payment),
  STRUCT(6, '6. Compra', s_purchase)
]);
