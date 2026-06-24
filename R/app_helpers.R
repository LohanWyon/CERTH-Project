# R/app_helpers.R
# Purpose: Build and normalize app configuration inputs for the PLE pipeline.
# Notes:
# - Handles input normalization, cohort JSON management, and runtime config assembly.
# - Keeps Shiny-side config building separate from pipeline execution logic.

parse_csv_ids <- function(x) {
  x <- trimws(unlist(strsplit(as.character(x), ",")))
  x <- x[nzchar(x)]
  if (length(x) == 0) {
    return(numeric(0))
  }
  suppressWarnings(as.numeric(x))
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

normalize_optional_text <- function(x) {
  x <- null_if_empty(x)
  if (is.null(x)) {
    return(NULL)
  }
  trimws(as.character(x))
}

normalize_ohdsi_date <- function(x, default = NULL) {
  x <- null_if_empty(x)

  if (is.null(x)) {
    return(default)
  }

  x_chr <- trimws(as.character(x))

  if (!nzchar(x_chr)) {
    return(default)
  }

  parsed <- as.Date(x_chr)

  if (is.na(parsed)) {
    stop("Invalid date provided. Expected format: YYYY-MM-DD.")
  }

  format(parsed, "%Y%m%d")
}

normalize_file_stem <- function(x) {
  x <- trimws(tolower(as.character(x)))
  x <- gsub("[[:space:]]+", "_", x)
  x <- gsub("[^a-z0-9_\\-]", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  x
}

ensure_json_extension <- function(x) {
  if (!grepl("\\.json$", x, ignore.case = TRUE)) {
    paste0(x, ".json")
  } else {
    x
  }
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

list_available_cohort_json_files <- function(folder) {
  ensure_dir(folder)

  files <- list.files(
    path = folder,
    pattern = "\\.json$",
    full.names = FALSE
  )

  files <- sort(files, na.last = TRUE)

  c(
    "Select an existing cohort JSON" = "",
    "Import a new cohort JSON" = "__new__",
    stats::setNames(files, files)
  )
}

save_cohort_json_file <- function(folder, file_name, json_text, overwrite = FALSE) {
  ensure_dir(folder)

  file_name <- normalize_file_stem(file_name)
  if (!nzchar(file_name)) {
    stop("A cohort JSON file name is required.")
  }

  file_name <- ensure_json_extension(file_name)
  json_text <- normalize_optional_text(json_text)

  if (is.null(json_text)) {
    stop("Cohort JSON content is empty.")
  }

  file_path <- file.path(folder, file_name)

  if (file.exists(file_path) && !isTRUE(overwrite)) {
    stop("A cohort JSON file with this name already exists: ", file_name)
  }

  writeLines(json_text, file_path, useBytes = TRUE)
  invisible(file_path)
}

resolve_existing_cohort_json_selection <- function(choice, folder) {
  choice <- normalize_optional_text(choice)

  if (is.null(choice) || identical(choice, "__new__")) {
    return(NULL)
  }

  file_path <- file.path(folder, choice)

  if (!file.exists(file_path)) {
    stop("Selected cohort JSON file does not exist: ", choice)
  }

  file_path
}

default_auto_cohort_ids <- function() {
  list(
    target_cohort_id = 1,
    comparator_cohort_id = 2,
    primary_outcome_cohort_id = 3
  )
}

build_connection_config <- function(connection_info) {
  if (identical(connection_info$connection_mode, "demo")) {
    return(list(
      connection_mode = "demo",
      dbms = connection_info$dbms,
      server = connection_info$source_path,
      user = NULL,
      password = NULL,
      port = NULL,
      path_to_driver = NULL,
      oracle_temp_schema = NULL
    ))
  }

  list(
    connection_mode = "manual",
    dbms = connection_info$dbms,
    server = connection_info$server,
    user = connection_info$user,
    password = connection_info$password,
    port = connection_info$port,
    path_to_driver = NULL,
    oracle_temp_schema = connection_info$oracle_temp_schema
  )
}

build_technical_schema_config <- function(input, connection_info) {
  if (identical(connection_info$connection_mode, "demo")) {
    return(list(
      cdm_database_schema = "main",
      cohort_database_schema = "main",
      cohort_table = "cohort"
    ))
  }

  cdm_database_schema <- normalize_optional_text(input$cdm_database_schema)
  cohort_database_schema <- normalize_optional_text(input$cohort_database_schema)
  cohort_table <- normalize_optional_text(input$cohort_table)

  if (is.null(cdm_database_schema)) {
    stop("CDM database schema is required for a manual connection.")
  }

  if (is.null(cohort_database_schema)) {
    stop("Cohort database schema is required for a manual connection.")
  }

  if (is.null(cohort_table)) {
    stop("Cohort table is required for a manual connection.")
  }

  list(
    cdm_database_schema = cdm_database_schema,
    cohort_database_schema = cohort_database_schema,
    cohort_table = cohort_table
  )
}

build_cohorts_config <- function(input, connection_info) {
  cohort_json_folder <- normalize_optional_text(input$cohort_json_folder)
  if (is.null(cohort_json_folder)) {
    cohort_json_folder <- "cohorts_json"
  }

  ensure_dir(cohort_json_folder)

  tech_cfg <- build_technical_schema_config(input, connection_info)
  auto_ids <- default_auto_cohort_ids()

  additional_outcome_ids <- parse_csv_ids(input$outcome_cohort_ids)
  additional_outcome_ids <- additional_outcome_ids[!is.na(additional_outcome_ids)]

  list(
    cohort_database_schema = tech_cfg$cohort_database_schema,
    cohort_table = tech_cfg$cohort_table,
    generate_cohorts_from_json = isTRUE(input$generate_cohorts_from_json),
    cohort_json_folder = cohort_json_folder,
    target_cohort_id = auto_ids$target_cohort_id,
    comparator_cohort_id = auto_ids$comparator_cohort_id,
    primary_outcome_cohort_id = auto_ids$primary_outcome_cohort_id,
    outcome_cohort_ids = unique(c(auto_ids$primary_outcome_cohort_id, additional_outcome_ids)),
    target_json_file = resolve_existing_cohort_json_selection(
      choice = input$target_json_choice,
      folder = cohort_json_folder
    ),
    comparator_json_file = resolve_existing_cohort_json_selection(
      choice = input$comparator_json_choice,
      folder = cohort_json_folder
    ),
    primary_outcome_json_file = resolve_existing_cohort_json_selection(
      choice = input$outcome_json_choice,
      folder = cohort_json_folder
    )
  )
}

build_cm_data_config <- function(input, connection_info) {
  tech_cfg <- build_technical_schema_config(input, connection_info)

  list(
    cdm_database_schema = tech_cfg$cdm_database_schema,
    study_start_date = normalize_ohdsi_date(
      x = input$study_start_date,
      default = "19000101"
    ),
    study_end_date = normalize_ohdsi_date(
      x = input$study_end_date,
      default = "20991231"
    ),
    covariate_settings = FeatureExtraction::createDefaultCovariateSettings()
  )
}

build_study_population_config <- function() {
  list(
    first_exposure_only = TRUE,
    washout_period = 0,
    remove_subjects_with_prior_outcome = FALSE,
    prior_outcome_lookback = 0,
    require_time_at_risk = TRUE,
    min_time_at_risk = 1,
    risk_window_start = 1,
    start_anchor = "cohort start",
    risk_window_end = 365,
    end_anchor = "cohort start",
    remove_duplicate_subjects = "keep first",
    restrict_to_common_period = FALSE
  )
}

build_covariate_screening_config <- function() {
  list(
    enabled = TRUE,
    number_of_runs = 5,
    sample_fraction = 0.05,
    min_subjects_per_group = 500,
    top_covariates_per_run = 1000,
    seed = 20260619,
    include_forced_covariates = FALSE,
    forced_covariates_source = NULL,
    exclude_artefactual_covariates = FALSE,
    excluded_covariates_source = NULL,
    auto_exclude_high_correlation_covariates = TRUE,
    high_correlation_threshold = 0.999
  )
}

build_ps_model_config <- function() {
  list(
    model_type = "lasso_logistic",
    max_cohort_size_for_fitting = 250000,
    use_cross_validation = TRUE,
    prior_type = "laplace",
    prior_variance = 0.01
  )
}

build_adjustment_config <- function() {
  list(
    method = "matching",
    match_ratio = 1,
    caliper = 0.2,
    caliper_scale = "sd_logit_ps",
    allow_caliper_adaptation = TRUE,
    caliper_if_low_match_rate = 0.25,
    low_match_rate_threshold = 0.25,
    caliper_if_poor_balance = 0.15,
    high_match_rate_threshold = 0.90,
    poor_balance_threshold = 0.10,
    use_trimming = FALSE,
    trimming_rule = "common_support_percentile",
    trimming_lower_percentile = 0.01,
    trimming_upper_percentile = 0.99,
    trim_only_if_clear_non_overlap = TRUE
  )
}

build_outcome_model_config <- function() {
  list(
    model_type = "cox",
    stratified = TRUE,
    include_covariates = FALSE,
    estimand = "att"
  )
}

build_runtime_config <- function(input) {
  output_folder <- normalize_optional_text(input$output_folder)

  if (is.null(output_folder)) {
    output_folder <- file.path("output", "ple_analysis")
  }

  list(
    output_folder = output_folder,
    save_intermediate_rds = TRUE,
    verbose = TRUE
  )
}

build_config_from_input <- function(input, connection_info) {
  list(
    connection = build_connection_config(connection_info),
    cohorts = build_cohorts_config(input, connection_info),
    cm_data = build_cm_data_config(input, connection_info),
    study_population = build_study_population_config(),
    covariate_screening = build_covariate_screening_config(),
    ps_model = build_ps_model_config(),
    adjustment = build_adjustment_config(),
    outcome_model = build_outcome_model_config(),
    output = build_runtime_config(input)
  )
}