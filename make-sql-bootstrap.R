#!/usr/bin/env Rscript

buildBootstrapSql <- function (
  numReplicates,
  dataTable,
  dataTableIdColumn = 'id',
  bootstrapKind = 'pure',
  intervalType = 'percent',
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
        'percentile_cont(', quantile, ') WITHIN GROUP (ORDER BY',
        indent, expression, ')')
    else
      paste0(
        'percentile_cont(', expression, ',',
        indent, quantile, ') OVER ()')
  }

  ctes <- paste0(
    'WITH bootstrap_indexes AS (\n  ', buildBootstrapIndexesSql(), '\n)'
  )

  if (bootstrapKind == 'pure') {
    ctes <- c(
      ctes,
      paste0(
        'bootstrap_data AS (\n',
        '  SELECT mass,',
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
        if (intervalType == 'percent') {
            '    avg(mass) AS mass_avg\n'
        } else {
          paste0(
            '    avg(mass) AS mass_avg,\n',
            '    stddev(mass) AS mass_sd\n'
          )
        },
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
        '  SELECT mass, bootstrap_index, ',
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
      if (intervalType == 'percent') {
        paste0(
          'bootstrap AS (\n',
          '  SELECT bootstrap_index,\n',
          '    sum(bootstrap_weight * mass) /',
          ' sum(bootstrap_weight) AS mass_avg\n',
          '  FROM bootstrap_weights\n',
          '  GROUP BY bootstrap_index',
          '\n)'
        )
      } else {
        c(
          paste0(
            'bootstrap_avg AS (\n',
            '  SELECT bootstrap_index,\n',
            '    sum(bootstrap_weight * mass) /',
            ' sum(bootstrap_weight) AS mass_avg\n',
            '  FROM bootstrap_weights\n',
            '  GROUP BY bootstrap_index',
            '\n)'
          ),
          paste0(
            'bootstrap AS (\n',
            '  SELECT bootstrap_index,\n',
            '    max(mass_avg) AS mass_avg,\n',
            '    sqrt(sum(bootstrap_weight * power(mass - mass_avg, 2)) /\n',
            '      sum(bootstrap_weight)) AS mass_sd\n',
            '  FROM bootstrap_weights\n',
            '  JOIN bootstrap_avg USING (bootstrap_index)\n',
            '  GROUP BY bootstrap_index',
            '\n)'
          )
        )
      }
    )
  }

  if (intervalType == 'percent') {
    ctes <- c(
      ctes,
      paste0(
        'bootstrap_ci AS (\n',
        '  SELECT\n',
        '    ', buildPercentileSql(0.025, 'mass_avg', ' '), ' AS mass_lo,\n',
        '    ', buildPercentileSql(0.975, 'mass_avg', ' '), ' AS mass_hi\n',
        '  FROM bootstrap',
        if (dialect == 'bq') '\n  LIMIT 1' else '',
        '\n)'),
      paste0(
        'sample AS (\n',
        '  SELECT avg(mass) AS mass_avg\n',
        '  FROM ', dataTableFrom,
        '\n)'
      )
    )

    paste0(
      paste(ctes, collapse = ',\n'),
      '\n',
      'SELECT *\n',
      'FROM sample\n',
      'JOIN bootstrap_ci ON TRUE;',
      '\n'
    )
  } else {
    indent <- '\n      '
    tSql <- '(bootstrap.mass_avg - sample.mass_avg) / bootstrap.mass_sd'
    ctes <- c(
      ctes,
      paste0(
        'sample AS (\n',
        '  SELECT avg(mass) AS mass_avg, stddev(mass) AS mass_sd\n',
        '  FROM ', dataTableFrom,
        '\n)'
      ),
      paste0(
        'bootstrap_q AS (\n',
        '  SELECT\n',
        '    ', buildPercentileSql(0.025, tSql, indent), ' AS q_lo,\n',
        '    ', buildPercentileSql(0.975, tSql, indent), ' AS q_hi\n',
        '  FROM bootstrap\n',
        '  JOIN sample ON TRUE',
        if (dialect == 'bq') '\n  LIMIT 1' else '',
        '\n)'
      )
    )

    paste0(
      paste(ctes, collapse = ',\n'),
      '\n',
      'SELECT sample.mass_avg,\n',
      '  sample.mass_avg - sample.mass_sd * q_hi AS mass_lo,\n',
      '  sample.mass_avg - sample.mass_sd * q_lo AS mass_hi\n',
      'FROM sample\n',
      'JOIN bootstrap_q ON TRUE;',
      '\n'
    )
  }
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  stopifnot(grepl('^\\d+$', args[1]))
  stopifnot(grepl('^cats', args[2]))
  stopifnot(args[3] %in% c('pure', 'poisson'))
  stopifnot(args[4] %in% c('percent', 'student'))
  stopifnot(args[5] %in% c('pg', 'bq'))
  stopifnot(args[6] %in% c('sql_bootstrap', 'none'))

  cat(buildBootstrapSql(
    numReplicates = as.numeric(args[1]),
    dataTable = args[2],
    bootstrapKind = args[3],
    intervalType = args[4],
    dialect = args[5],
    schema = args[6]
  ))
}
