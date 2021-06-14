#!/usr/bin/env Rscript

dataDir <- 'example-data'

examples <- read.csv(file.path(dataDir, 'examples.csv'))

cat(with(
  examples,
  paste(
    'DROP TABLE IF EXISTS',
    tableName,
    ';', collapse = '\n'),
))
cat('\n')
