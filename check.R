library(boot)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
resultsFile <- args[1]

stopifnot(nchar(resultsFile) > 0)

if (!file.exists(resultsFile)) {
  cat(
    'exampleId,replicates,measureAvg,measureLo,measureHi,elapsed,user,system\n',
    file = resultsFile)
}
results <- fread(resultsFile)

examples <- fread('example-data/examples.csv')
examples <- examples[numHitsOrder < 7]

grid <- merge(
  CJ(
    exampleId = examples$id,
    replicates = c(500, 1000, 2000)
  ),
  examples, by.x = 'exampleId', by.y = 'id'
)

runTrial <- function(trialData) {
  hits <- fread(trialData[, file])

  ci <- NA
  timings <- system.time(local({
    b <- boot(
      hits,
      function (data, indexes) mean(data[indexes, converted]),
      trialData[, replicates],
      parallel = 'multicore', ncpus = 3
    )
    ci <<- boot.ci(b, type = 'perc', index = 1)
  }))

  print(ci)

  data.table(
    measureAvg = mean(hits$converted),
    measureLo = ci$percent[4],
    measureHi = ci$percent[5],
    elapsed = summary(timings)[['elapsed']],
    user = summary(timings)[['user']],
    system = summary(timings)[['system']]
  )
}

invisible(by(grid, 1:nrow(grid), function (trialData) {
  if (!results[, any(
    exampleId == trialData$exampleId &
    replicates == trialData$replicates)]
  ) {
    print(trialData[, 1:2])
    trialResults <- runTrial(trialData)
    results <<- rbind(results, cbind(trialData[, 1:2], trialResults))
    fwrite(results, file = resultsFile)
  }
}))
