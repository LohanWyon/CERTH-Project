# R/run_pipeline_shiny.R

required_packages <- c(
  "DatabaseConnector",
  "SqlRender",
  "FeatureExtraction",
  "CohortMethod",
  "Cyclops",
  "CohortGenerator",
  "CirceR",
  "readr",
  "dplyr"
)

check_required_packages <- function(pkgs = required_packages) {
  missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs) > 0) {
    stop("Missing required packages: ", paste(missing_pkgs, collapse = ", "))
  }
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || all(is.na(a))) {
    return(b)
  }
  a
}

write_csv_safe <- function(x, path) {
  if (is.null(x)) {
    return(invisible(NULL))
  }
  ensure_dir(dirname(path))
  readr::write_csv(x, path)
  invisible(path)
}

save_rds_safe <- function(x, path) {
  if (is.null(x)) {
    return(invisible(NULL))
  }
  ensure_dir(dirname(path))
  saveRDS(x, path)
  invisible(path)
}

get_output_paths <- function(output_config) {
  final_dir <- output_config$final_output_folder %||% output_config$output_folder
  dev_dir <- output_config$dev_output_folder %||% file.path(final_dir, "dev")
  debug_dir <- output_config$debug_output_folder %||% file.path(final_dir, "debug")

  ensure_dir(final_dir)

  if (isTRUE(output_config$save_dev_files)) {
    ensure_dir(dev_dir)
  }

  if (isTRUE(output_config$save_debug_files)) {
    ensure_dir(debug_dir)
  }

  list(
    final = final_dir,
    dev = dev_dir,
    debug = debug_dir
  )
}

read_json_text <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    stop("JSON file not found: ", path)
  }
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

create_connection_details <- function(connection_config) {
  args <- list(
    dbms = connection_config$dbms,
    server = connection_config$server,
    user = connection_config$user,
    password = connection_config$password,
    port = connection_config$port,
    pathToDriver = connection_config$path_to_driver
  )

  args <- args[!vapply(args, is.null, logical(1))]
  do.call(DatabaseConnector::createConnectionDetails, args)
}

create_ps_prior <- function(ps_model_config) {
  Cyclops::createPrior(
    priorType = ps_model_config$prior_type,
    variance = ps_model_config$prior_variance,
    exclude = 0,
    useCrossValidation = isTRUE(ps_model_config$use_cross_validation),
    forceIntercept = FALSE
  )
}

generate_cohorts_if_requested <- function(connection_details,
                                          cohorts_config,
                                          cm_data_config) {
  if (!isTRUE(cohorts_config$generate_cohorts_from_json)) {
    return(invisible(NULL))
  }

  required_jsons <- c(
    cohorts_config$target_json_file,
    cohorts_config$comparator_json_file,
    cohorts_config$primary_outcome_json_file
  )

  if (any(vapply(required_jsons, is.null, logical(1)))) {
    stop("Cohort generation from JSON is enabled, but one or more required JSON files are missing.")
  }

  cohort_table_names <- CohortGenerator::getCohortTableNames(
    cohortTable = cohorts_config$cohort_table
  )

  CohortGenerator::createCohortTables(
    connectionDetails = connection_details,
    cohortDatabaseSchema = cohorts_config$cohort_database_schema,
    cohortTableNames = cohort_table_names,
    incremental = FALSE
  )

  build_definition_row <- function(cohort_id, cohort_name, json_file) {
    json_text <- read_json_text(json_file)
    cohort_expression <- CirceR::cohortExpressionFromJson(json_text)
    cohort_sql <- CirceR::buildCohortQuery(
      cohort_expression,
      options = CirceR::createGenerateOptions(generateStats = FALSE)
    )

    data.frame(
      cohortId = cohort_id,
      cohortName = cohort_name,
      json = json_text,
      sql = cohort_sql,
      stringsAsFactors = FALSE
    )
  }

  cohort_definition_set <- do.call(
    rbind,
    list(
      build_definition_row(
        cohort_id = cohorts_config$target_cohort_id,
        cohort_name = paste0("target_", cohorts_config$target_cohort_id),
        json_file = cohorts_config$target_json_file
      ),
      build_definition_row(
        cohort_id = cohorts_config$comparator_cohort_id,
        cohort_name = paste0("comparator_", cohorts_config$comparator_cohort_id),
        json_file = cohorts_config$comparator_json_file
      ),
      build_definition_row(
        cohort_id = cohorts_config$primary_outcome_cohort_id,
        cohort_name = paste0("outcome_", cohorts_config$primary_outcome_cohort_id),
        json_file = cohorts_config$primary_outcome_json_file
      )
    )
  )

  CohortGenerator::generateCohortSet(
    connectionDetails = connection_details,
    cdmDatabaseSchema = cm_data_config$cdm_database_schema,
    cohortDatabaseSchema = cohorts_config$cohort_database_schema,
    cohortTableNames = cohort_table_names,
    cohortDefinitionSet = cohort_definition_set
  )

  invisible(cohort_definition_set)
}

