# R/app_helpers.R

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}

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

ensure_json_extension <- function(file_name) {
  if (is.null(file_name) || length(file_name) == 0 || is.na(file_name)) {
    stop("file_name is NULL or empty")
  }
  if (!grepl("\\.json$", file_name, ignore.case = TRUE)) {
    file_name <- paste0(file_name, ".json")
  }
  file_name
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

deduplicate_covariate_catalog <- function(x) {
  if (is.null(x) || !is.data.frame(x) || nrow(x) == 0) {
    return(data.frame(
      covariateId = numeric(0),
      covariateName = character(0),
      analysisId = numeric(0),
      conceptId = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  keep_cols <- intersect(
    c("covariateId", "covariateName", "analysisId", "conceptId"),
    names(x)
  )

  x <- x[, keep_cols, drop = FALSE]

  if (!("covariateId" %in% names(x))) {
    x$covariateId <- NA_real_
  }

  if (!("covariateName" %in% names(x))) {
    x$covariateName <- NA_character_
  }

  if (!("analysisId" %in% names(x))) {
    x$analysisId <- NA_real_
  }

  if (!("conceptId" %in% names(x))) {
    x$conceptId <- NA_real_
  }

  x$covariateId <- suppressWarnings(as.numeric(x$covariateId))
  x$analysisId <- suppressWarnings(as.numeric(x$analysisId))
  x$conceptId <- suppressWarnings(as.numeric(x$conceptId))
  x$covariateName <- as.character(x$covariateName)

  x <- x[!is.na(x$covariateId), , drop = FALSE]
  x <- x[order(x$covariateName, x$covariateId), , drop = FALSE]
  x <- x[!duplicated(x$covariateId), , drop = FALSE]
  rownames(x) <- NULL
  x
}

build_covariate_choice_labels <- function(catalog_df) {
  if (is.null(catalog_df) || !is.data.frame(catalog_df) || nrow(catalog_df) == 0) {
    return(setNames(character(0), character(0)))
  }

  labels <- character(nrow(catalog_df))
  ids <- character(nrow(catalog_df))

  for (i in seq_len(nrow(catalog_df))) {
    cov_name <- catalog_df$covariateName[i]
    cov_id <- catalog_df$covariateId[i]
    concept_id <- catalog_df$conceptId[i]

    if (is.na(cov_name) || !nzchar(cov_name)) {
      cov_name <- paste0("Covariate ", cov_id)
    }

    if (is.na(concept_id)) {
      concept_str <- "NA"
    } else {
      concept_str <- as.character(concept_id)
    }

    labels[i] <- paste0(
      cov_name,
      " [covariateId: ", cov_id,
      ", conceptId: ", concept_str, "]"
    )
    ids[i] <- as.character(cov_id)
  }

  all_labels <- c("", labels)
  all_ids <- c("", ids)
  
  stats::setNames(all_ids, all_labels)
}

find_covariate_catalog_row <- function(catalog_df, covariate_id) {
  if (is.null(catalog_df) || !is.data.frame(catalog_df) || nrow(catalog_df) == 0) {
    return(NULL)
  }

  covariate_id <- suppressWarnings(as.numeric(covariate_id))
  if (is.na(covariate_id)) {
    return(NULL)
  }

  hits <- catalog_df[catalog_df$covariateId == covariate_id, , drop = FALSE]
  if (nrow(hits) == 0) {
    return(NULL)
  }

  hits[1, , drop = FALSE]
}

expand_covariate_with_subcovariates <- function(catalog_df, selected_covariate_id) {
  selected_row <- find_covariate_catalog_row(catalog_df, selected_covariate_id)

  if (is.null(selected_row)) {
    return(numeric(0))
  }

  analysis_id <- suppressWarnings(as.numeric(selected_row$analysisId[[1]]))
  concept_id <- suppressWarnings(as.numeric(selected_row$conceptId[[1]]))

  if (!is.na(analysis_id) &&
      !is.na(concept_id) &&
      "analysisId" %in% names(catalog_df) &&
      "conceptId" %in% names(catalog_df)) {
    matched_ids <- catalog_df$covariateId[
      catalog_df$analysisId == analysis_id &
        catalog_df$conceptId == concept_id
    ]
    matched_ids <- unique(as.numeric(matched_ids))
    matched_ids <- matched_ids[!is.na(matched_ids)]

    if (length(matched_ids) > 0) {
      return(sort(matched_ids))
    }
  }

  cov_id <- suppressWarnings(as.numeric(selected_row$covariateId[[1]]))
  if (is.na(cov_id)) {
    return(numeric(0))
  }
  cov_id
}

expand_covariates_from_concept_id <- function(catalog_df, selected_covariate_id) {
  selected_row <- find_covariate_catalog_row(catalog_df, selected_covariate_id)

  if (is.null(selected_row)) {
    return(numeric(0))
  }

  concept_id <- suppressWarnings(as.numeric(selected_row$conceptId[[1]]))

  if (is.na(concept_id) || !("conceptId" %in% names(catalog_df))) {
    cov_id <- suppressWarnings(as.numeric(selected_row$covariateId[[1]]))
    if (is.na(cov_id)) {
      return(numeric(0))
    }
    return(cov_id)
  }

  matched_ids <- catalog_df$covariateId[!is.na(catalog_df$conceptId) & catalog_df$conceptId == concept_id]
  matched_ids <- unique(as.numeric(matched_ids))
  matched_ids <- matched_ids[!is.na(matched_ids)]

  if (length(matched_ids) == 0) {
    cov_id <- suppressWarnings(as.numeric(selected_row$covariateId[[1]]))
    if (is.na(cov_id)) {
      return(numeric(0))
    }
    return(cov_id)
  }

  sort(matched_ids)
}

expand_covariates_from_descendant_concepts <- function(catalog_df, selected_covariate_id, descendant_concept_ids) {
  if (is.null(catalog_df) || nrow(catalog_df) == 0) {
    return(numeric(0))
  }

  if (is.null(descendant_concept_ids) || length(descendant_concept_ids) == 0) {
    return(numeric(0))
  }

  matching_ids <- catalog_df$covariateId[!is.na(catalog_df$conceptId) & catalog_df$conceptId %in% descendant_concept_ids]
  matching_ids <- unique(as.numeric(matching_ids))
  matching_ids <- matching_ids[!is.na(matching_ids)]

  if (length(matching_ids) == 0) {
    cov_id <- suppressWarnings(as.numeric(selected_covariate_id))
    if (is.na(cov_id)) {
      return(numeric(0))
    }
    return(cov_id)
  }

  sort(matching_ids)
}

build_selected_covariates_table <- function(selected_ids, catalog_df) {
  selected_ids <- unique(suppressWarnings(as.numeric(selected_ids)))
  selected_ids <- selected_ids[!is.na(selected_ids)]

  if (length(selected_ids) == 0) {
    return(data.frame(
      covariateId = numeric(0),
      covariateName = character(0),
      analysisId = numeric(0),
      conceptId = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- catalog_df[catalog_df$covariateId %in% selected_ids, , drop = FALSE]

  missing_ids <- setdiff(selected_ids, out$covariateId)
  if (length(missing_ids) > 0) {
    out <- rbind(
      out,
      data.frame(
        covariateId = missing_ids,
        covariateName = paste0("Covariate ", missing_ids),
        analysisId = NA_real_,
        conceptId = NA_real_,
        stringsAsFactors = FALSE
      )
    )
  }

  out <- out[match(selected_ids, out$covariateId), , drop = FALSE]
  rownames(out) <- NULL
  out
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
    washout_period = 365,
    remove_subjects_with_prior_outcome = TRUE,
    prior_outcome_lookback = 365,
    require_time_at_risk = TRUE,
    min_time_at_risk = 1,
    risk_window_start = 1,
    start_anchor = "cohort start",
    risk_window_end = 365,
    end_anchor = "cohort start",
    remove_duplicate_subjects = "keep first, truncate to second",
    restrict_to_common_period = TRUE
  )
}

build_covariate_screening_config <- function(input,
                                            forced_covariate_ids = numeric(0),
                                            excluded_covariate_ids = numeric(0)) {
  forced_covariate_ids <- unique(suppressWarnings(as.numeric(forced_covariate_ids)))
  forced_covariate_ids <- forced_covariate_ids[!is.na(forced_covariate_ids)]

  excluded_covariate_ids <- unique(suppressWarnings(as.numeric(excluded_covariate_ids)))
  excluded_covariate_ids <- excluded_covariate_ids[!is.na(excluded_covariate_ids)]

  list(
    enabled = isTRUE(input$screening_enabled),
    number_of_runs = as.integer(input$screening_number_of_runs %||% 3),
    sample_fraction = 0.05,
    min_subjects_per_group = as.integer(input$screening_min_subjects_per_group %||% 500),
    top_covariates_per_run = as.integer(input$screening_top_covariates_per_run %||% 500),
    seed = 20260619,
    include_forced_covariates = length(forced_covariate_ids) > 0,
    forced_covariate_ids = forced_covariate_ids,
    exclude_artefactual_covariates = length(excluded_covariate_ids) > 0,
    excluded_covariate_ids = excluded_covariate_ids,
    auto_exclude_high_correlation_covariates = TRUE,
    high_correlation_threshold = 0.95,
    max_abs_screening_coefficient = 3
  )
}

build_ps_model_config <- function() {
  list(
    model_type = "lasso_logistic",
    max_cohort_size_for_fitting = 250000,
    use_cross_validation = TRUE,
    prior_type = "laplace",
    prior_variance = 1
  )
}

build_adjustment_config <- function(input) {
  if (isTRUE(input$auto_caliper_search)) {
    return(list(
      method = "matching",
      match_ratio = 1,
      caliper = 0.2,
      caliper_scale = "sd_logit_ps",
      allow_caliper_adaptation = FALSE,
      use_trimming = isTRUE(input$trimming_enabled),
      trimming_rule = "common_support_percentile",
      trimming_lower_percentile = as.numeric(input$trimming_lower_percentile %||% 0.01),
      trimming_upper_percentile = as.numeric(input$trimming_upper_percentile %||% 0.99),
      trim_only_if_clear_non_overlap = TRUE,
      auto_caliper_search = TRUE,
      target_match_rate = as.numeric(input$target_match_rate %||% 0.65),
      target_match_rate_tolerance = as.numeric(input$target_match_rate_tolerance %||% 0.15)
    ))
  }
  
  list(
    method = "matching",
    match_ratio = 1,
    caliper = as.numeric(input$matching_caliper %||% 0.2),
    caliper_scale = "sd_logit_ps",
    allow_caliper_adaptation = isTRUE(input$matching_allow_caliper_adaptation),
    caliper_if_low_match_rate = as.numeric(input$matching_caliper_if_low_match_rate %||% 0.25),
    low_match_rate_threshold = as.numeric(input$matching_low_match_rate_threshold %||% 0.25),
    caliper_if_poor_balance = as.numeric(input$matching_caliper_if_poor_balance %||% 0.15),
    high_match_rate_threshold = as.numeric(input$matching_high_match_rate_threshold %||% 0.90),
    poor_balance_threshold = as.numeric(input$matching_poor_balance_threshold %||% 0.10),
    use_trimming = isTRUE(input$trimming_enabled),
    trimming_rule = "common_support_percentile",
    trimming_lower_percentile = as.numeric(input$trimming_lower_percentile %||% 0.01),
    trimming_upper_percentile = as.numeric(input$trimming_upper_percentile %||% 0.99),
    trim_only_if_clear_non_overlap = TRUE,
    auto_caliper_search = FALSE,
    target_match_rate = NULL,
    target_match_rate_tolerance = NULL
  )
}

build_outcome_model_config <- function(input) {
  list(
    model_type = "cox",
    stratified = TRUE,
    include_covariates = FALSE,
    estimand = "att",
    prior_variance = as.numeric(input$outcome_prior_variance %||% 2),
    use_cross_validation = isTRUE(input$outcome_use_cross_validation)
  )
}

build_runtime_config <- function(input) {
  output_folder <- normalize_optional_text(input$output_folder)

  if (is.null(output_folder)) {
    output_folder <- file.path("output", "ple_analysis")
  }

  list(
    output_folder = output_folder,
    final_output_folder = output_folder,
    dev_output_folder = file.path(output_folder, "dev"),
    debug_output_folder = file.path(output_folder, "debug"),
    save_final_results = TRUE,
    save_dev_files = isTRUE(input$save_dev_files),
    save_debug_files = isTRUE(input$save_debug_files),
    verbose = TRUE
  )
}

build_config_from_input <- function(input,
                                    connection_info,
                                    forced_covariate_ids = numeric(0),
                                    excluded_covariate_ids = numeric(0)) {
  list(
    connection = build_connection_config(connection_info),
    cohorts = build_cohorts_config(input, connection_info),
    cm_data = build_cm_data_config(input, connection_info),
    study_population = build_study_population_config(),
    covariate_screening = build_covariate_screening_config(
      input = input,
      forced_covariate_ids = forced_covariate_ids,
      excluded_covariate_ids = excluded_covariate_ids
    ),
    ps_model = build_ps_model_config(),
    adjustment = build_adjustment_config(input),
    outcome_model = build_outcome_model_config(input),
    output = build_runtime_config(input)
  )
}

get_descendant_concept_ids <- function(connection, cdm_database_schema, concept_id, include_self = FALSE) {
  if (is.na(concept_id) || is.null(concept_id) || concept_id == 0) {
    return(numeric(0))
  }

  if (include_self) {
    query <- sprintf(
      "SELECT DISTINCT descendant_concept_id FROM %s.concept_ancestor WHERE ancestor_concept_id = %d",
      cdm_database_schema,
      as.numeric(concept_id)
    )
  } else {
    query <- sprintf(
      "SELECT DISTINCT descendant_concept_id FROM %s.concept_ancestor WHERE ancestor_concept_id = %d AND min_levels_of_separation > 0",
      cdm_database_schema,
      as.numeric(concept_id)
    )
  }

  result <- DatabaseConnector::querySql(connection, query)
  unique(as.numeric(result[[1]]))
}

get_concept_ancestors <- function(connection, concept_id, cdm_schema = "main") {
  if (is.na(concept_id) || is.null(concept_id) || concept_id == 0) {
    return(data.frame(
      ancestor_concept_id = numeric(0),
      min_levels_of_separation = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  
  query <- sprintf(
    "SELECT ca.ancestor_concept_id, ca.min_levels_of_separation
     FROM %s.concept_ancestor ca
     WHERE ca.descendant_concept_id = %d
       AND ca.min_levels_of_separation > 0
     ORDER BY ca.min_levels_of_separation ASC, ca.ancestor_concept_id ASC",
    cdm_schema, as.numeric(concept_id)
  )
  
  DatabaseConnector::querySql(connection, query)
}

get_all_descendants_of_ancestor <- function(connection, ancestor_concept_id, cdm_schema = "main") {
  if (is.na(ancestor_concept_id) || is.null(ancestor_concept_id) || ancestor_concept_id == 0) {
    return(numeric(0))
  }
  
  query <- sprintf(
    "SELECT DISTINCT descendant_concept_id
     FROM %s.concept_ancestor
     WHERE ancestor_concept_id = %d",
    cdm_schema, as.numeric(ancestor_concept_id)
  )
  
  descendants <- DatabaseConnector::querySql(connection, query)
  unique(descendants$descendant_concept_id)
}

get_ancestor_names_from_catalog <- function(catalog_df, ancestor_ids) {
  if (is.null(catalog_df) || nrow(catalog_df) == 0 || is.null(ancestor_ids) || length(ancestor_ids) == 0) {
    return(data.frame(
      ancestor_concept_id = ancestor_ids,
      ancestor_concept_name = as.character(ancestor_ids),
      stringsAsFactors = FALSE
    ))
  }
  
  ancestor_ids <- unique(as.numeric(ancestor_ids))
  ancestor_ids <- ancestor_ids[!is.na(ancestor_ids)]
  
  result <- data.frame(
    ancestor_concept_id = ancestor_ids,
    ancestor_concept_name = as.character(ancestor_ids),
    stringsAsFactors = FALSE
  )
  
  for (i in seq_len(nrow(result))) {
    cid <- result$ancestor_concept_id[i]
    matches <- catalog_df[catalog_df$conceptId == cid, , drop = FALSE]
    
    if (nrow(matches) > 0) {
      name <- matches$covariateName[1]
      if (!is.na(name) && nzchar(trimws(name))) {
        result$ancestor_concept_name[i] <- trimws(name)
      }
    }
  }
  
  result
}