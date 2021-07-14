WITH bootstrap_indexes AS (
  SELECT * FROM UNNEST(generate_array(1, 1000)) AS bootstrap_index
),
bootstrap_data AS (
  SELECT converted, ROW_NUMBER() OVER (ORDER BY created_at) - 1 AS data_index
  FROM `sql_bootstrap.hits` hits
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
    avg(converted) AS rate_avg,
    stddev(converted) AS rate_sd
  FROM bootstrap_map
  JOIN bootstrap_data USING (data_index)
  GROUP BY bootstrap_index
),
sample AS (
  SELECT avg(converted) AS rate_avg, stddev(converted) AS rate_sd
  FROM `sql_bootstrap.hits` hits
),
bootstrap_q AS (
  SELECT
    percentile_cont((bootstrap.rate_avg - sample.rate_avg) / bootstrap.rate_sd,
      0.025) OVER () AS q_lo,
    percentile_cont((bootstrap.rate_avg - sample.rate_avg) / bootstrap.rate_sd,
      0.975) OVER () AS q_hi
  FROM bootstrap
  JOIN sample ON TRUE
  LIMIT 1
)
SELECT sample.rate_avg,
  sample.rate_avg - sample.rate_sd * q_hi AS rate_lo,
  sample.rate_avg - sample.rate_sd * q_lo AS rate_hi
FROM sample
JOIN bootstrap_q ON TRUE;
