#!/usr/bin/env R

file <- 'example.sql'
cat(
  'CREATE TABLE hits (created_at TIMESTAMP, converted BOOLEAN);\n\n',
  file = file)

conversionRate <- 0.01
hitCreationRate <- 0.1 # per second
numHits <- 10000

startTime <- as.POSIXct('2021-01-01', tz = 'UTC')
hitTimes <- startTime + cumsum(rexp(numHits, hitCreationRate))
hits <- runif(numHits) < conversionRate

cat(paste0(
  'INSERT INTO hits (created_at, converted) VALUES (',
  paste(
    paste(
      paste0("'", hitTimes, "'"),
      hits, sep = ',')
    , collapse = '),('),
  ');\n'
), file = file, append = TRUE)
