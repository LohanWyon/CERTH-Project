# app_helpers.R

parse_csv_ids <- function(x) {
  x <- trimws(unlist(strsplit(x, ",")))
  x <- x[nzchar(x)]
  as.numeric(x)
}

parse_csv_strings <- function(x) {
  x <- trimws(unlist(strsplit(x, ",")))
  x[nzchar(x)]
}

null_if_empty <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  x_chr <- trimws(as.character(x))
  if (length(x_chr) == 0 || all(!nzchar(x_chr))) {
    return(NULL)
  }
  x
}

null_if_na <- function(x) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    return(NULL)
  }
  x
}

build_config_from_input <- function(input, duckdb_path) {
  connectionConfig <- list(
    dbms = "duckdb",
    server = duckdb_path,
    user = NULL,
    password = NULL,
    port = NULL,
    pathToDriver = NULL,
    oracleTempSchema = null_if_empty(input$oracleTempSchema)
  )

  cohortsConfig <- list(
    cohortDatabaseSchema = input$cohortDatabaseSchema,
    cohortTable = input$cohortTable,
    targetId = input$targetId,
    comparatorId = input$comparatorId,
    outcomeIds = parse_csv_ids(input$outcomeIds),
    primaryOutcomeId = input$primaryOutcomeId,
    targetName = "target",
    comparatorName = "comparator",
    targetJsonFile = input$targetJsonFile,
    comparatorJsonFile = input$comparatorJsonFile,
    outcomeJsonFiles = parse_csv_strings(input$outcomeJsonFiles)
  )

  cmDataConfig <- list(
    cdmDatabaseSchema = input$cdmDatabaseSchema,
    oracleTempSchema = null_if_empty(input$oracleTempSchema),
    studyStartDate = input$studyStartDate,
    studyEndDate = input$studyEndDate,
    covariateSettings = FeatureExtraction::createDefaultCovariateSettings()
  )

  studyPopulationConfig <- list(
    removeDuplicateSubjects = input$removeDuplicateSubjects,
    removeSubjectsWithPriorOutcome = input$removeSubjectsWithPriorOutcome,
    priorOutcomeLookback = input$priorOutcomeLookback,
    requireTimeAtRisk = TRUE,
    minTimeAtRisk = 1,
    riskWindowStart = input$riskWindowStart,
    startAnchor = input$startAnchor,
    riskWindowEnd = input$riskWindowEnd,
    endAnchor = input$endAnchor,
    restrictToCommonPeriod = input$restrictToCommonPeriod,
    firstExposureOnly = input$firstExposureOnly,
    washoutPeriod = input$washoutPeriod
  )

  analysisConfig <- list(
    psModel = list(
      maxCohortSizeForFitting = input$maxCohortSizeForFitting,
      prior = Cyclops::createPrior(
        "laplace",
        exclude = 0,
        useCrossValidation = FALSE
      )
    ),
    psScreening = list(
      enabled = input$psScreening_enabled,
      sampleSize = input$psScreening_sampleSize,
      topCovariates = input$psScreening_topCovariates,
      seed = input$psScreening_seed
    ),
    adjustment = list(
      method = input$adjustment_method,
      caliper = null_if_na(input$caliper),
      maxRatio = null_if_na(input$maxRatio),
      trimFraction = null_if_na(input$trimFraction)
    ),
    outcomeModel = list(
      modelType = input$modelType,
      stratified = input$stratified
    )
  )

  runtimeConfig <- list(
    outputFolder = input$outputFolder,
    createCohorts = input$createCohorts,
    saveIntermediateRds = input$saveIntermediateRds,
    verbose = input$verbose
  )

  list(
    connectionConfig = connectionConfig,
    cohortsConfig = cohortsConfig,
    cmDataConfig = cmDataConfig,
    studyPopulationConfig = studyPopulationConfig,
    analysisConfig = analysisConfig,
    runtimeConfig = runtimeConfig
  )
}

write_r_list <- function(object_name, object_value, file) {
  dump(
    list = object_name,
    file = file,
    envir = list2env(setNames(list(object_value), object_name))
  )
}

write_all_config_files <- function(cfg) {
  if (!dir.exists("config")) dir.create("config", recursive = TRUE)

  write_r_list("connectionConfig", cfg$connectionConfig, "config/config_connection.R")
  write_r_list("cohortsConfig", cfg$cohortsConfig, "config/config_cohorts.R")
  write_r_list("cmDataConfig", cfg$cmDataConfig, "config/config_cm_data.R")
  write_r_list("studyPopulationConfig", cfg$studyPopulationConfig, "config/config_study_population.R")
  write_r_list("analysisConfig", cfg$analysisConfig, "config/config_analysis.R")
  write_r_list("runtimeConfig", cfg$runtimeConfig, "config/config_runtime.R")
}