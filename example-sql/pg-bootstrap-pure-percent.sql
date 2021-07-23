WITH bootstrap_indexes AS (
  SELECT generate_series(1, 1000) AS bootstrap_index
),
bootstrap_data AS (
  SELECT mass, ROW_NUMBER() OVER (ORDER BY id) - 1 AS data_index
  FROM cats
),
bootstrap_map AS (
  SELECT floor(random() * (
    SELECT count(data_index) FROM bootstrap_data)) AS data_index,
    bootstrap_index
  FROM bootstrap_data
  JOIN bootstrap_indexes ON TRUE
),
bootstrap AS (
  SELECT bootstrap_index,
    avg(mass) AS mass_avg
  FROM bootstrap_map
  JOIN bootstrap_data USING (data_index)
  GROUP BY bootstrap_index
),
bootstrap_ci AS (
  SELECT
    percentile_cont(0.025) WITHIN GROUP (ORDER BY mass_avg) AS mass_lo,
    percentile_cont(0.975) WITHIN GROUP (ORDER BY mass_avg) AS mass_hi
  FROM bootstrap
),
sample AS (
  SELECT avg(mass) AS mass_avg
  FROM cats
)
SELECT *
FROM sample
JOIN bootstrap_ci ON TRUE;
