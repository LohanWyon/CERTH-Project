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
  if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a
}

write_csv_safe <- function(x, path) {
  if (is.null(x)) return(invisible(NULL))
  ensure_dir(dirname(path))
  readr::write_csv(x, path)
  invisible(path)
}

save_rds_safe <- function(x, path) {
  if (is.null(x)) return(invisible(NULL))
  ensure_dir(dirname(path))
  saveRDS(x, path)
  invisible(path)
}

get_output_paths <- function(output_config) {
  final_dir <- output_config$final_output_folder %||% output_config$output_folder
  dev_dir <- output_config$dev_output_folder %||% file.path(final_dir, "dev")
  debug_dir <- output_config$debug_output_folder %||% file.path(final_dir, "debug")

  ensure_dir(final_dir)
  if (isTRUE(output_config$save_dev_files)) ensure_dir(dev_dir)
  if (isTRUE(output_config$save_debug_files)) ensure_dir(debug_dir)

  list(final = final_dir, dev = dev_dir, debug = debug_dir)
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
  if (!isTRUE(cohorts_config$generate_cohorts_from_json)) return(invisible(NULL))

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

  study_population
}

extract_ps_model_coefficients <- function(ps_object, cm_data) {
  ps_model <- CohortMethod::getPsModel(
    propensityScore = ps_object,
    cohortMethodData = cm_data
  )

  if (is.null(ps_model) || nrow(ps_model) == 0 ||
      !("coefficient" %in% names(ps_model)) ||
      !("covariateId" %in% names(ps_model))) {
    return(NULL)
  }

  ps_model <- ps_model[ps_model$covariateId != 0, , drop = FALSE]
  ps_model$abs_coefficient <- abs(ps_model$coefficient)
  ps_model[order(-ps_model$abs_coefficient), , drop = FALSE]
}

export_propensity_score_population <- function(population) {
  if (is.null(population) || !is.data.frame(population)) return(NULL)

  score_column <- intersect(c("propensityScore", "propensity_score", "ps"), names(population))
  treatment_column <- intersect(c("treatment", "treatmentGroup", "exposure"), names(population))

  if (length(score_column) == 0 || length(treatment_column) == 0) return(NULL)

  out <- data.frame(
    treatment = population[[treatment_column[1]]],
    propensity_score = population[[score_column[1]]]
  )

  if ("rowId" %in% names(population)) out$rowId <- population$rowId
  if ("stratumId" %in% names(population)) out$stratumId <- population$stratumId

  out
}

save_kaplan_meier_plot <- function(adjusted_population, output_folder) {
  if (is.null(adjusted_population) || nrow(adjusted_population) == 0) return(FALSE)

  output_file <- file.path(output_folder, "kaplan_meier.png")

  tryCatch({
    CohortMethod::plotKaplanMeier(
      population = adjusted_population,
      censorMarks = FALSE,
      confidenceIntervals = TRUE,
      includeZero = FALSE,
      dataTable = TRUE,
      dataCutoff = 0.9,
      targetLabel = "Target",
      comparatorLabel = "Comparator",
      title = "Kaplan-Meier survival curve after matching",
      fileName = output_file
    )
    file.exists(output_file)
  }, error = function(e) FALSE)
}