build_cm_data <- function(connection_details,
                          cohorts_config,
                          cm_data_config,
                          study_population_config,
                          output_config) {
  paths <- get_output_paths(output_config)

  get_db_args <- CohortMethod::createGetDbCohortMethodDataArgs(
    removeDuplicateSubjects = study_population_config$remove_duplicate_subjects,
    firstExposureOnly = study_population_config$first_exposure_only,
    washoutPeriod = study_population_config$washout_period,
    restrictToCommonPeriod = study_population_config$restrict_to_common_period,
    studyStartDate = cm_data_config$study_start_date,
    studyEndDate = cm_data_config$study_end_date,
    covariateSettings = cm_data_config$covariate_settings
  )

  cm_data <- CohortMethod::getDbCohortMethodData(
    connectionDetails = connection_details,
    cdmDatabaseSchema = cm_data_config$cdm_database_schema,
    targetId = cohorts_config$target_cohort_id,
    comparatorId = cohorts_config$comparator_cohort_id,
    outcomeIds = unique(cohorts_config$outcome_cohort_ids),
    exposureDatabaseSchema = cohorts_config$cohort_database_schema,
    exposureTable = cohorts_config$cohort_table,
    outcomeDatabaseSchema = cohorts_config$cohort_database_schema,
    outcomeTable = cohorts_config$cohort_table,
    getDbCohortMethodDataArgs = get_db_args
  )

  if (isTRUE(output_config$save_dev_files)) {
    save_rds_safe(cm_data, file.path(paths$dev, "cm_data.rds"))
  }

  cm_data
}

build_study_population <- function(cm_data,
                                   cohorts_config,
                                   study_population_config,
                                   output_config) {
  paths <- get_output_paths(output_config)

  study_population_args <- CohortMethod::createCreateStudyPopulationArgs(
    removeSubjectsWithPriorOutcome = study_population_config$remove_subjects_with_prior_outcome,
    priorOutcomeLookback = study_population_config$prior_outcome_lookback,
    riskWindowStart = study_population_config$risk_window_start,
    startAnchor = study_population_config$start_anchor,
    riskWindowEnd = study_population_config$risk_window_end,
    endAnchor = study_population_config$end_anchor
  )

  study_population <- CohortMethod::createStudyPopulation(
    cohortMethodData = cm_data,
    outcomeId = cohorts_config$primary_outcome_cohort_id,
    createStudyPopulationArgs = study_population_args
  )

  if (nrow(study_population) == 0) {
    stop("Study population is empty after applying inclusion and exclusion criteria.")
  }

  if (isTRUE(output_config$save_dev_files)) {
    save_rds_safe(study_population, file.path(paths$dev, "study_population.rds"))
  }

  study_population
}

extract_ps_model_coefficients <- function(ps_object, cm_data) {
  ps_model <- CohortMethod::getPsModel(
    propensityScore = ps_object,
    cohortMethodData = cm_data
  )

  if (is.null(ps_model) || nrow(ps_model) == 0) {
    return(NULL)
  }

  if (!("coefficient" %in% names(ps_model)) || !("covariateId" %in% names(ps_model))) {
    return(NULL)
  }

  ps_model$abs_coefficient <- abs(ps_model$coefficient)
  ps_model <- ps_model[ps_model$covariateId != 0, , drop = FALSE]
  ps_model[order(-ps_model$abs_coefficient), , drop = FALSE]
}

