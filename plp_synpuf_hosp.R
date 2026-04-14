# plp_synpuf_hosp.R
# Full PLP script on SynPUF 1k (DuckDB) with separate configuration


# ---------------------------
# Block 0: packages & config
# ---------------------------
library(CDMConnector)
library(DatabaseConnector)
library(PatientLevelPrediction)
library(duckdb)
library(DBI)
library(dplyr)
library(FeatureExtraction)

options(scipen = 999)

# Load configuration
source("config_plp_synpuf.R")

# Create output folder if needed
if (!dir.exists(outputFolder)) dir.create(outputFolder, recursive = TRUE)


# ------------------------------------------------
# Block 1: DuckDB connection + SynPUF 1k OMOP CDM
# ------------------------------------------------
message("==> Connecting to SynPUF 1k via CDMConnector + DuckDB")

# DuckDB folder for synpuf-1k
synpuf_dir <- CDMConnector::eunomiaDir(synpuf_name)

# DuckDB connection
con_duck <- DBI::dbConnect(duckdb::duckdb(), dbdir = synpuf_dir)

# CDM object (optional but handy for checks)
cdm <- CDMConnector::cdmFromCon(
  con         = con_duck,
  cdmSchema   = cdmDatabaseSchema,
  writeSchema = cdmDatabaseSchema,
  cdmName     = cdmDatabaseName,
  cdmVersion  = "5.3"
)

# Quick checks
print(DBI::dbListTables(con_duck))
print(DBI::dbGetQuery(con_duck, "
  SELECT COUNT(*) AS n_person
  FROM main.person
"))


# --------------------------------------------
# Block 2: create the cohort table in DuckDB
# --------------------------------------------
message("==> Creating / updating main.cohort")

# Drop cohort table if it already exists
if ("cohort" %in% DBI::dbListTables(con_duck)) {
  DBI::dbRemoveTable(con_duck, "cohort")
}

# Target cohort: all patients, index date = observation period start
sql_target <- "
CREATE TABLE main.cohort AS
SELECT
  1 AS cohort_definition_id,
  op.person_id AS subject_id,
  op.observation_period_start_date AS cohort_start_date,
  op.observation_period_end_date   AS cohort_end_date
FROM main.observation_period op
"

DBI::dbExecute(con_duck, sql_target)

# Outcome cohort: patients with at least one condition_occurrence
sql_outcome <- "
INSERT INTO main.cohort
SELECT
  2 AS cohort_definition_id,
  co.person_id AS subject_id,
  MIN(co.condition_start_date) AS cohort_start_date,
  MIN(co.condition_end_date)   AS cohort_end_date
FROM main.condition_occurrence co
GROUP BY co.person_id
"

DBI::dbExecute(con_duck, sql_outcome)

# Check cohort table
print(DBI::dbGetQuery(con_duck, "
  SELECT cohort_definition_id, COUNT(*) AS n
  FROM main.cohort
  GROUP BY cohort_definition_id
"))
print(DBI::dbGetQuery(con_duck, "SELECT * FROM main.cohort LIMIT 5"))


# -------------------------------------------------
# Block 3: connectionDetails via DatabaseConnector
# -------------------------------------------------
message("==> Creating connectionDetails (DuckDB)")

connectionDetails <- DatabaseConnector::createConnectionDetails(
  dbms   = dbms,
  server = synpuf_dir
  # user, password, port not needed for local DuckDB
)

print(connectionDetails)


# ---------------------------------------
# Block 4: databaseDetails for PLP
# ---------------------------------------
message("==> Creating databaseDetails for PLP")

databaseDetails <- PatientLevelPrediction::createDatabaseDetails(
  connectionDetails      = connectionDetails,
  cdmDatabaseSchema      = cdmDatabaseSchema,
  cdmDatabaseName        = cdmDatabaseName,
  tempEmulationSchema    = cdmDatabaseSchema,
  cohortDatabaseSchema   = cohortDatabaseSchema,
  cohortTable            = cohortTable,
  outcomeDatabaseSchema  = outcomeDatabaseSchema,
  outcomeTable           = outcomeTable,
  cohortId               = targetCohortId,
  outcomeIds             = outcomeCohortId,
  cdmVersion             = 5
)

str(databaseDetails)


# -----------------------------
# Block 5: getPlpData
# -----------------------------
message("==> Extracting PLP data (getPlpData)")

covSettings <- FeatureExtraction::createCovariateSettings(
  useDemographicsGender              = TRUE,
  useDemographicsAge                 = TRUE,
  useDemographicsAgeGroup            = TRUE,
  useConditionOccurrenceAnyTimePrior = TRUE,
  useDrugExposureAnyTimePrior        = TRUE
)

restrictSettings <- PatientLevelPrediction::createRestrictPlpDataSettings(
  sampleSize = sampleSizePlp
)

plpData <- PatientLevelPrediction::getPlpData(
  databaseDetails         = databaseDetails,
  covariateSettings       = covSettings,
  restrictPlpDataSettings = restrictSettings
)

print(plpData)


# -----------------------------
# Block 6: PLP model & settings
# -----------------------------
message("==> Setting up PLP model (LASSO logistic regression)")

modelSettings <- PatientLevelPrediction::setLassoLogisticRegression()

populationSettings <- PatientLevelPrediction::createStudyPopulationSettings(
  firstExposureOnly              = FALSE,
  washoutPeriod                  = 0,
  removeSubjectsWithPriorOutcome = TRUE,
  priorOutcomeLookback           = 9999,
  riskWindowStart                = 1,
  riskWindowEnd                  = 365
)

splitSettings <- PatientLevelPrediction::createDefaultSplitSetting(
  testFraction = 0.25
)


# -----------------------------
# Block 7: runPlp
# -----------------------------
message("==> Running runPlp")

plpResult <- PatientLevelPrediction::runPlp(
  plpData            = plpData,
  outcomeId          = outcomeCohortId,
  modelSettings      = modelSettings,
  analysisId         = "SynPUF_duckdb_glm",
  analysisName       = "GLM on SynPUF DuckDB",
  populationSettings = populationSettings,
  splitSettings      = splitSettings,
  saveDirectory      = outputFolder
)

print(plpResult)

# End of script
message("==> PLP script finished")