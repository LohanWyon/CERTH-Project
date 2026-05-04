# run_plp_from_config.R
# Generic PLP script using external config files and ATLAS JSON cohort definitions

# ---------------------------
# Block 0: packages
# ---------------------------
library(DatabaseConnector)
library(SqlRender)
library(PatientLevelPrediction)
library(CohortGenerator)
library(CirceR)
library(FeatureExtraction)

options(scipen = 999)

# ---------------------------
# Block 0bis: project_root + precheck
# ---------------------------

if (exists("project_root_for_plp", inherits = TRUE)) {
  project_root <- normalizePath(project_root_for_plp, winslash = "/", mustWork = TRUE)
} else if (file.exists("precheck_plp.R")) {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
} else if (file.exists(file.path("..", "precheck_plp.R"))) {
  project_root <- normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = TRUE)
} else {
  stop("Could not determine project root")
}

cat("project_root =", project_root, "\n")

source(file.path(project_root, "precheck_plp.R"))

# ---------------------------
# Block 1: load config files only if needed
# ---------------------------

if (!exists("dbms") || !exists("server")) {
  source(file.path(project_root, "config", "config_connection.R"))
}

if (!exists("targetCohortId") ||
    !exists("outcomeCohortId") ||
    !exists("cohortTable") ||
    !exists("targetJsonFile") ||
    !exists("outcomeJsonFile")) {
  source(file.path(project_root, "config", "config_cohorts.R"))
}

if (!exists("outputFolder") ||
    !exists("analysisId") ||
    !exists("analysisName")) {
  source(file.path(project_root, "config", "config_runtime.R"))
}

if (!exists("modelSettings")) {
  source(file.path(project_root, "config", "config_model.R"))
}

if (!exists("covariateSettings")) {
  source(file.path(project_root, "config", "config_covariates.R"))
}

# ---------------------------
# Block 1bis: normalize paths relative to project_root
# ---------------------------

# Valeurs par défaut si rien n'a été fourni par l'UI ni les configs
if (!exists("targetJsonFile") || is.null(targetJsonFile)) {
  targetJsonFile <- file.path("cohorts", "target.json")
}
if (!exists("outcomeJsonFile") || is.null(outcomeJsonFile)) {
  outcomeJsonFile <- file.path("cohorts", "outcome.json")
}
if (!exists("outputFolder") || is.null(outputFolder)) {
  outputFolder <- file.path("results", analysisId)
}

# Si les chemins sont relatifs, les baser sur project_root
if (!grepl("^[A-Za-z]:/|^/", targetJsonFile)) {
  targetJsonFile <- file.path(project_root, targetJsonFile)
}
if (!grepl("^[A-Za-z]:/|^/", outcomeJsonFile)) {
  outcomeJsonFile <- file.path(project_root, outcomeJsonFile)
}
if (!grepl("^[A-Za-z]:/|^/", outputFolder)) {
  outputFolder <- file.path(project_root, outputFolder)
}

targetJsonFile  <- normalizePath(targetJsonFile,  winslash = "/", mustWork = FALSE)
outcomeJsonFile <- normalizePath(outcomeJsonFile, winslash = "/", mustWork = FALSE)
outputFolder    <- normalizePath(outputFolder,    winslash = "/", mustWork = FALSE)

# ---------------------------
# Block 2: connections
# ---------------------------
message("==> Creating connectionDetails")

connectionArgs <- list(
  dbms   = dbms,
  server = server
)

if (exists("user")      && !is.null(user))      connectionArgs$user      <- user
if (exists("password")  && !is.null(password))  connectionArgs$password  <- password
if (exists("port")      && !is.null(port))      connectionArgs$port      <- port
if (exists("pathToDriver") && !is.null(pathToDriver)) {
  connectionArgs$pathToDriver <- pathToDriver
}

connectionDetails <- do.call(DatabaseConnector::createConnectionDetails, connectionArgs)

message("==> Connecting through DatabaseConnector")
conn <- DatabaseConnector::connect(connectionDetails)
on.exit({
  try(DatabaseConnector::disconnect(conn), silent = TRUE)
}, add = TRUE)

# ---------------------------
# Block 3: create cohorts from ATLAS JSON
# ---------------------------
message("==> Preparing cohort tables")

cohortTableNames <- CohortGenerator::getCohortTableNames(
  cohortTable = cohortTable
)

