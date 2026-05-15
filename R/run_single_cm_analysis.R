# run_single_cm_analysis.R

library(magrittr)

build_cm_data <- function(connectionDetails,
                          cohortsConfig,
                          cmDataConfig,
                          studyPopulationConfig,
                          runtimeConfig) {
  if (isTRUE(runtimeConfig$verbose)) {
    message("Building CohortMethod study data...")
  }

  getDbArgs <- CohortMethod::createGetDbCohortMethodDataArgs(
    removeDuplicateSubjects = studyPopulationConfig$removeDuplicateSubjects,
    firstExposureOnly = studyPopulationConfig$firstExposureOnly,
    washoutPeriod = studyPopulationConfig$washoutPeriod,
    restrictToCommonPeriod = studyPopulationConfig$restrictToCommonPeriod,
    studyStartDate = cmDataConfig$studyStartDate,
    studyEndDate = cmDataConfig$studyEndDate,
    covariateSettings = cmDataConfig$covariateSettings
  )

  cmData <- CohortMethod::getDbCohortMethodData(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cmDataConfig$cdmDatabaseSchema,
    targetId = cohortsConfig$targetId,
    comparatorId = cohortsConfig$comparatorId,
    outcomeIds = cohortsConfig$outcomeIds,
    exposureDatabaseSchema = cohortsConfig$cohortDatabaseSchema,
    exposureTable = cohortsConfig$cohortTable,
    outcomeDatabaseSchema = cohortsConfig$cohortDatabaseSchema,
    outcomeTable = cohortsConfig$cohortTable,
    getDbCohortMethodDataArgs = getDbArgs
  )

  cmData
}

build_study_population <- function(cmData,
                                   cohortsConfig,
                                   studyPopulationConfig,
                                   runtimeConfig) {
  if (isTRUE(runtimeConfig$verbose)) {
    message("Creating study population...")
  }

  # Arguments volontairement réduits pour être compatibles avec plus de versions
  spArgs <- CohortMethod::createCreateStudyPopulationArgs(
    removeSubjectsWithPriorOutcome = studyPopulationConfig$removeSubjectsWithPriorOutcome,
    priorOutcomeLookback = studyPopulationConfig$priorOutcomeLookback,
    riskWindowStart = studyPopulationConfig$riskWindowStart,
    startAnchor = studyPopulationConfig$startAnchor,
    riskWindowEnd = studyPopulationConfig$riskWindowEnd,
    endAnchor = studyPopulationConfig$endAnchor
  )

  population <- CohortMethod::createStudyPopulation(
    cohortMethodData = cmData,
    outcomeId = cohortsConfig$primaryOutcomeId,
    createStudyPopulationArgs = spArgs
  )

  if (nrow(population) == 0) {
    stop("Study population is empty after applying inclusion/exclusion criteria.")
  }

  population
}

