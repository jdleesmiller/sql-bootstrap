WITH bootstrap_indexes AS (
  SELECT * FROM UNNEST(generate_array(0, 1000)) AS bootstrap_index
),
bootstrap_data AS (
  SELECT hits.*, ROW_NUMBER() OVER (ORDER BY created_at) - 1 AS data_index
  FROM `hits.hits` hits
),
bootstrap_variates AS (
  SELECT data_index, bootstrap_index, rand() AS bootstrap_u
  FROM bootstrap_data
  JOIN bootstrap_indexes ON TRUE
),
bootstrap_weights AS (
  SELECT data_index, bootstrap_index, (
    CASE WHEN bootstrap_u < 0.367879441171442 THEN 0 ELSE 
    CASE WHEN bootstrap_u < 0.735758882342885 THEN 1 ELSE 
    CASE WHEN bootstrap_u < 0.919698602928606 THEN 2 ELSE 
    CASE WHEN bootstrap_u < 0.981011843123846 THEN 3 ELSE 
    CASE WHEN bootstrap_u < 0.996340153172656 THEN 4 ELSE 
    CASE WHEN bootstrap_u < 0.999405815182418 THEN 5 ELSE 
    CASE WHEN bootstrap_u < 0.999916758850712 THEN 6 ELSE 
    CASE WHEN bootstrap_u < 0.999989750803325 THEN 7 ELSE 
    CASE WHEN bootstrap_u < 0.999998874797402 THEN 8 ELSE 
    CASE WHEN bootstrap_u < 0.999999888574522 THEN 9 ELSE 
    CASE WHEN bootstrap_u < 0.999999989952234 THEN 10 ELSE 
    CASE WHEN bootstrap_u < 0.999999999168389 THEN 11 ELSE 
    CASE WHEN bootstrap_u < 0.999999999936402 THEN 12 ELSE 
    CASE WHEN bootstrap_u < 0.99999999999548 THEN 13 ELSE 
    CASE WHEN bootstrap_u < 0.9999999999997 THEN 14 ELSE 
    15 END END END END END END END END END END END END END END END) AS bootstrap_weight
  FROM bootstrap_variates
),
bootstrap_measures AS (
  SELECT bootstrap_index,
  sum(bootstrap_weight * (CASE WHEN converted THEN 1.0 ELSE 0.0 END)) /
    sum(bootstrap_weight) AS measure
  FROM bootstrap_weights
  JOIN bootstrap_data USING (data_index)
  GROUP BY bootstrap_index
),
bootstrap_ci AS (
  SELECT
    percentile_cont(measure, 0.025) OVER () AS measure_lo,
    percentile_cont(measure, 0.975) OVER () AS measure_hi
  FROM bootstrap_measures
),
sample_measures AS (
  SELECT avg(CASE WHEN converted THEN 1.0 ELSE 0.0 END) AS measure_avg
  FROM `hits.hits` hits
)
SELECT *
FROM sample_measures
JOIN bootstrap_ci ON TRUE;