run_covariate_screening <- function(population,
                                    cm_data,
                                    covariate_screening_config,
                                    output_config) {
  paths <- get_output_paths(output_config)

  if (!isTRUE(covariate_screening_config$enabled)) {
    return(list(selected_covariate_ids = NULL, screening_log = NULL))
  }

  treated_index <- which(population$treatment == 1)
  comparator_index <- which(population$treatment == 0)

  if (length(treated_index) == 0 || length(comparator_index) == 0) {
    return(list(selected_covariate_ids = NULL, screening_log = NULL))
  }

  set.seed(covariate_screening_config$seed)
  selected_covariate_ids <- integer(0)
  screening_log <- list()

  for (run_id in seq_len(covariate_screening_config$number_of_runs)) {
    treated_n <- max(
      covariate_screening_config$min_subjects_per_group,
      floor(length(treated_index) * covariate_screening_config$sample_fraction)
    )
    comparator_n <- max(
      covariate_screening_config$min_subjects_per_group,
      floor(length(comparator_index) * covariate_screening_config$sample_fraction)
    )

    treated_sample <- sample(treated_index, size = min(treated_n, length(treated_index)))
    comparator_sample <- sample(comparator_index, size = min(comparator_n, length(comparator_index)))
    screening_population <- population[c(treated_sample, comparator_sample), , drop = FALSE]

    screening_prior <- Cyclops::createPrior(
      priorType = "normal",
      variance = 1,
      exclude = 0,
      useCrossValidation = FALSE
    )

    screening_ps_args <- CohortMethod::createCreatePsArgs(
      maxCohortSizeForFitting = nrow(screening_population),
      errorOnHighCorrelation = FALSE,
      stopOnError = FALSE,
      prior = screening_prior
    )

    screening_ps <- CohortMethod::createPs(
      cohortMethodData = cm_data,
      population = screening_population,
      createPsArgs = screening_ps_args
    )

    screening_coefficients <- extract_ps_model_coefficients(screening_ps, cm_data)

    if (is.null(screening_coefficients) || nrow(screening_coefficients) == 0) {
      screening_log[[run_id]] <- data.frame(
        run_id = run_id,
        n_treated = sum(screening_population$treatment == 1, na.rm = TRUE),
        n_comparator = sum(screening_population$treatment == 0, na.rm = TRUE),
        n_selected_this_run = 0L,
        n_selected_cumulative = length(selected_covariate_ids)
      )
      next
    }

    top_covariate_ids <- unique(utils::head(
      as.numeric(screening_coefficients$covariateId),
      covariate_screening_config$top_covariates_per_run
    ))
    top_covariate_ids <- top_covariate_ids[!is.na(top_covariate_ids)]

    selected_covariate_ids <- union(selected_covariate_ids, top_covariate_ids)
    selected_covariate_ids <- as.numeric(selected_covariate_ids)

    screening_log[[run_id]] <- data.frame(
      run_id = run_id,
      n_treated = sum(screening_population$treatment == 1, na.rm = TRUE),
      n_comparator = sum(screening_population$treatment == 0, na.rm = TRUE),
      n_selected_this_run = length(top_covariate_ids),
      n_selected_cumulative = length(selected_covariate_ids)
    )
  }

  screening_log_df <- if (length(screening_log) > 0) do.call(rbind, screening_log) else data.frame()

  if (isTRUE(output_config$save_dev_files) && nrow(screening_log_df) > 0) {
    write_csv_safe(
      screening_log_df,
      file.path(paths$dev, "covariate_screening_log.csv")
    )
  }

  list(
    selected_covariate_ids = if (length(selected_covariate_ids) == 0) NULL else as.integer(selected_covariate_ids),
    screening_log = screening_log_df
  )
}

