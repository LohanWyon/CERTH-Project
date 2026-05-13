analysisConfig <-
list(psModel = list(prior = structure(list(priorType = "laplace", 
    variance = 0.01, exclude = NULL, graph = NULL, neighborhood = NULL, 
    useCrossValidation = FALSE, forceIntercept = FALSE), class = "cyclopsPrior"), 
    maxCohortSizeForFitting = 250000L), psScreening = list(enabled = TRUE, 
    sampleSize = 10000L, topCovariates = 200L, seed = 123L), 
    adjustment = list(method = "stratification", caliper = 0.20000000000000001, 
        maxRatio = 1L, trimFraction = 0.10000000000000001), outcomeModel = list(
        modelType = "cox", stratified = TRUE))
