analysisConfig <-
list(psModel = list(maxCohortSizeForFitting = 5000L, prior = structure(list(
    priorType = "normal", variance = 4L, exclude = 0, graph = NULL, 
    neighborhood = NULL, useCrossValidation = FALSE, forceIntercept = FALSE), class = "cyclopsPrior")), 
    psScreening = list(enabled = TRUE, sampleSize = 500L, topCovariates = 5000L, 
        seed = 123L), adjustment = list(method = "matching", 
        caliper = 2.1400000000000001, maxRatio = 1L, trimFraction = NULL), 
    outcomeModel = list(modelType = "cox", stratified = FALSE))
