explain analyze WITH bootstrap_indexes AS (
  SELECT generate_series(1, 1000) AS bootstrap_index
),
bootstrap_data AS (
  SELECT converted, bootstrap_index, random() AS bootstrap_u
  FROM hits
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
-- this seems much worse than the obvious approach
-- bootstrap AS (
--   SELECT bootstrap_index, t1.rate_avg, t2.rate_sd
--   FROM (
--     SELECT bootstrap_index,
--       sum(bootstrap_weight * converted) / sum(bootstrap_weight) AS rate_avg
--     FROM bootstrap_weights w1
--     GROUP BY bootstrap_index
--   ) t1,
--   LATERAL (
--     SELECT sqrt(sum(bootstrap_weight * power(converted - rate_avg, 2)) /
--       sum(bootstrap_weight)) AS rate_sd
--     FROM bootstrap_weights w2
--     WHERE w2.bootstrap_index = t1.bootstrap_index
--   ) t2
-- ),
-- bootstrap_avg AS (
--   SELECT bootstrap_index,
--     sum(bootstrap_weight * converted) / sum(bootstrap_weight) AS rate_avg
--   FROM bootstrap_weights
--   GROUP BY bootstrap_index
-- ),
-- bootstrap AS (
--   SELECT bootstrap_index,
--     max(rate_avg) AS rate_avg,
--     sqrt(sum(bootstrap_weight * power(converted - rate_avg, 2)) /
--       sum(bootstrap_weight)) AS rate_sd
--   FROM bootstrap_weights
--   JOIN bootstrap_avg USING (bootstrap_index)
--   GROUP BY bootstrap_index
-- ),
-- this 'explain's worse but ends up performing about the same
-- bootstrap AS (
--   SELECT bootstrap_index,
--     MAX(rate_avg) AS rate_avg,
--     sqrt(sum(bootstrap_weight * power(converted - rate_avg, 2)) /
--       sum(bootstrap_weight)) AS rate_sd
--   FROM (
--     SELECT bootstrap_weights.*,
--       (sum(bootstrap_weight * converted) OVER (PARTITION BY bootstrap_index)) /
--       (sum(bootstrap_weight) OVER (PARTITION BY bootstrap_index)) AS rate_avg
--     FROM bootstrap_weights
--   ) t
--   GROUP BY bootstrap_index
-- ),
bootstrap AS (
  SELECT bootstrap_index,
    sum(bootstrap_weight * converted) / sum(bootstrap_weight) AS rate_avg,
    sqrt(sum(bootstrap_weight * power(converted - ((sum(bootstrap_weight * converted) OVER (PARTITION BY bootstrap_index)) /
      (sum(bootstrap_weight) OVER (PARTITION BY bootstrap_index))), 2)) /
      sum(bootstrap_weight)) AS rate_sd
  FROM bootstrap_weights
  GROUP BY bootstrap_index
),
sample AS (
  SELECT avg(converted) AS rate_avg, stddev(converted) AS rate_sd
  FROM hits
),
bootstrap_q AS (
  SELECT
    percentile_cont(0.025) WITHIN GROUP (ORDER BY
      (bootstrap.rate_avg - sample.rate_avg) / bootstrap.rate_sd
    ) AS q_lo,
    percentile_cont(0.975) WITHIN GROUP (ORDER BY
      (bootstrap.rate_avg - sample.rate_avg) / bootstrap.rate_sd
    ) AS q_hi
  FROM bootstrap
  JOIN sample ON TRUE
)
SELECT sample.rate_avg,
  sample.rate_avg - sample.rate_sd * q_hi AS rate_lo,
  sample.rate_avg - sample.rate_sd * q_lo AS rate_hi
FROM sample
JOIN bootstrap_q ON TRUE;
