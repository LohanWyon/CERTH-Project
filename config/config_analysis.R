analysisConfig <-
list(psModel = list(maxCohortSizeForFitting = 5000L, prior = structure(list(
    priorType = "laplace", variance = 1, exclude = 0, graph = NULL, 
    neighborhood = NULL, useCrossValidation = FALSE, forceIntercept = FALSE), class = "cyclopsPrior")), 
    psScreening = list(enabled = TRUE, sampleSize = 500L, topCovariates = 5000L, 
        seed = 123L), adjustment = list(method = "trimming", 
        caliper = NULL, maxRatio = NULL, trimFraction = 0.01), 
    outcomeModel = list(modelType = "cox", stratified = FALSE))
