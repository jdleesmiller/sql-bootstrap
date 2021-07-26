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
    avg(mass) AS mass_avg,
    stddev(mass) AS mass_sd
  FROM bootstrap_map
  JOIN bootstrap_data USING (data_index)
  GROUP BY bootstrap_index
),
sample AS (
  SELECT avg(mass) AS mass_avg, stddev(mass) AS mass_sd
  FROM cats
),
bootstrap_q AS (
  SELECT
    percentile_cont(0.025) WITHIN GROUP (ORDER BY
      (bootstrap.mass_avg - sample.mass_avg) / bootstrap.mass_sd) AS q_lo,
    percentile_cont(0.975) WITHIN GROUP (ORDER BY
      (bootstrap.mass_avg - sample.mass_avg) / bootstrap.mass_sd) AS q_hi
  FROM bootstrap
  JOIN sample ON TRUE
)
SELECT sample.mass_avg,
  sample.mass_avg - sample.mass_sd * q_hi AS mass_lo,
  sample.mass_avg - sample.mass_sd * q_lo AS mass_hi
FROM sample
JOIN bootstrap_q ON TRUE;
