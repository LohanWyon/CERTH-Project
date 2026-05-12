analysisConfig <- list(
  psModel = list(
    maxCohortSizeForFitting = 5000,
    prior = createPrior("laplace", exclude = 0, useCrossValidation = FALSE)
  ),
  psScreening = list(
    enabled = TRUE,
    sampleSize = 500,
    topCovariates = 5000,
    seed = 123
  ),
  adjustment = list(
    method = "stratification",
    caliper = NULL,
    maxRatio = NULL,
    trimFraction = NULL
  ),
  outcomeModel = list(
    modelType = "cox",
    stratified = FALSE
  )
)
