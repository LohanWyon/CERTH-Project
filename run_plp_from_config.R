# run_plp_from_config.R
# Generic PLP script using external config files and ATLAS JSON cohort definitions

# ---------------------------
# Block 0: packages
# ---------------------------
library(CDMConnector)
library(DatabaseConnector)
library(PatientLevelPrediction)
library(CohortGenerator)
library(CirceR)
library(duckdb)
library(DBI)
library(dplyr)
library(FeatureExtraction)

options(scipen = 999)

# ---------------------------
# Block 1: load config files
# ---------------------------
source("config/config_connection.R")
source("config/config_cohorts.R")
source("config/config_covariates.R")
source("config/config_model.R")
source("config/config_runtime.R")

if (!dir.exists(outputFolder)) {
  dir.create(outputFolder, recursive = TRUE)
}

# ---------------------------
# Block 2: connections
# ---------------------------
message("==> Creating connectionDetails")

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms   = dbms,
  server = server
)

message("==> Connecting with DBI")
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = server)

message("==> Creating CDM reference object")
cdm <- CDMConnector::cdmFromCon(
  con         = con,
  cdmSchema   = cdmDatabaseSchema,
  writeSchema = cdmDatabaseSchema,
  cdmName     = cdmDatabaseName,
  cdmVersion  = as.character(cdmVersion)
)

nPerson <- DBI::dbGetQuery(
  con,
  paste0("SELECT COUNT(*) AS n_person FROM ", cdmDatabaseSchema, ".person")
)
message("==> Number of persons in CDM: ", nPerson$n_person[1])

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

targetJson  <- paste(readLines(targetJsonFile, warn = FALSE),  collapse = "\n")
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
  cohortId   = c(targetCohortId, outcomeCohortId),
  cohortName = c(targetCohortName, outcomeCohortName),
  json       = c(targetJson, outcomeJson),
  sql        = c(targetSql, outcomeSql),
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

cohortCounts <- DBI::dbGetQuery(
  con,
  paste0(
    "SELECT cohort_definition_id, COUNT(*) AS n ",
    "FROM ", cohortDatabaseSchema, ".", cohortTable, " ",
    "GROUP BY cohort_definition_id"
  )
)
message("==> Cohort counts:")
print(cohortCounts)

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
  cohortId               = targetCohortId,
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