save_analysis_outputs <- function(output_config,
                                  analysis_summary,
                                  matching_summary,
                                  ps_before_matching,
                                  ps_after_matching,
                                  adjusted_population,
                                  covariate_balance,
                                  ps_model_coefficients,
                                  pipeline_artifacts) {
  paths <- get_output_paths(output_config)

  write_csv_safe(analysis_summary, file.path(paths$final, "analysis_summary.csv"))
  write_csv_safe(matching_summary, file.path(paths$final, "matching_summary.csv"))
  write_csv_safe(
    export_propensity_score_population(ps_before_matching),
    file.path(paths$final, "ps_before_matching.csv")
  )
  write_csv_safe(
    export_propensity_score_population(ps_after_matching),
    file.path(paths$final, "ps_after_matching.csv")
  )
  write_csv_safe(covariate_balance, file.path(paths$final, "covariate_balance.csv"))

  if (!is.null(ps_model_coefficients) && nrow(ps_model_coefficients) > 0) {
    write_csv_safe(
      ps_model_coefficients,
      file.path(paths$final, "ps_model_coefficients.csv")
    )
  }

  if (!is.null(pipeline_artifacts$outcome_model)) {
    outcome_estimate <- pipeline_artifacts$outcome_model$outcomeModelTreatmentEstimate
    if (!is.null(outcome_estimate) && is.data.frame(outcome_estimate)) {
      write_csv_safe(
        outcome_estimate,
        file.path(paths$final, "outcome_model_estimate.csv")
      )
    }
  }

  save_kaplan_meier_plot(
    adjusted_population = adjusted_population,
    output_folder = paths$final
  )

  if (isTRUE(output_config$save_dev_files)) {
    save_rds_safe(adjusted_population, file.path(paths$dev, "adjusted_population.rds"))
    save_rds_safe(covariate_balance, file.path(paths$dev, "covariate_balance.rds"))
    save_rds_safe(pipeline_artifacts, file.path(paths$dev, "pipeline_artifacts.rds"))
  }

  invisible(paths$final)
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
  selected_covariate_ids <- numeric(0)
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

    max_abs_screening_coefficient <- covariate_screening_config$max_abs_screening_coefficient %||% 3
    screening_coefficients <- screening_coefficients[
      is.finite(screening_coefficients$coefficient) &
        abs(screening_coefficients$coefficient) <= max_abs_screening_coefficient,
      ,
      drop = FALSE
    ]

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

  if (isTRUE(covariate_screening_config$include_forced_covariates)) {
    forced_ids <- unique(as.numeric(covariate_screening_config$forced_covariate_ids))
    forced_ids <- forced_ids[!is.na(forced_ids)]
    selected_covariate_ids <- union(as.numeric(selected_covariate_ids), forced_ids)
  }

  screening_log_df <- if (length(screening_log) > 0) do.call(rbind, screening_log) else data.frame()

  if (isTRUE(output_config$save_dev_files) && nrow(screening_log_df) > 0) {
    write_csv_safe(screening_log_df, file.path(paths$dev, "covariate_screening_log.csv"))
  }

  list(
    selected_covariate_ids = if (length(selected_covariate_ids) == 0) NULL else as.numeric(selected_covariate_ids),
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
    cat(paste(..., collapse = ""), "\n", file = debug_file, append = TRUE)
  }

  if (is.null(covariates)) {
    safe_log("covariates is NULL")
    return(data.frame())
  }

  covariates_df <- covariates |>
    dplyr::select(rowId, covariateId) |>
    dplyr::collect()

  covariates_df$rowId <- as.numeric(covariates_df$rowId)
  covariates_df$covariateId <- as.numeric(covariates_df$covariateId)
  covariates_df <- covariates_df[
    !is.na(covariates_df$rowId) & !is.na(covariates_df$covariateId),
    , drop = FALSE
  ]

  if (nrow(covariates_df) == 0) {
    safe_log("covariates_df is empty after filtering")
    return(data.frame())
  }

  if (!all(c("rowId", "treatment") %in% names(population))) {
    safe_log("population is missing rowId or treatment")
    return(data.frame())
  }

  population_sub <- population[, c("rowId", "treatment"), drop = FALSE]
  population_sub$rowId <- as.numeric(population_sub$rowId)
  population_sub$treatment <- as.numeric(population_sub$treatment)
  population_sub <- population_sub[
    !is.na(population_sub$rowId) & !is.na(population_sub$treatment),
    , drop = FALSE
  ]
  population_sub <- population_sub[population_sub$rowId %in% covariates_df$rowId, , drop = FALSE]

  if (nrow(population_sub) == 0) {
    safe_log("population_sub is empty after rowId matching")
    return(data.frame())
  }

  covariate_pairs <- unique(covariates_df[, c("rowId", "covariateId"), drop = FALSE])

  if (!is.null(covariate_ref) && !is.null(analysis_id_filter)) {
    covariate_ref_names <- colnames(covariate_ref)
    if ("covariateId" %in% covariate_ref_names && "analysisId" %in% covariate_ref_names) {
      keep_ids <- covariate_ref |>
        dplyr::filter(analysisId %in% analysis_id_filter) |>
        dplyr::select(covariateId) |>
        dplyr::collect() |>
        dplyr::pull(covariateId)

      keep_ids <- unique(as.numeric(keep_ids))
      keep_ids <- keep_ids[!is.na(keep_ids)]
      covariate_pairs <- covariate_pairs[
        covariate_pairs$covariateId %in% keep_ids,
        , drop = FALSE
      ]
    }
  }

  covariate_ids <- sort(unique(as.numeric(covariate_pairs$covariateId)))
  covariate_ids <- covariate_ids[!is.na(covariate_ids)]

  if (length(covariate_ids) == 0) {
    safe_log("No covariate IDs available after filtering")
    return(data.frame())
  }

  results <- vector("list", length(covariate_ids))

  for (i in seq_along(covariate_ids)) {
    covariate_id <- covariate_ids[i]
    present_row_ids <- covariate_pairs$rowId[covariate_pairs$covariateId == covariate_id]
    covariate_value <- as.integer(population_sub$rowId %in% present_row_ids)
    treatment_value <- population_sub$treatment

    correlation <- if (length(unique(covariate_value)) < 2 || length(unique(treatment_value)) < 2) {
      NA_real_
    } else {
      suppressWarnings(stats::cor(covariate_value, treatment_value, method = "pearson"))
    }

    results[[i]] <- data.frame(
      covariateId = as.numeric(covariate_id),
      mean_0 = mean(covariate_value[treatment_value == 0], na.rm = TRUE),
      mean_1 = mean(covariate_value[treatment_value == 1], na.rm = TRUE),
      correlation = correlation
    )
  }

  results <- do.call(rbind, results)
  if (is.null(results) || nrow(results) == 0) return(data.frame())

  results <- results[
    is.finite(results$correlation) & abs(results$correlation) >= threshold,
    , drop = FALSE
  ]
  results <- results[order(-abs(results$correlation), -pmax(results$mean_0, results$mean_1)), , drop = FALSE]
  rownames(results) <- NULL

  if (!is.null(output_folder)) {
    write_csv_safe(results, file.path(debug_dir, "debug_high_correlation_covariates.csv"))
  }

  results
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
  auto_excluded_covariate_ids <- numeric(0)

  if (isTRUE(covariate_screening_config$auto_exclude_high_correlation_covariates)) {
    debug_output_folder <- if (isTRUE(output_config$save_debug_files)) paths$debug else NULL

    high_correlation_table <- find_high_correlation_covariates(
      cm_data = cm_data,
      population = population,
      threshold = covariate_screening_config$high_correlation_threshold %||% 0.95,
      output_folder = debug_output_folder,
      analysis_id_filter = c(410, 412, 413)
    )

    if (!is.null(high_correlation_table) && nrow(high_correlation_table) > 0) {
      auto_excluded_covariate_ids <- unique(as.numeric(high_correlation_table$covariateId))
      auto_excluded_covariate_ids <- auto_excluded_covariate_ids[!is.na(auto_excluded_covariate_ids)]
    }
  }

  manual_excluded_covariate_ids <- numeric(0)
  if (isTRUE(covariate_screening_config$exclude_artefactual_covariates)) {
    manual_excluded_covariate_ids <- unique(as.numeric(covariate_screening_config$excluded_covariate_ids))
    manual_excluded_covariate_ids <- manual_excluded_covariate_ids[!is.na(manual_excluded_covariate_ids)]
  }

  final_include_ids <- screening_results$selected_covariate_ids
  if (is.null(final_include_ids) || length(final_include_ids) == 0) {
    final_include_ids <- NULL
  } else {
    final_include_ids <- unique(as.numeric(final_include_ids))
    final_include_ids <- final_include_ids[!is.na(final_include_ids)]
  }

  final_exclude_ids <- unique(c(auto_excluded_covariate_ids, manual_excluded_covariate_ids))
  final_exclude_ids <- as.numeric(final_exclude_ids)
  final_exclude_ids <- final_exclude_ids[!is.na(final_exclude_ids)]

  if (!is.null(final_include_ids) && length(final_exclude_ids) > 0) {
    final_include_ids <- setdiff(final_include_ids, final_exclude_ids)
  }
  if (!is.null(final_include_ids) && length(final_include_ids) == 0) final_include_ids <- NULL

  message(
    "Auto-excluded covariate IDs: ",
    if (length(auto_excluded_covariate_ids) == 0) "" else paste(auto_excluded_covariate_ids, collapse = ", ")
  )
  message(
    "Manually excluded covariate IDs: ",
    if (length(manual_excluded_covariate_ids) == 0) "" else paste(manual_excluded_covariate_ids, collapse = ", ")
  )
  message("Final include covariate count: ", length(final_include_ids))
  message("Final exclude covariate count: ", length(final_exclude_ids))

  if (isTRUE(output_config$save_debug_files)) {
    write_csv_safe(high_correlation_table, file.path(paths$debug, "debug_high_correlation_table.csv"))
    if (length(auto_excluded_covariate_ids) > 0) {
      write_csv_safe(data.frame(covariateId = auto_excluded_covariate_ids), file.path(paths$debug, "debug_auto_excluded_covariate_ids.csv"))
    }
    if (length(manual_excluded_covariate_ids) > 0) {
      write_csv_safe(data.frame(covariateId = manual_excluded_covariate_ids), file.path(paths$debug, "debug_manual_excluded_covariate_ids.csv"))
    }
  }

  ps_args <- CohortMethod::createCreatePsArgs(
    maxCohortSizeForFitting = ps_model_config$max_cohort_size_for_fitting,
    errorOnHighCorrelation = FALSE,
    stopOnError = FALSE,
    prior = create_ps_prior(ps_model_config),
    includeCovariateIds = final_include_ids,
    excludeCovariateIds = NULL
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
    save_rds_safe(manual_excluded_covariate_ids, file.path(paths$dev, "manual_excluded_covariate_ids.rds"))
  }

  list(
    ps = ps,
    screening = screening_results,
    ps_model_coefficients = ps_model_coefficients,
    auto_excluded_covariate_ids = auto_excluded_covariate_ids,
    manually_excluded_covariate_ids = manual_excluded_covariate_ids,
    final_include_ids = final_include_ids,
    final_exclude_ids = final_exclude_ids,
    high_correlation_table = high_correlation_table
  )
}

