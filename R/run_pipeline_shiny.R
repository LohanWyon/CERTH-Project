# R/run_pipeline_shiny.R

required_packages <- c(
  "DatabaseConnector",
  "SqlRender",
  "FeatureExtraction",
  "CohortMethod",
  "Cyclops",
  "CohortGenerator",
  "CirceR",
  "readr"
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
                                          cm_data_config,
                                          connection_config) {
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
                          connection_config,
                          output_config) {
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

  saveRDS(cm_data, file.path(output_config$output_folder, "cm_data.rds"))
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

  saveRDS(study_population, file.path(output_config$output_folder, "study_population.rds"))
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

  coefficient_column <- intersect(c("coefficient", "estimate", "value"), names(ps_model))[1]
  covariate_id_column <- intersect(c("covariateId", "covariate_id"), names(ps_model))[1]

  if (is.na(coefficient_column) || is.na(covariate_id_column)) {
    return(NULL)
  }

  ps_model$abs_coefficient <- abs(ps_model[[coefficient_column]])
  ps_model <- ps_model[!is.na(ps_model[[covariate_id_column]]), , drop = FALSE]
  ps_model <- ps_model[ps_model[[covariate_id_column]] != 0, , drop = FALSE]
  ps_model[order(-ps_model$abs_coefficient), , drop = FALSE]
}

run_covariate_screening <- function(population,
                                    cm_data,
                                    covariate_screening_config,
                                    output_config) {
  if (!isTRUE(covariate_screening_config$enabled)) {
    return(list(selected_covariate_ids = NULL, screening_log = NULL))
  }

  treated_index <- which(population$treatment == 1)
  comparator_index <- which(population$treatment == 0)

  if (length(treated_index) == 0 || length(comparator_index) == 0) {
    return(list(selected_covariate_ids = NULL, screening_log = NULL))
  }

  set.seed(covariate_screening_config$seed)
  selected_covariate_ids <- c()
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

    screening_coeffs <- extract_ps_model_coefficients(screening_ps, cm_data)

    if (is.null(screening_coeffs) || nrow(screening_coeffs) == 0) {
      next
    }

    top_ids <- unique(utils::head(
      screening_coeffs[[intersect(c("covariateId", "covariate_id"), names(screening_coeffs))[1]]],
      covariate_screening_config$top_covariates_per_run
    ))

    selected_covariate_ids <- union(selected_covariate_ids, top_ids)

    screening_log[[run_id]] <- data.frame(
      run_id = run_id,
      n_treated = sum(screening_population$treatment == 1, na.rm = TRUE),
      n_comparator = sum(screening_population$treatment == 0, na.rm = TRUE),
      n_selected_this_run = length(top_ids),
      n_selected_cumulative = length(selected_covariate_ids)
    )
  }

  screening_log_df <- if (length(screening_log) > 0) do.call(rbind, screening_log) else data.frame()
  readr::write_csv(screening_log_df, file.path(output_config$output_folder, "covariate_screening_log.csv"))

  list(
    selected_covariate_ids = if (length(selected_covariate_ids) == 0) NULL else selected_covariate_ids,
    screening_log = screening_log_df
  )
}

fit_ps_model <- function(population,
                         cm_data,
                         covariate_screening_config,
                         ps_model_config,
                         output_config) {
  screening_res <- run_covariate_screening(
    population = population,
    cm_data = cm_data,
    covariate_screening_config = covariate_screening_config,
    output_config = output_config
  )

  ps_args <- CohortMethod::createCreatePsArgs(
    maxCohortSizeForFitting = ps_model_config$max_cohort_size_for_fitting,
    errorOnHighCorrelation = FALSE,
    stopOnError = FALSE,
    prior = create_ps_prior(ps_model_config),
    includeCovariateIds = screening_res$selected_covariate_ids
  )

  ps <- CohortMethod::createPs(
    cohortMethodData = cm_data,
    population = population,
    createPsArgs = ps_args
  )

  ps_model_coefficients <- extract_ps_model_coefficients(ps, cm_data)

  saveRDS(ps, file.path(output_config$output_folder, "ps.rds"))
  saveRDS(ps_model_coefficients, file.path(output_config$output_folder, "ps_model_coefficients.rds"))

  list(
    ps = ps,
    screening = screening_res,
    ps_model_coefficients = ps_model_coefficients
  )
}

