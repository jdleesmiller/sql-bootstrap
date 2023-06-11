#
# Example for use in the blog post: estimating the mean mass of cats.
#

library(boot)
library(data.table)
library(ggplot2)
library(knitr)
library(parallel)

set.seed(5295211)

trueMean <- 4.5
trueSd <- 1
sampleSize <- 10

cats <- data.table(
  catName = c(
    "Apollo", "Bean", "Casper", "Daisy", "Ella",
    "Finn", "Ginger", "Harley", "Iago", "Jasper"
  ),
  mass = rnorm(sampleSize, trueMean, trueSd)
)

printCatsTable <- function(cats) {
  cat(kable(rbind(
    cats[order(catName), .(Name = catName, "Mass (kg)" = round(mass, 1))],
    cats[, .(
      Name = c("**Mean**", "**Std Dev**"),
      "Mass (kg)" = round(c(mean(mass), sd(mass)), 1)
    )]
  )), sep = "\n")
}
printCatsTable(cats)

# Example sample 1:
printCatsTable(cats[sample.int(nrow(cats), replace = TRUE)])

# Example sample 2:
printCatsTable(cats[sample.int(nrow(cats), replace = TRUE)])

# Find bootstrap confidence intervals (percentile and studentized).
bootstrapResamples <- 1000
getBootstrapStats <- function(data, indexes) {
  data[indexes, c(mean(mass), var(mass))]
}
catsBoot <- boot(cats, getBootstrapStats, bootstrapResamples)

catsBootCi <- boot.ci(catsBoot, type = c("perc", "stud"))
catsBootCi

# We know the population variance for this example, so we can get normal CIs.
print("zCI:")
confidenceLevel <- 0.95
q <- (1 + c(-1, 1) * confidenceLevel) / 2
catsZCi <- mean(cats$mass) + qnorm(q) * trueSd / sqrt(sampleSize)
catsZCi

# If we didn't know the population variance, we'd find t CIs.
print("tCI:")
catsTCi <- mean(cats$mass) +
  qt(q, sampleSize - 1) * sd(cats$mass) / sqrt(sampleSize)
catsTCi

# What happens if we just use 1.96 instead of t?
print("approximate 1.96 CI:")
cats196Ci <- mean(cats$mass) + c(-1.96, 1.96) * sd(cats$mass) / sqrt(sampleSize)
cats196Ci

# What t interval confidence level corresponds with the 1.96 interval?
cats196C <- 1 - 2 * pt(-1.96, sampleSize - 1)
cats196C
# Check (should match 1.96 interval):
mean(cats$mass) +
  qt((1 + c(-1, 1) * cats196C) / 2, sampleSize - 1) *
    sd(cats$mass) / sqrt(sampleSize)

# Plot of all the various CIs...
markup <- data.table(
  statistic = c(
    rep("mean", times = 2),
    rep(c("lo", "hi"), times = 4)
  ),
  source = c(
    "true", "sample",
    rep(c("bootstrap", "bootstrapT", "z", "t"), each = 2)
  ),
  mass = c(
    trueMean, mean(cats$mass),
    catsBootCi$percent[4:5],
    catsBootCi$student[4:5],
    catsZCi,
    catsTCi
  )
)
print(markup)

ggsave(
  file = "doc/cats-example-full.svg", width = 8, height = 6,
  ggplot(data.table(mass = catsBoot$t[, 1]), aes(mass)) +
    geom_histogram(binwidth = 0.1) +
    geom_vline(
      data = markup,
      aes(xintercept = mass, color = source, group = statistic)
    )
)

simpleMarkup <- data.table(
  source = c("Sample Mean", rep("Bootstrap 95%CI", 2)),
  statistic = c("mean", "lo", "hi"),
  mass = c(mean(cats$mass), catsBootCi$percent[4:5])
)

# Plot the bootstrap distribution and percentile CIs.
p <- ggplot(data.table(mass = catsBoot$t[, 1]), aes(mass)) +
  geom_histogram(aes(y = after_stat(count / sum(count))), binwidth = 0.1) +
  geom_vline(
    data = simpleMarkup,
    aes(xintercept = mass, color = source, group = statistic),
    linetype = "dashed"
  ) +
  theme(legend.title = element_blank(), legend.position = "bottom") +
  labs(
    title = "Mean mass of an adult domestic cat",
    subtitle = paste0(
      "Empirical bootstrap distribution of the sample mean (",
      bootstrapResamples, " resamples)"
    )
  ) +
  xlab("Mass (kg)") +
  ylab("Probability")

ggsave(
  file = "doc/cats-example.svg", width = 6, height = 4, p
)
ggsave(
  file = "doc/cats-example.png", width = 6, height = 4, p
)

# What is the coverage like for the various intervals?
checkFile <- "doc/cats-check.RData"
if (file.exists(checkFile)) {
  load(checkFile)
} else {
  check <- rbindlist(mclapply(1:10000, function(trial) {
    if (trial %% 100 == 0) print(trial)
    x <- data.table(mass = rnorm(sampleSize, trueMean, trueSd))
    b <- boot(x, getBootstrapStats, bootstrapResamples)
    bci <- boot.ci(b, type = c("basic", "perc", "stud", "bca"))

    sampleMean <- mean(x$mass)
    sampleSd <- sd(x$mass)
    ciZ <- sampleMean + qnorm(q) * trueSd / sqrt(sampleSize)
    ciT <- sampleMean + qt(q, sampleSize - 1) * sampleSd / sqrt(sampleSize)
    ci196 <- sampleMean + c(-1.96, 1.96) * sampleSd / sqrt(sampleSize)

    data.table(
      trial, sampleMean,
      method = factor(rep(
        c("basic", "perc", "stud", "bca", "z", "t", "1.96"),
        each = 2
      )),
      endpoint = factor(rep(c("lo", "hi"), times = 6)),
      value = c(
        bci$basic[4:5], bci$percent[4:5], bci$student[4:5],
        bci$bca[4:5], ciZ, ciT, ci196
      )
    )
  }, mc.cores = detectCores()))
  save(check, file = checkFile)
}
check[, ok := ifelse(endpoint == "lo", value < trueMean, trueMean < value)]
cat(
  kable(check[, .(miss = 1 - mean(ok)), .(method, endpoint)]),
  sep = "\n"
)