find_high_correlation_covariates <- function(cm_data,
                                             population,
                                             threshold = 0.99,
                                             output_folder = NULL,
                                             analysis_id_filter = NULL) {
  covariates <- cm_data$covariates
  covariate_ref <- cm_data$covariateRef

  debug_dir <- output_folder %||% "output/ple_analysis/debug"
  ensure_dir(debug_dir)

  debug_file <- file.path(debug_dir, "debug_covariate_corr_debug.txt")

  safe_log <- function(...) {
    msg <- paste(..., collapse = "")
    cat(msg, "\n", file = debug_file, append = TRUE)
  }

  if (is.null(covariates)) {
    safe_log("covariates is NULL")
    return(data.frame())
  }

  covariates_df <- covariates |>
    dplyr::select(rowId, covariateId) |>
    dplyr::collect()

  safe_log("nrow(covariates_df) = ", nrow(covariates_df))

  covariates_df <- covariates_df[!is.na(covariates_df$rowId) & !is.na(covariates_df$covariateId), , drop = FALSE]
  safe_log("nrow(covariates_df) after NA filter = ", nrow(covariates_df))

  if (nrow(covariates_df) == 0) {
    safe_log("covariates_df is empty after NA filter")
    return(data.frame())
  }

  required_population_columns <- c("rowId", "treatment")
  if (!all(required_population_columns %in% names(population))) {
    safe_log(
      "population is missing required columns: ",
      paste(setdiff(required_population_columns, names(population)), collapse = ", ")
    )
    return(data.frame())
  }

  population_sub <- population[, required_population_columns, drop = FALSE]
  population_sub <- population_sub[!is.na(population_sub$rowId) & !is.na(population_sub$treatment), , drop = FALSE]
  safe_log("nrow(population_sub) initial = ", nrow(population_sub))

  population_sub <- population_sub[population_sub$rowId %in% covariates_df$rowId, , drop = FALSE]
  safe_log("nrow(population_sub) after rowId match = ", nrow(population_sub))

  if (nrow(population_sub) == 0) {
    safe_log("population_sub empty after rowId matching")
    return(data.frame())
  }

  covariate_pairs <- unique(covariates_df[, c("rowId", "covariateId"), drop = FALSE])

  if (!is.null(covariate_ref)) {
    covariate_ref_names <- colnames(covariate_ref)

    if ("covariateId" %in% covariate_ref_names &&
        !is.null(analysis_id_filter) &&
        "analysisId" %in% covariate_ref_names) {
      keep_ids <- covariate_ref |>
        dplyr::filter(.data$analysisId %in% analysis_id_filter) |>
        dplyr::select(.data$covariateId) |>
        dplyr::collect() |>
        dplyr::pull(.data$covariateId)

      keep_ids <- as.numeric(keep_ids)
      keep_ids <- keep_ids[!is.na(keep_ids)]

      safe_log("Using analysis_id_filter; length(keep_ids) = ", length(keep_ids))

      covariate_pairs <- covariate_pairs[covariate_pairs$covariateId %in% keep_ids, , drop = FALSE]
    }
  }

  covariate_ids <- sort(unique(covariate_pairs$covariateId))
  covariate_ids <- covariate_ids[!is.na(covariate_ids)]
  safe_log("length(covariate_ids) = ", length(covariate_ids))

  if (length(covariate_ids) == 0) {
    safe_log("No covariate_ids to process")
    return(data.frame())
  }

  out <- vector("list", length(covariate_ids))

  for (i in seq_along(covariate_ids)) {
    current_id <- covariate_ids[i]
    present_row_ids <- covariate_pairs$rowId[covariate_pairs$covariateId == current_id]

    x <- as.integer(population_sub$rowId %in% present_row_ids)
    y <- population_sub$treatment

    if (length(unique(x)) < 2 || length(unique(y)) < 2) {
      correlation <- NA_real_
    } else {
      correlation <- suppressWarnings(stats::cor(x, y, method = "pearson"))
    }

    mean_0 <- mean(x[y == 0], na.rm = TRUE)
    mean_1 <- mean(x[y == 1], na.rm = TRUE)

    out[[i]] <- data.frame(
      covariateId = current_id,
      mean_0 = mean_0,
      mean_1 = mean_1,
      correlation = correlation
    )
  }

  out <- do.call(rbind, out)

  if (is.null(out) || !is.data.frame(out) || nrow(out) == 0) {
    safe_log("out is empty after loop")
    return(data.frame())
  }

  out_all <- out[order(-abs(out$correlation)), , drop = FALSE]
  rownames(out_all) <- NULL


  write_csv_safe(
    out_all,
    file.path(debug_dir, "debug_all_covariate_correlations.csv")
  )

  out_sel <- out[is.finite(out$correlation) & abs(out$correlation) >= threshold, , drop = FALSE]
  safe_log("nrow(out_all) = ", nrow(out_all), " ; nrow(out_sel) = ", nrow(out_sel))

  if (nrow(out_sel) == 0) {
    return(out_sel)
  }

  out_sel <- out_sel[order(-abs(out_sel$correlation), -pmax(out_sel$mean_0, out_sel$mean_1)), , drop = FALSE]
  rownames(out_sel) <- NULL
  out_sel
}

