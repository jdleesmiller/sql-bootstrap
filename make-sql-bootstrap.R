#!/usr/bin/env Rscript

buildBootstrapSql <- function (
  numReplicates,
  dataTable,
  dataTableIdColumn = 'created_at',
  measureSql = 'CASE WHEN converted THEN 1.0 ELSE 0.0 END',
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

  buildPercentileSql <- function (quantile, column) {
    if (dialect == 'pg')
      paste0('percentile_cont(', quantile,
               ') WITHIN GROUP (ORDER BY ', column, ')')
    else
      paste0('percentile_cont(', column, ', ', quantile,') OVER ()')
  }

  ctes <- paste0(
    'WITH bootstrap_indexes AS (\n  ', buildBootstrapIndexesSql(), '\n)'
  )

  if (kind == 'pure') {
    ctes <- c(
      ctes,
      paste0(
        'bootstrap_data AS (\n',
        '  SELECT ', dataTable, '.*,',
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
        '  SELECT ', dataTable, '.*, bootstrap_index, ',
          random, '() AS bootstrap_u\n',
        '  FROM ', dataTableFrom, '\n',
        '  JOIN bootstrap_indexes ON TRUE',
        '\n)'
      ),
      paste0(
        'bootstrap_weights AS (\n',
        '  SELECT bootstrap_variates.*, (',
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
