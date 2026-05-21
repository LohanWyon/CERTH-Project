# preset_local.R

appPreset <- list(
  dbms = "duckdb",
  oracleTempSchema = "",

  cohortDatabaseSchema = "main",
  cohortTable = "cohort",
  targetId = 1,
  comparatorId = 2,
  outcomeIds = "3",
  primaryOutcomeId = 3,
  targetJsonFile = "inst/cohorts/target.json",
  comparatorJsonFile = "inst/cohorts/comparator.json",
  outcomeJsonFiles = "inst/cohorts/outcome.json",

  cdmDatabaseSchema = "main",
  studyStartDate = "",
  studyEndDate = "",

  firstExposureOnly = TRUE,
  washoutPeriod = 183,
  removeSubjectsWithPriorOutcome = TRUE,
  priorOutcomeLookback = 99999,
  riskWindowStart = 1,
  riskWindowEnd = 30,
  startAnchor = "cohort start",
  endAnchor = "cohort start",
  removeDuplicateSubjects = "keep first",
  restrictToCommonPeriod = FALSE,

  ps_prior_type = "normal",
  ps_prior_variance = 4,
  ps_prior_cv = FALSE,

  maxCohortSizeForFitting = 5000,

  psScreening_enabled = TRUE,
  psScreening_sampleSize = 500,
  psScreening_topCovariates = 5000,
  psScreening_seed = 123,

  adjustment_method = "matching",
  caliper = 2.14,
  maxRatio = 1,
  trimFraction = NULL,

  modelType = "cox",
  stratified = FALSE,

  outputFolder = "results",
  createCohorts = TRUE,
  saveIntermediateRds = TRUE,
  verbose = TRUE
)