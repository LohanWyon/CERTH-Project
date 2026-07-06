library(shiny)
library(bslib)
library(DT)
library(readr)
library(plotly)
library(CDMConnector)
library(FeatureExtraction)
library(CirceR)
library(dplyr)

source("R/app_helpers.R")
source("R/run_pipeline_shiny.R")

# 1) Construire la même config que Shiny
connection_info <- list(
  connection_mode = "demo",
  dbms = "duckdb",
  source_label = "Eunomia demo database",
  source_path = CDMConnector::eunomiaDir(datasetName = "synpuf-110k"),
  server = NA_character_,
  port = NA_character_,
  user = NA_character_,
  password = NA_character_,
  oracle_temp_schema = NA_character_
)

fake_input <- list(
  generate_cohorts_from_json = TRUE,
  cohort_json_folder = "cohorts_json",
  target_json_choice = "target_test.json",
  comparator_json_choice = "comparator_test.json",
  outcome_json_choice = "outcome_test.json",
  output_folder = "",
  cdm_database_schema = "main",
  cohort_database_schema = "main",
  cohort_table = "cohort",
  study_start_date = "",
  study_end_date = "",
  outcome_cohort_ids = "",

  screening_enabled = TRUE,
  screening_number_of_runs = 3,
  screening_top_covariates_per_run = 300,
  screening_min_subjects_per_group = 500,

  matching_caliper = 0.2,
  matching_allow_caliper_adaptation = TRUE,
  matching_low_match_rate_threshold = 0.25,
  matching_caliper_if_low_match_rate = 0.25,
  matching_high_match_rate_threshold = 0.90,
  matching_poor_balance_threshold = 0.10,
  matching_caliper_if_poor_balance = 0.15,

  trimming_enabled = TRUE,
  trimming_lower_percentile = 0.02,
  trimming_upper_percentile = 0.98,

  outcome_prior_variance = 2,
  outcome_use_cross_validation = FALSE,

  save_dev_files = FALSE,
  save_debug_files = FALSE,

  use_demo_connection = TRUE
)

cfg <- build_config_from_input(
  input = fake_input,
  connection_info = connection_info
)

# 2) Lancer le pipeline en direct, sans tryCatch
run_primary_ple_pipeline(cfg)