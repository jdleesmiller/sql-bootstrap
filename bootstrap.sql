WITH bootstrap_indexes AS (SELECT generate_series(0, 1000) AS bootstrap_index),
data AS (
  SELECT hits.*, ROW_NUMBER() OVER (ORDER BY created_at) - 1 AS data_index
  FROM hits
),
bootstrap_map AS (
  SELECT floor(random() * (SELECT count(data_index) FROM data)) AS data_index,
    bootstrap_index
  FROM data
  JOIN bootstrap_indexes ON TRUE
),
bootstrap_measures AS (
  SELECT bootstrap_index, avg(CASE WHEN converted THEN 1 ELSE 0 END) AS measure
  FROM bootstrap_map
  JOIN data USING (data_index)
  GROUP BY bootstrap_index
),
bootstrap_ci AS (
  SELECT
    percentile_cont(0.025) WITHIN GROUP (ORDER BY measure) AS measure_lo,
    percentile_cont(0.975) WITHIN GROUP (ORDER BY measure) AS measure_hi
  FROM bootstrap_measures
),
sample_measures AS (
  SELECT avg(CASE WHEN converted THEN 1 ELSE 0 END) AS avg_measure
  FROM data
)
SELECT *
FROM sample_measures
JOIN bootstrap_ci ON TRUE;
