-- 04_productos.sql
-- Pregunta 3: productos con mucho interés y poca compra.
--
-- NOTA DE CALIDAD DE DATOS (dataset ofuscado):
-- Los eventos view_item y add_to_cart suelen traer 12 productos en el array items (relleno).
-- En add_to_cart, el producto realmente añadido es el único con quantity > 0 (64 % de los eventos).
-- En view_item no existe ningún marcador fiable, por lo que la vista por producto no es medible.
-- => Se usa "añadir al carrito" como señal de interés y se mide carrito -> compra por producto.

CREATE OR REPLACE TABLE `ga4-portfolio-enr.ga4_analysis.productos` AS
WITH items AS (
  SELECT
    event_name,
    user_pseudo_id,
    i.item_name,
    i.item_category,
    i.quantity,
    i.item_revenue_in_usd
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
    UNNEST(items) AS i
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND (
      (event_name = 'add_to_cart' AND i.quantity > 0)   -- solo el producto realmente añadido
      OR event_name = 'purchase'
    )
),
agg AS (
  SELECT
    item_name,
    ANY_VALUE(item_category) AS item_category,
    COUNT(DISTINCT IF(event_name = 'add_to_cart', user_pseudo_id, NULL)) AS usuarios_carrito,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL))    AS usuarios_compra,
    IFNULL(SUM(IF(event_name = 'add_to_cart', quantity, NULL)), 0)       AS unidades_carrito,
    IFNULL(SUM(IF(event_name = 'purchase', quantity, NULL)), 0)          AS unidades_vendidas,
    ROUND(IFNULL(SUM(IF(event_name = 'purchase', item_revenue_in_usd, NULL)), 0), 2) AS ingresos_usd
  FROM items
  GROUP BY item_name
),
tasas AS (
  SELECT
    *,
    ROUND(SAFE_DIVIDE(usuarios_compra, usuarios_carrito) * 100, 2) AS tasa_carrito_compra
  FROM agg
),
umbrales AS (
  -- Medianas sobre productos con volumen suficiente (>= 50 usuarios lo añadieron al carrito)
  SELECT
    APPROX_QUANTILES(usuarios_carrito, 100)[OFFSET(50)]    AS mediana_carrito,
    APPROX_QUANTILES(tasa_carrito_compra, 100)[OFFSET(50)] AS mediana_conversion
  FROM tasas
  WHERE usuarios_carrito >= 50
)
SELECT
  t.*,
  u.mediana_carrito,
  u.mediana_conversion,
  CASE
    WHEN t.usuarios_carrito < 50 THEN 'Volumen bajo (<50 usuarios)'
    WHEN t.usuarios_carrito >= u.mediana_carrito AND t.tasa_carrito_compra <  u.mediana_conversion THEN 'Mucho interés, poca compra'
    WHEN t.usuarios_carrito >= u.mediana_carrito AND t.tasa_carrito_compra >= u.mediana_conversion THEN 'Estrella'
    WHEN t.tasa_carrito_compra >= u.mediana_conversion THEN 'Nicho eficiente'
    ELSE 'Bajo rendimiento'
  END AS segmento
FROM tasas t
CROSS JOIN umbrales u;

-- Resumen por segmento
SELECT
  segmento,
  COUNT(*) AS productos,
  SUM(usuarios_carrito) AS usuarios_carrito,
  SUM(usuarios_compra) AS usuarios_compra,
  ROUND(SUM(ingresos_usd), 0) AS ingresos_usd,
  ANY_VALUE(mediana_carrito) AS mediana_carrito,
  ANY_VALUE(mediana_conversion) AS mediana_conversion
FROM `ga4-portfolio-enr.ga4_analysis.productos`
GROUP BY segmento
ORDER BY usuarios_carrito DESC;

-- Top 10 de cada segmento clave
SELECT segmento, item_name, item_category, usuarios_carrito, usuarios_compra, tasa_carrito_compra, ingresos_usd
FROM `ga4-portfolio-enr.ga4_analysis.productos`
WHERE segmento IN ('Mucho interés, poca compra', 'Estrella')
QUALIFY ROW_NUMBER() OVER (PARTITION BY segmento ORDER BY usuarios_carrito DESC) <= 10
ORDER BY segmento DESC, usuarios_carrito DESC;
