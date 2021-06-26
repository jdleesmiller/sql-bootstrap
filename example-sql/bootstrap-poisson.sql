WITH bootstrap_indexes AS (
  SELECT generate_series(1, 1000) AS bootstrap_index
),
bootstrap_variates AS (
  SELECT hits.*, bootstrap_index, random() AS bootstrap_u
  FROM hits  JOIN bootstrap_indexes ON TRUE
),
bootstrap_weights AS (
  SELECT bootstrap_variates.*, (CASE
    WHEN bootstrap_u < 0.367879441171442 THEN 0
    WHEN bootstrap_u < 0.735758882342885 THEN 1
    WHEN bootstrap_u < 0.919698602928606 THEN 2
    WHEN bootstrap_u < 0.981011843123846 THEN 3
    WHEN bootstrap_u < 0.996340153172656 THEN 4
    WHEN bootstrap_u < 0.999405815182418 THEN 5
    WHEN bootstrap_u < 0.999916758850712 THEN 6
    WHEN bootstrap_u < 0.999989750803325 THEN 7
    WHEN bootstrap_u < 0.999998874797402 THEN 8
    WHEN bootstrap_u < 0.999999888574522 THEN 9
    WHEN bootstrap_u < 0.999999989952234 THEN 10
    WHEN bootstrap_u < 0.999999999168389 THEN 11
    WHEN bootstrap_u < 0.999999999936402 THEN 12
    WHEN bootstrap_u < 0.99999999999548 THEN 13
    WHEN bootstrap_u < 0.9999999999997 THEN 14
    ELSE 15 END) AS bootstrap_weight
  FROM bootstrap_variates
),
bootstrap_measures AS (
  SELECT bootstrap_index,
  sum(bootstrap_weight * (CASE WHEN converted THEN 1.0 ELSE 0.0 END)) /
    sum(bootstrap_weight) AS measure
  FROM bootstrap_weights
  GROUP BY bootstrap_index
),
bootstrap_ci AS (
  SELECT
    percentile_cont(0.025) WITHIN GROUP (ORDER BY measure) AS measure_lo,
    percentile_cont(0.975) WITHIN GROUP (ORDER BY measure) AS measure_hi
  FROM bootstrap_measures
),
sample_measures AS (
  SELECT avg(CASE WHEN converted THEN 1.0 ELSE 0.0 END) AS measure_avg
  FROM hits
)
SELECT *
FROM sample_measures
JOIN bootstrap_ci ON TRUE;