apply_trimming_if_needed <- function(ps, adjustment_config) {
  if (!isTRUE(adjustment_config$use_trimming)) return(ps)

  trim_fraction <- max(
    adjustment_config$trimming_lower_percentile,
    1 - adjustment_config$trimming_upper_percentile
  )

  trim_args <- CohortMethod::createTrimByPsArgs(trimFraction = trim_fraction)
  CohortMethod::trimByPs(population = ps, trimByPsArgs = trim_args)
}

filter_covariate_balance <- function(covariate_balance, include_covariate_ids) {
  if (is.null(covariate_balance) || !is.data.frame(covariate_balance) ||
      nrow(covariate_balance) == 0 || is.null(include_covariate_ids) ||
      length(include_covariate_ids) == 0 ||
      !("covariateId" %in% names(covariate_balance))) {
    return(covariate_balance)
  }

  include_covariate_ids <- unique(as.numeric(include_covariate_ids))
  include_covariate_ids <- include_covariate_ids[!is.na(include_covariate_ids)]

  covariate_balance[
    as.numeric(covariate_balance$covariateId) %in% include_covariate_ids,
    , drop = FALSE
  ]
}

compute_balance_metrics <- function(covariate_balance) {
  if (is.null(covariate_balance) || nrow(covariate_balance) == 0) {
    return(list(max_abs_smd_after = NA_real_, pct_above_0_1_after = NA_real_))
  }

  balance_column <- intersect(
    c("asd", "asmd", "stdDiff", "standardizedMeanDifference"),
    names(covariate_balance)
  )

  if (length(balance_column) == 0) {
    return(list(max_abs_smd_after = NA_real_, pct_above_0_1_after = NA_real_))
  }

  balance_values <- abs(covariate_balance[[balance_column[1]]])
  balance_values <- balance_values[is.finite(balance_values)]

  if (length(balance_values) == 0) {
    return(list(max_abs_smd_after = NA_real_, pct_above_0_1_after = NA_real_))
  }

  list(
    max_abs_smd_after = max(balance_values),
    pct_above_0_1_after = mean(balance_values > 0.1)
  )
}

