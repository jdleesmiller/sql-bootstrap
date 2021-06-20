#
# Example for use in a blog post.
#

library(boot)
library(data.table)
library(ggplot2)
library(knitr)

set.seed(5295211)

trueMean <- 4.5
trueSd <- 1

cats <- data.table(
  catName = c(
    'Apollo', 'Bean', 'Casper', 'Daisy', 'Ella',
    'Finn', 'Ginger', 'Harley', 'Iago', 'Jasper'),
  weight = round(rnorm(10, trueMean, trueSd), 1)
)

printCatsTable <- function(cats) {
  cat(kable(rbind(
    cats[order(catName)],
    cats[, .(catName = '**mean**', weight = round(mean(weight), 1))])
    ), sep = '\n')
}
printCatsTable(cats)

# Example sample 1:
printCatsTable(cats[sample.int(nrow(cats), replace = TRUE)])

# Example sample 2:
printCatsTable(cats[sample.int(nrow(cats), replace = TRUE)])

# Find bootstrap confidence intervals.
catsBoot <- boot(
  cats,
  function (data, indexes) mean(data[indexes, weight]),
  1000)

catsBootCi <- boot.ci(catsBoot, type = 'perc', index = 1)
catsBootCi

# We know the population variance for this example, so we can get normal CIs.
q <- c(0.025, 0.975)
n <- nrow(cats)
catsZCi <- mean(cats$weight) + qnorm(q) * trueSd / sqrt(n)
catsZCi

# If we didn't know the population variance, we'd find t CIs.
catsTCi <- mean(cats$weight) + qt(q, n - 1) * sd(cats$weight) / sqrt(n)
catsTCi

# Plot of all the various CIs...
markup <- data.table(
  statistic = c(
    rep('mean', times = 2),
    rep(c('lo', 'hi'), times = 3)
  ),
  source = c(
    'true', 'sample',
    rep(c('bootstrap', 'z', 't'), each = 2)
  ),
  weight = c(
    trueMean, mean(cats$weight),
    catsBootCi$percent[4:5],
    catsZCi,
    catsTCi
  )
)
markup

ggsave(
  file = 'doc/cats-example-full.svg', width = 4, height = 3,
  ggplot(data.table(weight = catsBoot$t[,1]), aes(weight)) +
    geom_histogram(binwidth = 0.1) +
    geom_vline(
      data = markup,
      aes(xintercept = weight, color = source, group = statistic)))

simpleMarkup <- data.table(
  source = c('Sample Mean', rep('Bootstrap 95%CI', 2)),
  statistic = c('mean', 'lo', 'hi'),
  weight = c(mean(cats$weight), catsBootCi$percent[4:5])
)

ggsave(
  file = 'doc/cats-example.svg', width = 6, height = 4,
  ggplot(data.table(weight = catsBoot$t[,1]), aes(weight)) +
    geom_histogram(aes(y = stat(count / sum(count))), binwidth = 0.1) +
    geom_vline(
      data = simpleMarkup,
      aes(xintercept = weight, color = source, group = statistic),
      linetype = 'dashed') +
      theme(legend.title = element_blank(), legend.position = 'bottom') +
    labs(
      title = 'Mean weight of an adult domestic cat',
      subtitle = 'Empirical bootstrap distribution of the sample mean') +
      xlab('Weight (kg)') +
      ylab('Probability'))
