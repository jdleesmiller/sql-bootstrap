WITH bootstrap_indexes AS (
  SELECT * FROM UNNEST(generate_array(1, 1000)) AS bootstrap_index
),
bootstrap_data AS (
  SELECT mass, ROW_NUMBER() OVER (ORDER BY id) - 1 AS data_index
  FROM `sql_bootstrap.cats` cats
),
bootstrap_map AS (
  SELECT floor(rand() * (
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
  FROM `sql_bootstrap.cats` cats
),
bootstrap_q AS (
  SELECT
    percentile_cont((bootstrap.mass_avg - sample.mass_avg) / bootstrap.mass_sd,
      0.025) OVER () AS q_lo,
    percentile_cont((bootstrap.mass_avg - sample.mass_avg) / bootstrap.mass_sd,
      0.975) OVER () AS q_hi
  FROM bootstrap
  JOIN sample ON TRUE
  LIMIT 1
)
SELECT sample.mass_avg,
  sample.mass_avg - sample.mass_sd * q_hi AS mass_lo,
  sample.mass_avg - sample.mass_sd * q_lo AS mass_hi
FROM sample
JOIN bootstrap_q ON TRUE;