try_match <- function(ps, cm_data, caliper, match_ratio) {
  match_args <- CohortMethod::createMatchOnPsArgs(
    caliper = caliper,
    maxRatio = match_ratio
  )

  matched_population <- CohortMethod::matchOnPs(
    population = ps,
    matchOnPsArgs = match_args
  )

  treated_before <- sum(ps$treatment == 1, na.rm = TRUE)
  treated_after <- sum(matched_population$treatment == 1, na.rm = TRUE)

  list(
    matched_population = matched_population,
    caliper_used = caliper,
    match_rate = if (treated_before > 0) treated_after / treated_before else 0
  )
}

build_matching_result <- function(result, cm_data, include_covariate_ids = NULL) {
  covariate_balance <- CohortMethod::computeCovariateBalance(
    cohortMethodData = cm_data,
    population = result$matched_population
  )

  covariate_balance <- filter_covariate_balance(
    covariate_balance = covariate_balance,
    include_covariate_ids = include_covariate_ids
  )

  list(
    matched_population = result$matched_population,
    covariate_balance = covariate_balance,
    caliper_used = result$caliper_used,
    match_rate = result$match_rate
  )
}

interpolate_and_match <- function(ps,
                                  cm_data,
                                  cal1,
                                  res1,
                                  cal2,
                                  res2,
                                  target_rate,
                                  tolerance,
                                  match_ratio,
                                  include_covariate_ids = NULL) {
  interp_fun <- stats::approxfun(
    x = c(res1$match_rate, res2$match_rate),
    y = c(cal1, cal2),
    method = "linear",
    rule = 2
  )

  caliper_optimal <- interp_fun(target_rate)
  caliper_optimal <- max(0.05, min(0.5, caliper_optimal))

  result_optimal <- try_match(ps, cm_data, caliper_optimal, match_ratio)

  if (abs(result_optimal$match_rate - target_rate) <= tolerance) {
    return(build_matching_result(result_optimal, cm_data, include_covariate_ids))
  }

  caliper_refine_low <- max(0.05, caliper_optimal - 0.02)
  caliper_refine_high <- min(0.5, caliper_optimal + 0.02)

  result_refine_low <- try_match(ps, cm_data, caliper_refine_low, match_ratio)
  result_refine_high <- try_match(ps, cm_data, caliper_refine_high, match_ratio)

  all_results <- list(result_optimal, result_refine_low, result_refine_high)
  best_idx <- which.min(vapply(all_results, function(r) abs(r$match_rate - target_rate), numeric(1)))

  build_matching_result(all_results[[best_idx]], cm_data, include_covariate_ids)
}