fit_ps_model <- function(population,
                         cm_data,
                         covariate_screening_config,
                         ps_model_config,
                         output_config) {
  paths <- get_output_paths(output_config)

  screening_results <- run_covariate_screening(
    population = population,
    cm_data = cm_data,
    covariate_screening_config = covariate_screening_config,
    output_config = output_config
  )

  high_correlation_table <- data.frame()
  auto_excluded_covariate_ids <- integer(0)

  if (isTRUE(covariate_screening_config$auto_exclude_high_correlation_covariates)) {
    debug_output_folder <- if (isTRUE(output_config$save_debug_files)) paths$debug else NULL

    high_correlation_table <- find_high_correlation_covariates(
      cm_data = cm_data,
      population = population,
      threshold = covariate_screening_config$high_correlation_threshold %||% 0.99,
      output_folder = debug_output_folder,
      analysis_id_filter = c(410, 412, 413)
    )

    if (!is.null(high_correlation_table) && nrow(high_correlation_table) > 0) {
      auto_excluded_covariate_ids <- unique(as.integer(high_correlation_table$covariateId))
      auto_excluded_covariate_ids <- auto_excluded_covariate_ids[!is.na(auto_excluded_covariate_ids)]
    }
  }

  message(
    "[custom fit_ps_model] Auto-excluded covariate IDs: ",
    if (length(auto_excluded_covariate_ids) == 0) "<none>" else paste(auto_excluded_covariate_ids, collapse = ", ")
  )

  if (isTRUE(output_config$save_debug_files)) {
    write_csv_safe(
      high_correlation_table,
      file.path(paths$debug, "debug_high_correlation_table.csv")
    )

    if (length(auto_excluded_covariate_ids) > 0) {
      write_csv_safe(
        data.frame(covariateId = auto_excluded_covariate_ids),
        file.path(paths$debug, "debug_auto_excluded_covariate_ids.csv")
      )
    }
  }

  final_include_ids <- screening_results$selected_covariate_ids
  if (is.null(final_include_ids) || length(final_include_ids) == 0) {
    final_include_ids <- NULL
  } else {
    final_include_ids <- as.integer(final_include_ids)
    final_include_ids <- final_include_ids[!is.na(final_include_ids)]
  }

  final_exclude_ids <- auto_excluded_covariate_ids
  if (is.null(final_exclude_ids) || length(final_exclude_ids) == 0) {
    final_exclude_ids <- NULL
  } else {
    final_exclude_ids <- as.integer(final_exclude_ids)
    final_exclude_ids <- final_exclude_ids[!is.na(final_exclude_ids)]
  }

  message("[fit_ps_model] final include covariate count: ", length(final_include_ids))
  
  ps_args <- CohortMethod::createCreatePsArgs(
    maxCohortSizeForFitting = ps_model_config$max_cohort_size_for_fitting,
    errorOnHighCorrelation = TRUE,
    stopOnError = FALSE,
    prior = create_ps_prior(ps_model_config),
    includeCovariateIds = final_include_ids,
    excludeCovariateIds = final_exclude_ids
  )

  ps <- CohortMethod::createPs(
    cohortMethodData = cm_data,
    population = population,
    createPsArgs = ps_args
  )

  ps_model_coefficients <- extract_ps_model_coefficients(ps, cm_data)

  if (isTRUE(output_config$save_dev_files)) {
    save_rds_safe(ps, file.path(paths$dev, "ps.rds"))
    save_rds_safe(ps_model_coefficients, file.path(paths$dev, "ps_model_coefficients.rds"))
    save_rds_safe(auto_excluded_covariate_ids, file.path(paths$dev, "auto_excluded_covariate_ids.rds"))
  }

  list(
    ps = ps,
    screening = screening_results,
    ps_model_coefficients = ps_model_coefficients,
    auto_excluded_covariate_ids = auto_excluded_covariate_ids,
    high_correlation_table = high_correlation_table
  )
}

