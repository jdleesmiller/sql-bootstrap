#!/usr/bin/env Rscript

dataDir <- 'example-data'

examples <- read.csv(file.path(dataDir, 'examples.csv'))

cat(with(
  examples,
  paste(
    'DROP TABLE IF EXISTS',
    tableName,
    ';',
    collapse = '\n'),
))
cat('\n\n')

cat(with(
  examples,
  paste(
    'CREATE TABLE',
    tableName,
    '(created_at TIMESTAMP, converted BOOLEAN);', collapse = '\n'),
))
cat('\n\n')

cat(with(
  examples,
  paste(
    '\\COPY', tableName,
    'FROM', paste0("'", file, "'"),
    'WITH CSV HEADER;', collapse = '\n')
))
cat('\n')
