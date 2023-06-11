library(data.table)

source("make-sql-bootstrap.R")

args <- commandArgs(trailingOnly = TRUE)
resultsFile <- args[1]
dialect <- args[2]
numTrials <- as.numeric(args[3])
command <- args[4]
furtherCommandArgs <-
  if (length(args) > 4) args[5:length(args)] else character()
schema <- "sql_bootstrap"

stopifnot(nchar(resultsFile) > 0)
stopifnot(dialect %in% c("pg", "bq"))
stopifnot(numTrials %in% c(10, 100))
stopifnot(nchar(command) > 0)

if (file.exists(resultsFile)) {
  stopifnot(file.copy(
    resultsFile,
    paste(
      resultsFile, "bak",
      strftime(Sys.time(), "%Y-%m-%dT%H-%M-%S"),
      sep = "."
    ),
    copy.date = TRUE
  ))
} else {
  cat(
    paste0(
      "exampleId,replicates,kind,type,trial,",
      "measureAvg,measureLo,measureHi,elapsed\n"),
    file = resultsFile
  )
}
results <- fread(resultsFile)

examples <- fread("example-data/examples.csv")

grid <- merge(
  CJ(
    exampleId = examples$id,
    replicates = c(125, 250, 500, 1000, 2000),
    kind = c("pure", "poisson"),
    type = c("percent", "student"),
    trial = 1:numTrials
  ),
  examples,
  by.x = "exampleId", by.y = "id"
)

if (dialect == "bq") {
  # We hit the 2500 cpu-second limit for 'pure' with 2000 replicates, and for
  # 'poisson' as well with 1000 replicates with 10^7 cats. (Unless using
  # reserved slots.)
  grid <- grid[
    (kind == "poisson" | replicates < 2000) &
      (numCatsOrder < 8 | replicates < 1000)
  ]
} else {
  # Larger examples take a while; thin out the grid.
  grid <- grid[
    (numCatsOrder < 6) | (
      numCatsOrder == 6 & trial <= 5 & replicates %in% c(1000))
  ]
}

if (numTrials == 100) {
  # For checking the interval rather than benchmarkings
  grid <- grid[numCatsOrder %in% c(2) & replicates %in% c(1000)]
} else {
  grid <- grid[replicates %in% c(1000, 2000)]
}

runQuery <- function(query) {
  start <- proc.time()
  output <- system2(command, furtherCommandArgs, input = query, stdout = TRUE)
  elapsed <- proc.time() - start

  stopifnot(attr(output, "status") == 0)

  # Extract the results from the output; there is probably a nicer way of doing
  # this... but currently it just looks for 3 numbers separated by pipes.
  maybePipe <- "\\s*\\|?\\s*"
  resultRx <- paste0(
    "^", maybePipe,
    paste(rep("([0-9.]+)", times = 3), collapse = "\\s*\\|\\s*"),
    maybePipe, "$"
  )
  resultMatch <- grepl(resultRx, output)
  stopifnot(sum(resultMatch) == 1)
  resultLine <- output[resultMatch]
  measureAvg <- as.numeric(sub(resultRx, "\\1", resultLine))
  measureLo <- as.numeric(sub(resultRx, "\\2", resultLine))
  measureHi <- as.numeric(sub(resultRx, "\\3", resultLine))

  data.table(
    measureAvg, measureLo, measureHi,
    elapsed = summary(elapsed)[["elapsed"]]
  )
}

invisible(by(grid, seq_len(nrow(grid)), function(trialData) {
  if (!results[, any(
    exampleId == trialData$exampleId &
      replicates == trialData$replicates &
      kind == trialData$kind &
      type == trialData$type &
      trial == trialData$trial
  )]
  ) {
    print(trialData[, 1:4])
    query <- trialData[
      , buildBootstrapSql(
        numReplicates = replicates,
        dataTable = tableName,
        bootstrapKind = kind,
        intervalType = type,
        dialect = dialect,
        schema = schema
      )
    ]
    trialResults <- runQuery(query)
    results <<- rbind(results, cbind(trialData[, 1:5], trialResults))
    fwrite(results, file = resultsFile)
  }
}))