apply_trimming_if_needed <- function(ps, adjustment_config) {
  if (!isTRUE(adjustment_config$use_trimming)) {
    return(ps)
  }

  trim_fraction <- max(
    adjustment_config$trimming_lower_percentile,
    1 - adjustment_config$trimming_upper_percentile
  )

  trim_args <- CohortMethod::createTrimByPsArgs(
    trimFraction = trim_fraction
  )

  CohortMethod::trimByPs(
    population = ps,
    trimByPsArgs = trim_args
  )
}

compute_balance_metrics <- function(covariate_balance) {
  if (is.null(covariate_balance) || nrow(covariate_balance) == 0) {
    return(list(
      max_abs_smd_after = NA_real_,
      pct_above_0_1_after = NA_real_
    ))
  }

  balance_column <- intersect(
    c("asd", "asmd", "stdDiff", "standardizedMeanDifference"),
    names(covariate_balance)
  )

  if (length(balance_column) == 0) {
    return(list(
      max_abs_smd_after = NA_real_,
      pct_above_0_1_after = NA_real_
    ))
  }

  balance_values <- abs(covariate_balance[[balance_column[1]]])
  balance_values <- balance_values[is.finite(balance_values)]

  if (length(balance_values) == 0) {
    return(list(
      max_abs_smd_after = NA_real_,
      pct_above_0_1_after = NA_real_
    ))
  }

  list(
    max_abs_smd_after = max(balance_values),
    pct_above_0_1_after = mean(balance_values > 0.1)
  )
}

apply_matching <- function(ps,
                           cm_data,
                           adjustment_config,
                           output_config) {
  match_once <- function(caliper_value) {
    match_args <- CohortMethod::createMatchOnPsArgs(
      caliper = caliper_value,
      maxRatio = adjustment_config$match_ratio
    )

    matched_population <- CohortMethod::matchOnPs(
      population = ps,
      matchOnPsArgs = match_args
    )

    covariate_balance <- CohortMethod::computeCovariateBalance(
      cohortMethodData = cm_data,
      population = matched_population
    )

    list(
      matched_population = matched_population,
      covariate_balance = covariate_balance,
      caliper_used = caliper_value
    )
  }

  initial_match <- match_once(adjustment_config$caliper)

  matched_treated_n <- sum(initial_match$matched_population$treatment == 1, na.rm = TRUE)
  original_treated_n <- sum(ps$treatment == 1, na.rm = TRUE)
  matched_fraction <- if (original_treated_n > 0) matched_treated_n / original_treated_n else 0

  final_match <- initial_match

  if (isTRUE(adjustment_config$allow_caliper_adaptation) &&
      matched_fraction < adjustment_config$low_match_rate_threshold) {
    final_match <- match_once(adjustment_config$caliper_if_low_match_rate)
  } else {
    balance_metrics <- compute_balance_metrics(initial_match$covariate_balance)

    if (isTRUE(adjustment_config$allow_caliper_adaptation) &&
        matched_fraction > adjustment_config$high_match_rate_threshold &&
        is.finite(balance_metrics$pct_above_0_1_after) &&
        balance_metrics$pct_above_0_1_after > adjustment_config$poor_balance_threshold) {
      final_match <- match_once(adjustment_config$caliper_if_poor_balance)
    }
  }

  final_match
}

fit_outcome_model <- function(adjusted_population,
                              cm_data,
                              outcome_model_config,
                              output_config) {
  message(
    "[fit_outcome_model] prior_variance = ", outcome_model_config$prior_variance,
    ", use_cv = ", outcome_model_config$use_cross_validation
  )
  paths <- get_output_paths(output_config)

  prior_outcome <- Cyclops::createPrior(
    priorType = "normal",
    useCrossValidation = isTRUE(outcome_model_config$use_cross_validation),
    variance = outcome_model_config$prior_variance %||% 2
  )

  outcome_args <- CohortMethod::createFitOutcomeModelArgs(
    modelType = outcome_model_config$model_type,
    stratified = outcome_model_config$stratified,
    prior = prior_outcome
  )

  outcome_model <- CohortMethod::fitOutcomeModel(
    population = adjusted_population,
    cohortMethodData = cm_data,
    fitOutcomeModelArgs = outcome_args
  )

  save_rds_safe(outcome_model, file.path(paths$final, "outcome_model.rds"))
  outcome_model
}