fit_ps_model <- function(population,
                         cmData,
                         analysisConfig,
                         runtimeConfig) {
  if (isTRUE(runtimeConfig$verbose)) {
    message("Fitting propensity score model...")
  }

  screeningEnabled <- isTRUE(analysisConfig$psScreening$enabled)

  if (!screeningEnabled) {
    psArgs <- CohortMethod::createCreatePsArgs(
      maxCohortSizeForFitting = analysisConfig$psModel$maxCohortSizeForFitting,
      errorOnHighCorrelation = FALSE,
      stopOnError = FALSE,
      prior = analysisConfig$psModel$prior
    )

    ps <- CohortMethod::createPs(
      cohortMethodData = cmData,
      population = population,
      createPsArgs = psArgs
    )

    return(ps)
  }

  sampleSize <- min(
    analysisConfig$psScreening$sampleSize,
    nrow(population)
  )

  set.seed(analysisConfig$psScreening$seed)

  sampleIdx <- sample(seq_len(nrow(population)), size = sampleSize)
  populationSample <- population[sampleIdx, , drop = FALSE]

  if (isTRUE(runtimeConfig$verbose)) {
    message("PS screening enabled.")
    message("Screening sample size: ", nrow(populationSample))
  }

  psArgsScreen <- CohortMethod::createCreatePsArgs(
    maxCohortSizeForFitting = sampleSize,
    errorOnHighCorrelation = FALSE,
    stopOnError = FALSE,
    prior = analysisConfig$psModel$prior
  )

  psScreen <- CohortMethod::createPs(
    cohortMethodData = cmData,
    population = populationSample,
    createPsArgs = psArgsScreen
  )

  if (isTRUE(runtimeConfig$verbose)) {
    message("Extracting selected covariates from screening PS model...")
  }

  psModel <- CohortMethod::getPsModel(
    propensityScore = psScreen,
    cohortMethodData = cmData
  )

  if (nrow(psModel) == 0) {
    warning("PS screening returned no selected covariates. Falling back to full PS model.")
    psArgs <- CohortMethod::createCreatePsArgs(
      maxCohortSizeForFitting = analysisConfig$psModel$maxCohortSizeForFitting,
      errorOnHighCorrelation = FALSE,
      stopOnError = FALSE,
      prior = analysisConfig$psModel$prior
    )

    ps <- CohortMethod::createPs(
      cohortMethodData = cmData,
      population = population,
      createPsArgs = psArgs
    )

    return(ps)
  }

  coefCol <- NULL
  possibleCoefCols <- c("coefficient", "estimate", "value")
  for (nm in possibleCoefCols) {
    if (nm %in% colnames(psModel)) {
      coefCol <- nm
      break
    }
  }

  covIdCol <- NULL
  possibleCovIdCols <- c("covariateId", "covariate_id")
  for (nm in possibleCovIdCols) {
    if (nm %in% colnames(psModel)) {
      covIdCol <- nm
      break
    }
  }

  if (is.null(coefCol) || is.null(covIdCol)) {
    stop("Could not identify coefficient/covariate ID columns in getPsModel() output.")
  }

  psModel$absCoef <- abs(psModel[[coefCol]])
  psModel <- psModel[order(-psModel$absCoef), , drop = FALSE]

  psModel <- psModel[!is.na(psModel[[covIdCol]]), , drop = FALSE]
  psModel <- psModel[psModel[[covIdCol]] != 0, , drop = FALSE]

  selectedIds <- unique(head(
    psModel[[covIdCol]],
    analysisConfig$psScreening$topCovariates
  ))

  if (length(selectedIds) == 0) {
    warning("No covariates selected after screening. Falling back to full PS model.")
    psArgs <- CohortMethod::createCreatePsArgs(
      maxCohortSizeForFitting = analysisConfig$psModel$maxCohortSizeForFitting,
      errorOnHighCorrelation = FALSE,
      stopOnError = FALSE,
      prior = analysisConfig$psModel$prior
    )

    ps <- CohortMethod::createPs(
      cohortMethodData = cmData,
      population = population,
      createPsArgs = psArgs
    )

    return(ps)
  }

  if (isTRUE(runtimeConfig$verbose)) {
    message("Selected ", length(selectedIds), " covariates for final PS model.")
  }

  psArgsFinal <- CohortMethod::createCreatePsArgs(
    maxCohortSizeForFitting = analysisConfig$psModel$maxCohortSizeForFitting,
    errorOnHighCorrelation = FALSE,
    stopOnError = FALSE,
    prior = analysisConfig$psModel$prior,
    includeCovariateIds = selectedIds
  )

  ps <- CohortMethod::createPs(
    cohortMethodData = cmData,
    population = population,
    createPsArgs = psArgsFinal
  )

  ps
}

apply_adjustment <- function(ps,
                             analysisConfig,
                             runtimeConfig) {
  method <- analysisConfig$adjustment$method

  if (isTRUE(runtimeConfig$verbose)) {
    message(paste0("Applying adjustment method: ", method))
  }

  if (identical(method, "matching")) {
    # Créer les arguments de matching
    matchArgs <- CohortMethod::createMatchOnPsArgs(
      caliper = analysisConfig$adjustment$caliper,
      maxRatio = analysisConfig$adjustment$maxRatio
    )

    return(
      CohortMethod::matchOnPs(
        population = ps,
        matchOnPsArgs = matchArgs
      )
    )
  }

  if (identical(method, "stratification")) {
    stratArgs <- CohortMethod::createStratifyByPsArgs()

    return(
      CohortMethod::stratifyByPs(
        population = ps,
        stratifyByPsArgs = stratArgs
      )
    )
  }

  if (identical(method, "trimming")) {
    trimArgs <- CohortMethod::createTrimByPsToEquipoiseArgs(
      trimFraction = analysisConfig$adjustment$trimFraction
    )

    return(
      CohortMethod::trimByPsToEquipoise(
        population = ps,
        trimByPsToEquipoiseArgs = trimArgs
      )
    )
  }

  stop("Unsupported adjustment method: ", method)
}

fit_outcome <- function(adjustedPopulation,
                        cmData,
                        analysisConfig,
                        runtimeConfig) {
  if (isTRUE(runtimeConfig$verbose)) {
    message("Fitting outcome model...")
  }

  priorOutcome <- Cyclops::createPrior(
    priorType = "normal", # ridge
    useCrossValidation = FALSE,
    variance = 2 # pénalisation modérée
  )

  outcomeArgs <- CohortMethod::createFitOutcomeModelArgs(
    modelType  = analysisConfig$outcomeModel$modelType,
    stratified = analysisConfig$outcomeModel$stratified,
    prior      = priorOutcome
  )

  outcomeModel <- CohortMethod::fitOutcomeModel(
    population          = adjustedPopulation,
    cohortMethodData    = cmData,
    fitOutcomeModelArgs = outcomeArgs
  )

  outcomeModel
}
