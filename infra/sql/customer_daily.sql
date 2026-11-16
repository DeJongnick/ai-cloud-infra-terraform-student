-- Séance 4, partie B : compteurs par client et par jour.
CREATE OR REPLACE TABLE `team3.customer_daily` AS
WITH flux AS (
  -- Votre historique, une seule ligne par transaction même si Pub/Sub l'a livrée deux fois.
  SELECT
    TX_ID,
    ANY_VALUE(TX_TS) AS TX_TS,
    ANY_VALUE(CUSTOMER_ID) AS CUSTOMER_ID,
    ANY_VALUE(TX_AMOUNT) AS TX_AMOUNT
  FROM `team3.tx_history`
  WHERE TX_TS >= TIMESTAMP '2026-10-01'
  -- (a) Une transaction est identifiée par son TX_ID : on supprime les doublons de livraison.
  GROUP BY TX_ID
),
tx AS (
  -- Le passé fourni par le socle, puis votre flux.
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM `fraudfinder.tx_seed`
  WHERE TX_TS >= TIMESTAMP '2026-09-10'
  -- (b) Mêmes trois colonnes, dans le même ordre.
  UNION ALL
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM flux
)
SELECT
  CUSTOMER_ID AS customer_id,
  DATE(TX_TS) AS day,
  -- (c) Nombre de transactions et somme des montants du client ce jour-là.
  COUNT(*) AS n,
  SUM(TX_AMOUNT) AS amount_sum
FROM tx
GROUP BY customer_id, day;
