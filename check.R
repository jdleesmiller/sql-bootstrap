library(boot)
library(data.table)

args <- commandArgs(trailingOnly = TRUE)
resultsFile <- args[1]

stopifnot(nchar(resultsFile) > 0)

if (file.exists(resultsFile)) {
  load(resultsFile)
} else {
  results <- NULL
}

examples <- fread("example-data/examples.csv")
examples <- examples[numCatsOrder == 2]

grid <- merge(
  CJ(
    exampleId = examples$id,
    replicates = c(1000),
    trial = 1:100
  ),
  examples,
  by.x = "exampleId", by.y = "id"
)

checkMeanConfidenceIntervals <- function(
    df,
    column,
    trueSd,
    replicates,
    useBca = FALSE,
    ...) {
  dx <- df[, .(x = get(column))]

  b <- boot(
    dx,
    function(data, indexes) {
      data[indexes, c(mean(x), var(x))]
    }, replicates, ...
  )

  bci <- boot.ci(b, type = c("perc", "stud"))

  bca <- c(NA, NA)
  if (useBca) {
    bca <- boot.ci(b, type = "bca")$bca[4:5]
  }

  confidenceLevel <- 0.95
  q <- (1 + c(-1, 1) * confidenceLevel) / 2

  sampleMean <- mean(dx$x)
  sampleSd <- sd(dx$x)
  sampleSize <- nrow(dx)

  ciZ <- sampleMean + qnorm(q) * trueSd / sqrt(sampleSize)
  ciT <- sampleMean + qt(q, sampleSize - 1) * sampleSd / sqrt(sampleSize)
  ci196 <- sampleMean + c(-1.96, 1.96) * sampleSd / sqrt(sampleSize)

  data.table(
    replicates = replicates,
    kind = "boot.ci",
    type = c("percent", "student", "bca", "z", "t", "1pt96"),
    measureAvg = sampleMean,
    measureLo = c(
      bci$percent[4], bci$student[4], bca[1], ciZ[1], ciT[1], ci196[1]
    ),
    measureHi = c(
      bci$percent[5], bci$student[5], bca[2], ciZ[2], ciT[2], ci196[2]
    )
  )
}

runTrial <- function(trialData) {
  cats <- fread(trialData[, file])

  out <- NA
  timings <- system.time(local({
    out <<- checkMeanConfidenceIntervals(
      cats, "mass",
      trialData[, trueSd],
      trialData[, replicates],
      parallel = "multicore", ncpus = 4
    )
  }))

  out[, elapsed := summary(timings)[["elapsed"]]]
  out[, user := summary(timings)[["system"]]]
  out[, system := summary(timings)[["system"]]]

  out
}

invisible(by(grid, seq_len(nrow(grid)), function(trialData) {
  if (is.null(results) || !results[, any(
    exampleId == trialData$exampleId &
      replicates == trialData$replicates &
      trial == trialData$trial
  )]) {
    print(trialData[, 1:3])
    trialResults <- runTrial(trialData)
    results <<- rbind(
      results, cbind(
        exampleId = trialData$exampleId,
        trial = trialData$trial,
        trialResults))
    save(results, file = resultsFile)
  }
}))