apply_matching <- function(ps,
                           cm_data,
                           adjustment_config,
                           output_config,
                           include_covariate_ids = NULL) {
  if (isTRUE(adjustment_config$auto_caliper_search)) {
    message("[auto_caliper] Starting auto-caliper search...")

    target_rate <- adjustment_config$target_match_rate %||% 0.65
    tolerance <- adjustment_config$target_match_rate_tolerance %||% 0.15
    match_ratio <- adjustment_config$match_ratio

    message(sprintf("[auto_caliper] Target: %.2f ± %.2f", target_rate, tolerance))

    caliper_test <- c(0.15, 0.25)
    results <- lapply(caliper_test, function(cal) {
      message(sprintf("[auto_caliper] Testing caliper %.2f...", cal))
      try_match(ps, cm_data, cal, match_ratio)
    })

    rates <- vapply(results, function(r) r$match_rate, numeric(1))
    message(sprintf(
      "[auto_caliper] Match rates: %.2f (cal=%.2f), %.2f (cal=%.2f)",
      rates[1], caliper_test[1], rates[2], caliper_test[2]
    ))

    if ((rates[1] <= target_rate && rates[2] >= target_rate) ||
        (rates[1] >= target_rate && rates[2] <= target_rate)) {
      message("[auto_caliper] Target is between the two rates, interpolating...")
      return(interpolate_and_match(
        ps, cm_data,
        caliper_test[1], results[[1]],
        caliper_test[2], results[[2]],
        target_rate, tolerance, match_ratio,
        include_covariate_ids
      ))
    }

    if (rates[1] < target_rate && rates[2] < target_rate) {
      message("[auto_caliper] Both rates below target, testing wider caliper...")
      caliper_wide <- c(0.35, 0.50, 0.75)
      result_last <- NULL

      for (cal in caliper_wide) {
        result_wide <- try_match(ps, cm_data, cal, match_ratio)
        message(sprintf("[auto_caliper] Caliper %.2f → match rate: %.2f", cal, result_wide$match_rate))

        if (result_wide$match_rate >= target_rate) {
          return(interpolate_and_match(
            ps, cm_data,
            caliper_test[2], results[[2]],
            cal, result_wide,
            target_rate, tolerance, match_ratio,
            include_covariate_ids
          ))
        }
        result_last <- result_wide
      }

      message("[auto_caliper] Could not reach target, using widest caliper tested")
      all_results <- c(results, list(result_last))
      best_idx <- which.max(vapply(all_results, function(r) r$match_rate, numeric(1)))
      return(build_matching_result(all_results[[best_idx]], cm_data, include_covariate_ids))
    }

    if (rates[1] > target_rate && rates[2] > target_rate) {
      message("[auto_caliper] Both rates above target, testing stricter caliper...")
      caliper_strict <- c(0.10, 0.05, 0.02)
      result_last <- NULL

      for (cal in caliper_strict) {
        result_strict <- try_match(ps, cm_data, cal, match_ratio)
        message(sprintf("[auto_caliper] Caliper %.2f → match rate: %.2f", cal, result_strict$match_rate))

        if (result_strict$match_rate <= target_rate) {
          return(interpolate_and_match(
            ps, cm_data,
            cal, result_strict,
            caliper_test[1], results[[1]],
            target_rate, tolerance, match_ratio,
            include_covariate_ids
          ))
        }
        result_last <- result_strict
      }

      message("[auto_caliper] Could not reach target, using strictest caliper tested")
      all_results <- c(results, list(result_last))
      best_idx <- which.min(vapply(all_results, function(r) r$match_rate, numeric(1)))
      return(build_matching_result(all_results[[best_idx]], cm_data, include_covariate_ids))
    }

    message("[auto_caliper] Unexpected state, using best of initial tests")
    best_idx <- which.min(abs(rates - target_rate))
    return(build_matching_result(results[[best_idx]], cm_data, include_covariate_ids))
  }

  result <- try_match(
    ps = ps,
    cm_data = cm_data,
    caliper = adjustment_config$caliper,
    match_ratio = adjustment_config$match_ratio
  )

  build_matching_result(
    result = result,
    cm_data = cm_data,
    include_covariate_ids = include_covariate_ids
  )
}

