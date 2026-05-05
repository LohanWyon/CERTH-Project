analysisConfig <- list(
  psModel = list(
    maxCohortSizeForFitting = 250000,
    errorOnHighCorrelation = FALSE,
    prior = createPrior("laplace", exclude = 0, useCrossValidation = TRUE)
  ),
  adjustment = list(
    method = "stratification",  # <- au lieu de "matching"
    caliper = 5.0,
    maxRatio = 10,
    trimFraction = NULL
  ),
  outcomeModel = list(
    modelType = "cox",
    stratified = TRUE
  )
)