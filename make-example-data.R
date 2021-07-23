#!/usr/bin/env Rscript

library(data.table)

dataDir <- 'example-data'

set.seed(8248246)
options(digits.secs = 3)

trueMean <- 4.5
trueSd <- 1
numCatsOrder <- 3:7
examples <- CJ(trueMean, trueSd, numCatsOrder)
examples[, id := 1:nrow(examples)]
examples[, file := file.path(dataDir, paste0('cats-', examples$id, '.csv'))]
examples[, tableName := paste('cats', examples$id, sep = '_')]

invisible(by(examples, examples$id, function (example) {
  n <- 10^example$numCatsOrder
  data <- data.table(id = 1:n, mass = rnorm(n, trueMean, trueSd))
  fwrite(data, file = example$file)
  NULL
}))

fwrite(examples, file = file.path(dataDir, 'examples.csv'))