CohortGenerator::createCohortTables(
  connectionDetails    = connectionDetails,
  cohortDatabaseSchema = cohortDatabaseSchema,
  cohortTableNames     = cohortTableNames,
  incremental          = incremental
)

message("==> Reading cohort JSON files")

if (!file.exists(targetJsonFile)) {
  stop(paste("Target cohort JSON file not found:", targetJsonFile))
}
if (!file.exists(outcomeJsonFile)) {
  stop(paste("Outcome cohort JSON file not found:", outcomeJsonFile))
}

targetJson  <- paste(readLines(targetJsonFile,  warn = FALSE), collapse = "\n")
outcomeJson <- paste(readLines(outcomeJsonFile, warn = FALSE), collapse = "\n")

if (nchar(trimws(targetJson)) == 0) {
  stop(paste("Target cohort JSON file is empty:", targetJsonFile))
}
if (nchar(trimws(outcomeJson)) == 0) {
  stop(paste("Outcome cohort JSON file is empty:", outcomeJsonFile))
}

message("==> Building cohort SQL from ATLAS JSON")

targetExpression <- CirceR::cohortExpressionFromJson(targetJson)
targetSql <- CirceR::buildCohortQuery(
  targetExpression,
  options = CirceR::createGenerateOptions(generateStats = generateStats)
)

outcomeExpression <- CirceR::cohortExpressionFromJson(outcomeJson)
outcomeSql <- CirceR::buildCohortQuery(
  outcomeExpression,
  options = CirceR::createGenerateOptions(generateStats = generateStats)
)

message("==> Creating cohort definition set")

cohortDefinitionSet <- data.frame(
  cohortId         = c(targetCohortId,  outcomeCohortId),
  cohortName       = c(targetCohortName, outcomeCohortName),
  json             = c(targetJson,      outcomeJson),
  sql              = c(targetSql,      outcomeSql),
  stringsAsFactors = FALSE
)

message("==> Generating cohorts")

invisible(
  CohortGenerator::generateCohortSet(
    connectionDetails    = connectionDetails,
    cdmDatabaseSchema    = cdmDatabaseSchema,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTableNames     = cohortTableNames,
    cohortDefinitionSet  = cohortDefinitionSet
  )
)

# ---------------------------
# Block 3 bis: precheck on generated cohorts
# ---------------------------
message("==> Running precheck on generated cohorts")

precheckCounts <- run_precheck(
  connectionDetails   = connectionDetails,
  minTargetSubjects   = 1,
  minOutcomeSubjects  = 1,
  failOnEmpty         = TRUE
)

# ---------------------------
# Block 4: databaseDetails for PLP
# ---------------------------
message("==> Creating databaseDetails for PLP")

databaseDetails <- PatientLevelPrediction::createDatabaseDetails(
  connectionDetails      = connectionDetails,
  cdmDatabaseSchema      = cdmDatabaseSchema,
  cdmDatabaseName        = cdmDatabaseName,
  tempEmulationSchema    = tempEmulationSchema,
  cohortDatabaseSchema   = cohortDatabaseSchema,
  cohortTable            = cohortTable,
  outcomeDatabaseSchema  = outcomeDatabaseSchema,
  outcomeTable           = outcomeTable,
  targetId               = targetCohortId,
  outcomeIds             = outcomeCohortId,
  cdmVersion             = cdmVersion
)

message("==> databaseDetails created")

# ---------------------------
# Block 5: get PLP data
# ---------------------------
message("==> Extracting PLP data")

restrictPlpDataSettings <- PatientLevelPrediction::createRestrictPlpDataSettings(
  sampleSize = sampleSizePlp
)

plpData <- PatientLevelPrediction::getPlpData(
  databaseDetails         = databaseDetails,
  covariateSettings       = covariateSettings,
  restrictPlpDataSettings = restrictPlpDataSettings
)

message("==> PLP data extracted successfully")

# ---------------------------
# Block 6: run PLP
# ---------------------------
message("==> Running PLP")

plpResult <- PatientLevelPrediction::runPlp(
  plpData            = plpData,
  outcomeId          = outcomeCohortId,
  modelSettings      = modelSettings,
  analysisId         = analysisId,
  analysisName       = analysisName,
  populationSettings = populationSettings,
  splitSettings      = splitSettings,
  saveDirectory      = outputFolder
)

message("==> PLP run completed successfully")
message("==> Results saved to: ", outputFolder)
message("==> PLP script finished")