apply_trimming_if_needed <- function(ps,
                                     adjustment_config) {
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

  col_after <- intersect(c("asd", "asmd", "stdDiff", "standardizedMeanDifference"), names(covariate_balance))
  if (length(col_after) == 0) {
    return(list(
      max_abs_smd_after = NA_real_,
      pct_above_0_1_after = NA_real_
    ))
  }

  vals <- abs(covariate_balance[[col_after[1]]])
  vals <- vals[is.finite(vals)]

  if (length(vals) == 0) {
    return(list(
      max_abs_smd_after = NA_real_,
      pct_above_0_1_after = NA_real_
    ))
  }

  list(
    max_abs_smd_after = max(vals),
    pct_above_0_1_after = mean(vals > 0.1)
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

  saveRDS(final_match$matched_population, file.path(output_config$output_folder, "adjusted_population.rds"))
  saveRDS(final_match$covariate_balance, file.path(output_config$output_folder, "covariate_balance.rds"))

  final_match
}

fit_outcome_model <- function(adjusted_population,
                              cm_data,
                              outcome_model_config,
                              output_config) {
  prior_outcome <- Cyclops::createPrior(
    priorType = "normal",
    useCrossValidation = FALSE,
    variance = 2
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

  saveRDS(outcome_model, file.path(output_config$output_folder, "outcome_model.rds"))
  outcome_model
}

build_analysis_summary <- function(cfg,
                                   study_population,
                                   adjusted_population,
                                   outcome_model,
                                   matching_result,
                                   screening_result) {
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

  data.frame(
    target_cohort_id = cfg$cohorts$target_cohort_id,
    comparator_cohort_id = cfg$cohorts$comparator_cohort_id,
    primary_outcome_cohort_id = cfg$cohorts$primary_outcome_cohort_id,
    treated_count_before_matching = sum(study_population$treatment == 1, na.rm = TRUE),
    comparator_count_before_matching = sum(study_population$treatment == 0, na.rm = TRUE),
    treated_count_after_matching = sum(matching_result$matched_population$treatment == 1, na.rm = TRUE),
    comparator_count_after_matching = sum(matching_result$matched_population$treatment == 0, na.rm = TRUE),
    selected_covariates_count = length(screening_result$selected_covariate_ids %||% numeric(0)),
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

save_analysis_outputs <- function(output_folder,
                                  analysis_summary,
                                  matching_summary,
                                  study_population,
                                  adjusted_population,
                                  covariate_balance,
                                  screening_log,
                                  ps_model_coefficients) {
  readr::write_csv(analysis_summary, file.path(output_folder, "analysis_summary.csv"))
  readr::write_csv(matching_summary, file.path(output_folder, "matching_summary.csv"))

  if (!is.null(screening_log) && nrow(screening_log) > 0) {
    readr::write_csv(screening_log, file.path(output_folder, "covariate_screening_log.csv"))
  }

  if (!is.null(ps_model_coefficients) && nrow(ps_model_coefficients) > 0) {
    readr::write_csv(ps_model_coefficients, file.path(output_folder, "ps_model_coefficients.csv"))
  }

  saveRDS(study_population, file.path(output_folder, "study_population.rds"))
  saveRDS(adjusted_population, file.path(output_folder, "adjusted_population.rds"))
  saveRDS(covariate_balance, file.path(output_folder, "covariate_balance.rds"))
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
  ensure_dir(cfg$output$output_folder)

  connection_details <- create_connection_details(cfg$connection)

  generate_cohorts_if_requested(
    connection_details = connection_details,
    cohorts_config = cfg$cohorts,
    cm_data_config = cfg$cm_data,
    connection_config = cfg$connection
  )

  counts <- log_generated_cohort_counts(
    connection_details = connection_details,
    cohorts_config = cfg$cohorts
  )
  print(counts)

  cm_data <- build_cm_data(
    connection_details = connection_details,
    cohorts_config = cfg$cohorts,
    cm_data_config = cfg$cm_data,
    study_population_config = cfg$study_population,
    connection_config = cfg$connection,
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
    adjusted_population = matching_result$matched_population,
    outcome_model = outcome_model,
    matching_result = matching_result,
    screening_result = ps_fit$screening
  )

  matching_summary <- build_matching_summary(
    study_population = study_population,
    matched_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance
  )

  save_analysis_outputs(
    output_folder = cfg$output$output_folder,
    analysis_summary = analysis_summary,
    matching_summary = matching_summary,
    study_population = study_population,
    adjusted_population = matching_result$matched_population,
    covariate_balance = matching_result$covariate_balance,
    screening_log = ps_fit$screening$screening_log,
    ps_model_coefficients = ps_fit$ps_model_coefficients
  )

  saveRDS(
    list(
      cm_data = cm_data,
      study_population = study_population,
      ps = ps_fit$ps,
      screening = ps_fit$screening,
      adjusted_population = matching_result$matched_population,
      covariate_balance = matching_result$covariate_balance,
      caliper_used = matching_result$caliper_used,
      outcome_model = outcome_model,
      analysis_summary = analysis_summary,
      matching_summary = matching_summary
    ),
    file.path(cfg$output$output_folder, "pipeline_artifacts.rds")
  )

  invisible(
    list(
      cm_data = cm_data,
      study_population = study_population,
      ps = ps_fit$ps,
      screening = ps_fit$screening,
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