build_analysis_summary <- function(cfg,
                                   study_population,
                                   outcome_model,
                                   matching_result,
                                   screening_result,
                                   ps_model_coefficients) {
  outcome_estimate <- outcome_model$outcomeModelTreatmentEstimate

  if (!is.null(outcome_estimate) && nrow(outcome_estimate) >= 1) {
    log_rr <- outcome_estimate$logRr[1]
    log_lb_95 <- outcome_estimate$logLb95[1]
    log_ub_95 <- outcome_estimate$logUb95[1]
    se_log_rr <- outcome_estimate$seLogRr[1]

    rr <- exp(log_rr)
    ci_95_lower <- exp(log_lb_95)
    ci_95_upper <- exp(log_ub_95)
    z_value <- log_rr / se_log_rr
    p_value <- 2 * (1 - stats::pnorm(abs(z_value)))
  } else {
    rr <- NA_real_
    ci_95_lower <- NA_real_
    ci_95_upper <- NA_real_
    se_log_rr <- NA_real_
    p_value <- NA_real_
  }

  selected_covariates_count <- if (!is.null(screening_result$selected_covariate_ids) &&
                                   length(screening_result$selected_covariate_ids) > 0) {
    length(screening_result$selected_covariate_ids)
  } else if (!is.null(ps_model_coefficients) && nrow(ps_model_coefficients) > 0) {
    nrow(ps_model_coefficients)
  } else {
    NA_integer_
  }

  data.frame(
    target_cohort_id = cfg$cohorts$target_cohort_id,
    comparator_cohort_id = cfg$cohorts$comparator_cohort_id,
    primary_outcome_cohort_id = cfg$cohorts$primary_outcome_cohort_id,
    treated_count_before_matching = sum(study_population$treatment == 1, na.rm = TRUE),
    comparator_count_before_matching = sum(study_population$treatment == 0, na.rm = TRUE),
    treated_count_after_matching = sum(matching_result$matched_population$treatment == 1, na.rm = TRUE),
    comparator_count_after_matching = sum(matching_result$matched_population$treatment == 0, na.rm = TRUE),
    selected_covariates_count = selected_covariates_count,
    caliper_used = matching_result$caliper_used,
    hazard_ratio = rr,
    ci_95_lower = ci_95_lower,
    ci_95_upper = ci_95_upper,
    se_log_hazard_ratio = se_log_rr,
    p_value = p_value
  )
}

build_matching_summary <- function(study_population,
                                   matched_population,
                                   covariate_balance) {
  treated_before <- sum(study_population$treatment == 1, na.rm = TRUE)
  comparator_before <- sum(study_population$treatment == 0, na.rm = TRUE)
  treated_after <- sum(matched_population$treatment == 1, na.rm = TRUE)
  comparator_after <- sum(matched_population$treatment == 0, na.rm = TRUE)

  balance_metrics <- compute_balance_metrics(covariate_balance)

  data.frame(
    treated_before_matching = treated_before,
    comparator_before_matching = comparator_before,
    treated_after_matching = treated_after,
    comparator_after_matching = comparator_after,
    treated_match_fraction = if (treated_before > 0) treated_after / treated_before else NA_real_,
    comparator_match_fraction = if (comparator_before > 0) comparator_after / comparator_before else NA_real_,
    max_abs_smd_after = balance_metrics$max_abs_smd_after,
    pct_covariates_abs_smd_gt_0_1_after = balance_metrics$pct_above_0_1_after
  )
}

save_analysis_outputs <- function(output_config,
                                  analysis_summary,
                                  matching_summary,
                                  adjusted_population,
                                  covariate_balance,
                                  ps_model_coefficients,
                                  pipeline_artifacts) {
  paths <- get_output_paths(output_config)

  write_csv_safe(analysis_summary, file.path(paths$final, "analysis_summary.csv"))
  write_csv_safe(matching_summary, file.path(paths$final, "matching_summary.csv"))

  if (!is.null(ps_model_coefficients) && nrow(ps_model_coefficients) > 0) {
    write_csv_safe(ps_model_coefficients, file.path(paths$final, "ps_model_coefficients.csv"))
  }

  save_rds_safe(adjusted_population, file.path(paths$final, "adjusted_population.rds"))
  save_rds_safe(covariate_balance, file.path(paths$final, "covariate_balance.rds"))
  save_rds_safe(pipeline_artifacts, file.path(paths$final, "pipeline_artifacts.rds"))
}

