#!/usr/bin/env Rscript

dataDir <- 'example-data'
hitCreationRate <- 0.1 # per second
startTime <- as.POSIXct('2021-01-01', tz = 'UTC')

set.seed(7750325)
options(digits.secs = 3)

generateExampleData <- function (conversionRate, numHits) {
  createdAt <- startTime + cumsum(rexp(numHits, hitCreationRate))
  converted <- runif(numHits) < conversionRate
  data.frame(created_at = createdAt, converted = converted)
}

examples <- merge(
  data.frame(conversionRate = c(0.01, 0.02)),
  data.frame(numHitsOrder = c(3, 4, 5, 6, 7)), by = NULL)
examples <- cbind(id = 1:nrow(examples), examples)
examples$file <- file.path(dataDir, paste0('hits-', examples$id, '.csv'))
examples$tableName <- paste('hits', examples$id, sep = '_')

invisible(by(examples, 1:nrow(examples), function (example) {
  data <- generateExampleData(example$conversionRate, 10 ^ example$numHitsOrder)
  write.csv(data, file = example$file, row.names = FALSE)
  NULL
}))

write.csv(
  examples,
  file = file.path(dataDir, 'examples.csv'),
  row.names = FALSE)
