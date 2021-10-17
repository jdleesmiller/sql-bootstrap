#
# Example for appendix A: problems with the classical t confidence intervals in
# web analytics.
#

library(boot)
library(data.table)
library(parallel)

RNGkind("L'Ecuyer-CMRG")
set.seed(8567442)

trueRate <- 2^-(seq(5.7, 8.7, length.out=10))
sampleSize <- c(1e4)
bootstrapReplicates <- c(1000, 2000)
numTrials <- 10000
trials <- CJ(trueRate, sampleSize, trial = 1:numTrials)
trialKeys <- 1:3

# The data are Bernoulli(p) for conversion rate p, so the variance is p(1-p).
trials[, trueSd := sqrt(trueRate * (1 - trueRate))]
trials[, trueSkewness := (1 - 2 * trueRate) / trueSd]

trials[trial == 1]

resultsFile <- 'doc/confidence.RData'
if (file.exists(resultsFile)) {
  load(resultsFile)
} else {
  results <- rbindlist(mclapply(1:nrow(trials), function (i) {
    trialData <- trials[i,]
    if (trialData[, trial] %% 10 == 0) print(trialData)
    q <- c(0.025, 0.975)
    n <- trialData[, sampleSize]
    p <- trialData[, trueRate]
    sample <- runif(n) < p

    bootstrapCis <- unlist(lapply(bootstrapReplicates, function (replicates) {
      bootstrap <- boot(sample, function (data, indexes) {
        c(mean(data[indexes]), var(data[indexes]))
      }, replicates)
      bootstrapCi <- boot.ci(bootstrap, type = c('perc', 'stud'))
      c(bootstrapCi$percent[4:5], bootstrapCi$student[4:5])
    }))

    mu <- mean(sample)
    zCi <- mu + qnorm(q) * trialData[, trueSd] / sqrt(n)
    tCi <- mu + qt(q, n - 1) * sd(sample) / sqrt(n)

    results <- cbind(
      trialData[, ..trialKeys],
      rbind(
        data.table(
          replicates = NA,
          method = factor(c('sample', rep(c('z', 't'), each = 2))),
          endpoint = factor(c('mean', rep(c('lo', 'hi'), times = 2))),
          value = c(mu, zCi, tCi)),
        data.table(
          replicates = rep(bootstrapReplicates, each = 4),
          method = factor(rep(
            rep(c('perc', 'stud'), each = 2),
            times = length(bootstrapReplicates))),
          endpoint = factor(rep(
            c('lo', 'hi'),
            times = 2 * length(bootstrapReplicates))),
          value = bootstrapCis)))

    results[, ok := ifelse(endpoint == 'lo', value < p, p < value)]

    fwrite(results, file = 'results.csv', append = TRUE)

    results
  }, mc.cores = detectCores()))

  save(results, file = resultsFile)
}

misses <- results[method != 'sample',
  .(miss = 1 - mean(ok)),
  .(trueRate, sampleSize, replicates, method, endpoint)]
# misses

library(ggplot2)

p <- ggplot(
  misses[sampleSize == 50000 & replicates %in% c(NA, 2000)],
  aes(x = trueRate, y = miss)) +
  geom_line(aes(color = method)) +
  scale_x_log10() +
  geom_hline(yintercept = 0.025, linetype = 'dashed') +
  facet_grid(endpoint ~ .)
print(p)