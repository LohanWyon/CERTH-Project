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

  outcomeArgs <- CohortMethod::createFitOutcomeModelArgs(
    modelType  = analysisConfig$outcomeModel$modelType,
    stratified = analysisConfig$outcomeModel$stratified
  )

  outcomeModel <- CohortMethod::fitOutcomeModel(
    population          = adjustedPopulation,
    cohortMethodData    = cmData,
    fitOutcomeModelArgs = outcomeArgs
  )

  outcomeModel
}