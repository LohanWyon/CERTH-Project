# run_ple_from_config.R

source("setup_java.R")
setup_java()

library(DatabaseConnector)
library(SqlRender)
library(CohortGenerator)
library(CirceR)
library(FeatureExtraction)
library(CohortMethod)
library(readr)

source("R/utils.R")
source("R/cohort_generation.R")
source("R/run_single_cm_analysis.R")
source("R/export_results.R")

source("config/config_connection.R")
source("config/config_cohorts.R")
source("config/config_cm_data.R")
source("config/config_study_population.R")
source("config/config_analysis.R")
source("config/config_runtime.R")

check_required_packages()
ensure_dir(runtimeConfig$outputFolder)

connectionDetails <- create_connection_details(connectionConfig)

generate_cohorts_if_requested(
  connectionDetails = connectionDetails,
  cohortsConfig = cohortsConfig,
  cmDataConfig = cmDataConfig,
  runtimeConfig = runtimeConfig
)

cmData <- build_cm_data(
  connectionDetails = connectionDetails,
  cohortsConfig = cohortsConfig,
  cmDataConfig = cmDataConfig,
  studyPopulationConfig = studyPopulationConfig,
  runtimeConfig = runtimeConfig
)

studyPopulation <- build_study_population(
  cmData = cmData,
  cohortsConfig = cohortsConfig,
  studyPopulationConfig = studyPopulationConfig,
  runtimeConfig = runtimeConfig
)

ps <- fit_ps_model(
  population = studyPopulation,
  cmData = cmData, 
  analysisConfig = analysisConfig,
  runtimeConfig = runtimeConfig
)
adjustedPopulation <- apply_adjustment(
  ps = ps,
  analysisConfig = analysisConfig,
  runtimeConfig = runtimeConfig
)

outcomeModel <- fit_outcome(
  adjustedPopulation = adjustedPopulation,
  cmData = cmData,
  analysisConfig = analysisConfig,
  runtimeConfig = runtimeConfig
)

export_results(
  outputFolder = runtimeConfig$outputFolder,
  outcomeModel = outcomeModel,
  ps = ps,
  adjustedPopulation = adjustedPopulation,
  runtimeConfig = runtimeConfig
)

message("PLE v1 completed successfully.")
message("Results written to: ", normalizePath(runtimeConfig$outputFolder, winslash = "/", mustWork = FALSE))