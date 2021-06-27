library(data.table)

source('make-sql-bootstrap.R')

args <- commandArgs(trailingOnly = TRUE)
resultsFile <- args[1]
dialect <- args[2]
numTrials <- as.numeric(args[3])
command <- args[4]
furtherCommandArgs <-
  if (length(args) > 4) args[5:length(args)] else character()
schema <- 'sql_bootstrap'

stopifnot(nchar(resultsFile) > 0)
stopifnot(dialect %in% c('pg', 'bq'))
stopifnot(numTrials > 0)
stopifnot(nchar(command) > 0)

if (!file.exists(resultsFile)) {
  cat(
    'exampleId,replicates,kind,trial,measureAvg,measureLo,measureHi,elapsed\n',
    file = resultsFile)
}
results <- fread(resultsFile)

examples <- fread('example-data/examples.csv')

if (dialect == 'pg') examples <- examples[numHitsOrder < 6]

grid <- merge(
  CJ(
    exampleId = examples$id,
    replicates = c(125, 250, 500, 1000, 2000),
    kind = c('pure', 'poisson'),
    trial = 1:numTrials
  ),
  examples, by.x = 'exampleId', by.y = 'id'
)

if (dialect == 'bq') {
  # We hit the 2500 cpu-second limit for 'pure' with 2000 replicates, and for
  # 'poisson' as well with 1000 replicates with 10^7 hits.
  grid <- grid[
    (kind == 'poisson' | replicates < 2000) &
    (numHitsOrder < 7 | replicates < 1000)]
}

runQuery <- function(query) {
  start <- proc.time()
  output <- system2(command, furtherCommandArgs, input = query, stdout = TRUE)
  elapsed <- proc.time() - start

  stopifnot(attr(output, 'status') == 0)

  # Extract the results from the output; there is probably a nicer way of doing
  # this... but currently it just looks for 3 numbers separated by pipes.
  maybePipe <- '\\s*\\|?\\s*'
  resultRx <- paste0(
    '^', maybePipe,
    paste(rep('([0-9.]+)', times = 3), collapse = '\\s*\\|\\s*'),
    maybePipe, '$')
  resultMatch <- grepl(resultRx, output)
  stopifnot(sum(resultMatch) == 1)
  resultLine <- output[resultMatch]
  measureAvg <- as.numeric(sub(resultRx, '\\1', resultLine))
  measureLo <- as.numeric(sub(resultRx, '\\2', resultLine))
  measureHi <- as.numeric(sub(resultRx, '\\3', resultLine))

  data.table(
    measureAvg, measureLo, measureHi,
    elapsed = summary(elapsed)[['elapsed']]
  )
}

invisible(by(grid, 1:nrow(grid), function (trialData) {
  if (!results[, any(
    exampleId == trialData$exampleId &
    replicates == trialData$replicates &
    kind == trialData$kind &
    trial == trialData$trial)]
  ) {
    print(trialData[, 1:4])
    query <- trialData[
      , buildBootstrapSql(
          numReplicates = replicates,
          dataTable = tableName,
          kind = kind,
          dialect = dialect,
          schema = schema)]
    trialResults <- runQuery(query)
    results <<- rbind(results, cbind(trialData[, 1:4], trialResults))
    fwrite(results, file = resultsFile)
  }
}))
