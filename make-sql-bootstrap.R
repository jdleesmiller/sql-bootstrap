#!/usr/bin/env Rscript

buildBootstrapSql <- function (
  numReplicates,
  dataTable,
  dataTableIdColumn = 'created_at',
  kind = 'pure',
  dialect = 'pg',
  schema = 'none'
) {
  dataTableFrom <- if (schema == 'none')
                     dataTable
                   else
                     if (dialect == 'bq')
                       paste0('`', schema, '.', dataTable, '` ', dataTable)
                     else
                       paste0(schema, '.', dataTable, ' ', dataTable)

  random <- if (dialect == 'bq') 'rand' else 'random'

  # SQL to sample from Poisson(1) using inverse transform sampling.
  buildPoissonSql <- function (variableName, indent = 4, maxN = 15) {
    nEvents <- 0:(maxN - 1)
    prEvents <- ppois(nEvents, lambda = 1)
    indent <- paste0('\n', strrep(' ', 4))

    paste0(
      'CASE', indent,
      paste(
        'WHEN bootstrap_u <', prEvents, 'THEN', nEvents,
        collapse = indent),
      indent,
      'ELSE ', maxN, ' END')
  }

  buildBootstrapIndexesSql <- function () {
    if (dialect == 'pg')
      paste0('SELECT generate_series(1, ',
               numReplicates, ')', ' AS bootstrap_index')
    else
      paste0('SELECT * FROM UNNEST(generate_array(1, ',
               numReplicates, ')) AS bootstrap_index')
  }

  buildPercentileSql <- function (quantile, expression, indent) {
    if (dialect == 'pg')
      paste0(
        'percentile_cont(', quantile, ') WITHIN GROUP (ORDER BY\n',
        indent, '  ', expression, ')')
    else
      paste0(
        'percentile_cont(', expression, ',\n',
        indent, '  ', quantile, ') OVER ()')
  }

  ctes <- paste0(
    'WITH bootstrap_indexes AS (\n  ', buildBootstrapIndexesSql(), '\n)'
  )

  if (kind == 'pure') {
    ctes <- c(
      ctes,
      paste0(
        'bootstrap_data AS (\n',
        '  SELECT converted,',
        ' ROW_NUMBER() OVER (ORDER BY ', dataTableIdColumn, ') - 1',
        ' AS data_index\n',
        '  FROM ', dataTableFrom,
        '\n)'
      ),
      paste0(
        'bootstrap_map AS (\n',
        '  SELECT floor(', random, '() * (\n',
        '    SELECT count(data_index) FROM bootstrap_data)) AS data_index,\n',
        '    bootstrap_index\n',
        '  FROM bootstrap_data\n',
        '  JOIN bootstrap_indexes ON TRUE',
        '\n)'
      ),
      paste0(
        'bootstrap AS (\n',
        '  SELECT bootstrap_index,\n',
        '    avg(converted) AS rate_avg,\n',
        '    stddev(converted) AS rate_sd\n',
        '  FROM bootstrap_map\n',
        '  JOIN bootstrap_data USING (data_index)\n',
        '  GROUP BY bootstrap_index',
        '\n)'
      )
    )
  } else {
    ctes <- c(
      ctes,
      paste0(
        'bootstrap_data AS (\n',
        '  SELECT converted, bootstrap_index, ',
          random, '() AS bootstrap_u\n',
        '  FROM ', dataTableFrom, '\n',
        '  JOIN bootstrap_indexes ON TRUE',
        '\n)'
      ),
      paste0(
        'bootstrap_weights AS (\n',
        '  SELECT bootstrap_data.*, (',
        buildPoissonSql('bootstrap_u'), ') AS bootstrap_weight\n',
        '  FROM bootstrap_data',
        '\n)'
      ),
      paste0(
        'bootstrap_avg AS (\n',
        '  SELECT bootstrap_index,\n',
        '    sum(bootstrap_weight * converted) /',
        ' sum(bootstrap_weight) AS rate_avg\n',
        '  FROM bootstrap_weights\n',
        '  GROUP BY bootstrap_index',
        '\n)'
      ),
      paste0(
        'bootstrap AS (\n',
        '  SELECT bootstrap_index,\n',
        '    max(rate_avg) AS rate_avg,\n',
        '    sqrt(sum(bootstrap_weight * power(converted - rate_avg, 2)) /\n',
        '      sum(bootstrap_weight)) AS rate_sd\n',
        '  FROM bootstrap_weights\n',
        '  JOIN bootstrap_avg USING (bootstrap_index)\n',
        '  GROUP BY bootstrap_index',
        '\n)'
      )
    )
  }

  tSql <- '(bootstrap.rate_avg - sample.rate_avg) / bootstrap.rate_sd'
  ctes <- c(
    ctes,
    paste0(
      'sample AS (\n',
      '  SELECT avg(converted) AS rate_avg, stddev(converted) AS rate_sd\n',
      '  FROM ', dataTableFrom,
      '\n)'
    ),
    paste0(
      'bootstrap_q AS (\n',
      '  SELECT\n',
      '    ', buildPercentileSql(0.025, tSql, '    '), ' AS q_lo,\n',
      '    ', buildPercentileSql(0.975, tSql, '    '), ' AS q_hi\n',
      '  FROM bootstrap\n',
      '  JOIN sample ON TRUE',
      if (dialect == 'bq') '\n  LIMIT 1' else '',
      '\n)'
    )
  )

  paste0(
    paste(ctes, collapse = ',\n'),
    '\n',
    'SELECT sample.rate_avg,\n',
    '  sample.rate_avg - sample.rate_sd * q_hi AS rate_lo,\n',
    '  sample.rate_avg - sample.rate_sd * q_lo AS rate_hi\n',
    'FROM sample\n',
    'JOIN bootstrap_q ON TRUE;',
    '\n'
  )
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  stopifnot(grepl('^\\d+$', args[1]))
  stopifnot(grepl('^hits', args[2]))
  stopifnot(args[3] %in% c('pure', 'poisson'))
  stopifnot(args[4] %in% c('pg', 'bq'))
  stopifnot(args[5] %in% c('sql_bootstrap', 'none'))

  cat(buildBootstrapSql(
    numReplicates = as.numeric(args[1]),
    dataTable = args[2],
    kind = args[3],
    dialect = args[4],
    schema = args[5]
  ))
}
