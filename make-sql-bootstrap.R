#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
stopifnot(grepl('^\\d+$', args[1]))
stopifnot(grepl('^hits', args[2]))
stopifnot(args[3] %in% c('pure', 'poisson'))
stopifnot(args[4] %in% c('pg', 'bq'))
stopifnot(args[5] %in% c('sql_bootstrap', 'none'))

buildBootstrapSql <- function (
  numReplicates,
  dataTable,
  dataTableIdColumn,
  measureSql,
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
    prEvents <- ppois(0:maxN, lambda = 1)
    indent <- strrep(' ', 4)

    buildSql <- function (n) {
      if (n > maxN) {
        paste0('\n', indent, maxN)
      } else {
        paste0(
          '\n', indent,
          'CASE WHEN ', variableName, ' < ', prEvents[n],
          ' THEN ', n - 1,
          ' ELSE ', buildSql(n + 1), ' END')
      }
    }

    buildSql(1)
  }

  buildBootstrapIndexesSql <- function () {
    if (dialect == 'pg')
      paste0('SELECT generate_series(0, ',
               numReplicates, ')', ' AS bootstrap_index')
    else
      paste0('SELECT * FROM UNNEST(generate_array(0, ',
               numReplicates, ')) AS bootstrap_index')
  }

  buildPercentileSql <- function (quantile, column) {
    if (dialect == 'pg')
      paste0('percentile_cont(', quantile,
               ') WITHIN GROUP (ORDER BY ', column, ')')
    else
      paste0('percentile_cont(', column, ', ', quantile,') OVER ()')
  }

  ctes <- c(
    paste0(
      'WITH bootstrap_indexes AS (\n  ', buildBootstrapIndexesSql(), '\n)'
    ),
    paste0(
      'bootstrap_data AS (\n',
      '  SELECT ', dataTable, '.*,',
      ' ROW_NUMBER() OVER (ORDER BY ', dataTableIdColumn, ') - 1',
      ' AS data_index\n',
      '  FROM ', dataTableFrom,
      '\n)'
    )
  )

  if (kind == 'pure') {
    ctes <- c(
      ctes,
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
        'bootstrap_measures AS (\n',
        '  SELECT bootstrap_index, avg(', measureSql, ') AS measure\n',
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
        'bootstrap_variates AS (\n',
        '  SELECT data_index, bootstrap_index, ', random, '() AS bootstrap_u\n',
        '  FROM bootstrap_data\n',
        '  JOIN bootstrap_indexes ON TRUE',
        '\n)'
      ),
      paste0(
        'bootstrap_weights AS (\n',
        '  SELECT data_index, bootstrap_index, (',
        buildPoissonSql('bootstrap_u'), ') AS bootstrap_weight\n',
        '  FROM bootstrap_variates',
        '\n)'
      ),
      paste0(
        'bootstrap_measures AS (\n',
        '  SELECT bootstrap_index,\n',
        '  sum(bootstrap_weight * (', measureSql, ')) /\n',
        '    sum(bootstrap_weight) AS measure\n',
        '  FROM bootstrap_weights\n',
        '  JOIN bootstrap_data USING (data_index)\n',
        '  GROUP BY bootstrap_index',
        '\n)'
      )
    )
  }

  ctes <- c(
    ctes,
    paste0(
      'bootstrap_ci AS (\n',
      '  SELECT\n',
      '    ', buildPercentileSql(0.025, 'measure'), ' AS measure_lo,\n',
      '    ', buildPercentileSql(0.975, 'measure'), ' AS measure_hi\n',
      '  FROM bootstrap_measures',
      if (dialect == 'bq') '\n  LIMIT 1' else '',
      '\n)'),
    paste0(
      'sample_measures AS (\n',
      '  SELECT avg(', measureSql, ') AS measure_avg\n',
      '  FROM ', dataTableFrom,
      '\n)'
    )
  )

  paste0(
    paste(ctes, collapse = ',\n'),
    '\n',
    'SELECT *\n',
    'FROM sample_measures\n',
    'JOIN bootstrap_ci ON TRUE;',
    '\n'
  )
}

cat(buildBootstrapSql(
  numReplicates = as.numeric(args[1]),
  dataTable = args[2],
  'created_at',
  'CASE WHEN converted THEN 1.0 ELSE 0.0 END',
  kind = args[3],
  dialect = args[4],
  schema = args[5]
))
