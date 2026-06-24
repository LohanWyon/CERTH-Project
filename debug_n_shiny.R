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
  source_path = CDMConnector::eunomiaDir(),
  server = NA_character_,
  port = NA_character_,
  user = NA_character_,
  password = NA_character_,
  oracle_temp_schema = NA_character_
)

# Simuler les valeurs d'input que tu as dans l’app
# (tu peux adapter si tu as changé qqch dans l’UI)
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
  outcome_cohort_ids = ""
)

cfg <- build_config_from_input(
  input = fake_input,
  connection_info = connection_info
)

# 2) Lancer le pipeline en direct, sans tryCatch
run_primary_ple_pipeline(cfg)