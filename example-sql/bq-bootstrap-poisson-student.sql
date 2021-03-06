WITH bootstrap_indexes AS (
  SELECT * FROM UNNEST(generate_array(1, 1000)) AS bootstrap_index
),
bootstrap_data AS (
  SELECT mass, bootstrap_index, rand() AS bootstrap_u
  FROM `sql_bootstrap.cats` cats
  JOIN bootstrap_indexes ON TRUE
),
bootstrap_weights AS (
  SELECT bootstrap_data.*, (CASE
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
  FROM bootstrap_data
),
bootstrap_avg AS (
  SELECT bootstrap_index,
    sum(bootstrap_weight * mass) / sum(bootstrap_weight) AS mass_avg
  FROM bootstrap_weights
  GROUP BY bootstrap_index
),
bootstrap AS (
  SELECT bootstrap_index,
    max(mass_avg) AS mass_avg,
    sqrt(sum(bootstrap_weight * power(mass - mass_avg, 2)) /
      sum(bootstrap_weight)) AS mass_sd
  FROM bootstrap_weights
  JOIN bootstrap_avg USING (bootstrap_index)
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
