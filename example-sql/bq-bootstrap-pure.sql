WITH bootstrap_indexes AS (
  SELECT * FROM UNNEST(generate_array(0, 1000)) AS bootstrap_index
),
bootstrap_data AS (
  SELECT hits.*, ROW_NUMBER() OVER (ORDER BY created_at) - 1 AS data_index
  FROM `sql_bootstrap.hits` hits
),
bootstrap_map AS (
  SELECT floor(rand() * (
    SELECT count(data_index) FROM bootstrap_data)) AS data_index,
    bootstrap_index
  FROM bootstrap_data
  JOIN bootstrap_indexes ON TRUE
),
bootstrap_measures AS (
  SELECT bootstrap_index, avg(CASE WHEN converted THEN 1.0 ELSE 0.0 END) AS measure
  FROM bootstrap_map
  JOIN bootstrap_data USING (data_index)
  GROUP BY bootstrap_index
),
bootstrap_ci AS (
  SELECT
    percentile_cont(measure, 0.025) OVER () AS measure_lo,
    percentile_cont(measure, 0.975) OVER () AS measure_hi
  FROM bootstrap_measures
  LIMIT 1
),
sample_measures AS (
  SELECT avg(CASE WHEN converted THEN 1.0 ELSE 0.0 END) AS measure_avg
  FROM `sql_bootstrap.hits` hits
)
SELECT *
FROM sample_measures
JOIN bootstrap_ci ON TRUE;