fit_outcome_model <- function(adjusted_population,
                              cm_data,
                              outcome_model_config,
                              output_config) {
  message(
    "[fit_outcome_model] prior_variance = ", outcome_model_config$prior_variance,
    ", use_cv = ", outcome_model_config$use_cross_validation
  )

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

  CohortMethod::fitOutcomeModel(
    population = adjusted_population,
    cohortMethodData = cm_data,
    fitOutcomeModelArgs = outcome_args
  )
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
    match_rate = matching_result$match_rate %||% NA_real_,
    hazard_ratio = rr,
    ci_95_lower = ci_95_lower,
    ci_95_upper = ci_95_upper,
    se_log_hazard_ratio = se_log_rr,
    p_value = p_value
  )
}

build_matching_summary <- function(study_population,
                                   matched_population,
                                   covariate_balance,
                                   match_rate = NULL) {
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
    match_rate = match_rate %||% if (treated_before > 0) treated_after / treated_before else NA_real_,
    max_abs_smd_after = balance_metrics$max_abs_smd_after,
    pct_covariates_abs_smd_gt_0_1_after = balance_metrics$pct_above_0_1_after
  )
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
    ") GROUP BY cohort_definition_id ORDER BY cohort_definition_id"
  )

  conn <- DatabaseConnector::connect(connection_details)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)
  DatabaseConnector::querySql(conn, sql)
}

run_primary_ple_pipeline <- function(cfg) {
  check_required_packages()
  get_output_paths(cfg$output)

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

  ps_before_matching <- ps_fit$ps
  ps_for_adjustment <- apply_trimming_if_needed(ps_fit$ps, cfg$adjustment)

  matching_result <- apply_matching(
    ps = ps_for_adjustment,
    cm_data = cm_data,
    adjustment_config = cfg$adjustment,
    output_config = cfg$output,
    include_covariate_ids = ps_fit$final_include_ids
  )

  ps_after_matching <- matching_result$matched_population

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
    covariate_balance = matching_result$covariate_balance,
    match_rate = matching_result$match_rate
  )

  pipeline_artifacts <- list(
    adjusted_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance,
    caliper_used = matching_result$caliper_used,
    match_rate = matching_result$match_rate,
    final_include_ids = ps_fit$final_include_ids,
    final_exclude_ids = ps_fit$final_exclude_ids,
    outcome_model = outcome_model,
    analysis_summary = analysis_summary,
    matching_summary = matching_summary
  )

  save_analysis_outputs(
    output_config = cfg$output,
    analysis_summary = analysis_summary,
    matching_summary = matching_summary,
    ps_before_matching = ps_before_matching,
    ps_after_matching = ps_after_matching,
    adjusted_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance,
    ps_model_coefficients = ps_fit$ps_model_coefficients,
    pipeline_artifacts = pipeline_artifacts
  )

  invisible(list(
    adjusted_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance,
    caliper_used = matching_result$caliper_used,
    match_rate = matching_result$match_rate,
    outcome_model = outcome_model,
    analysis_summary = analysis_summary,
    matching_summary = matching_summary
  ))
}

run_pipeline_safe <- function(cfg) {
  tryCatch(
    {
      run_primary_ple_pipeline(cfg)
      list(success = TRUE, error = NULL)
    },
    error = function(e) list(success = FALSE, error = conditionMessage(e))
  )
}