log_generated_cohort_counts <- function(connection_details, cohorts_config) {
  sql <- paste0(
    "SELECT cohort_definition_id, COUNT(*) AS n_rows, COUNT(DISTINCT subject_id) AS n_subjects ",
    "FROM ", cohorts_config$cohort_database_schema, ".", cohorts_config$cohort_table, " ",
    "WHERE cohort_definition_id IN (",
    paste(
      c(
        cohorts_config$target_cohort_id,
        cohorts_config$comparator_cohort_id,
        cohorts_config$primary_outcome_cohort_id
      ),
      collapse = ", "
    ),
    ") ",
    "GROUP BY cohort_definition_id ",
    "ORDER BY cohort_definition_id"
  )

  conn <- DatabaseConnector::connect(connection_details)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  DatabaseConnector::querySql(conn, sql)
}

run_primary_ple_pipeline <- function(cfg) {
  check_required_packages()
  paths <- get_output_paths(cfg$output)

  connection_details <- create_connection_details(cfg$connection)

  generate_cohorts_if_requested(
    connection_details = connection_details,
    cohorts_config = cfg$cohorts,
    cm_data_config = cfg$cm_data
  )

  log_generated_cohort_counts(
    connection_details = connection_details,
    cohorts_config = cfg$cohorts
  )

  cm_data <- build_cm_data(
    connection_details = connection_details,
    cohorts_config = cfg$cohorts,
    cm_data_config = cfg$cm_data,
    study_population_config = cfg$study_population,
    output_config = cfg$output
  )

  study_population <- build_study_population(
    cm_data = cm_data,
    cohorts_config = cfg$cohorts,
    study_population_config = cfg$study_population,
    output_config = cfg$output
  )

  ps_fit <- fit_ps_model(
    population = study_population,
    cm_data = cm_data,
    covariate_screening_config = cfg$covariate_screening,
    ps_model_config = cfg$ps_model,
    output_config = cfg$output
  )

  ps_for_adjustment <- apply_trimming_if_needed(
    ps = ps_fit$ps,
    adjustment_config = cfg$adjustment
  )

  matching_result <- apply_matching(
    ps = ps_for_adjustment,
    cm_data = cm_data,
    adjustment_config = cfg$adjustment,
    output_config = cfg$output
  )

  outcome_model <- fit_outcome_model(
    adjusted_population = matching_result$matched_population,
    cm_data = cm_data,
    outcome_model_config = cfg$outcome_model,
    output_config = cfg$output
  )

  analysis_summary <- build_analysis_summary(
    cfg = cfg,
    study_population = study_population,
    outcome_model = outcome_model,
    matching_result = matching_result,
    screening_result = ps_fit$screening,
    ps_model_coefficients = ps_fit$ps_model_coefficients
  )

  matching_summary <- build_matching_summary(
    study_population = study_population,
    matched_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance
  )

  pipeline_artifacts <- list(
    adjusted_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance,
    caliper_used = matching_result$caliper_used,
    outcome_model = outcome_model,
    analysis_summary = analysis_summary,
    matching_summary = matching_summary
  )

  save_analysis_outputs(
    output_config = cfg$output,
    analysis_summary = analysis_summary,
    matching_summary = matching_summary,
    adjusted_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance,
    ps_model_coefficients = ps_fit$ps_model_coefficients,
    pipeline_artifacts = pipeline_artifacts
  )

  invisible(
    list(
      adjusted_population = matching_result$matched_population,
      covariate_balance = matching_result$covariate_balance,
      caliper_used = matching_result$caliper_used,
      outcome_model = outcome_model,
      analysis_summary = analysis_summary,
      matching_summary = matching_summary
    )
  )
}

run_pipeline_safe <- function(cfg) {
  tryCatch(
    {
      run_primary_ple_pipeline(cfg)
      list(success = TRUE, error = NULL)
    },
    error = function(e) {
      list(success = FALSE, error = conditionMessage(e))
    }
  )
}