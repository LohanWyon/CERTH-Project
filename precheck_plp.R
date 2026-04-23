# precheck_plp.R
# Generic precheck utilities for the PLP pipeline

precheck_validate_config <- function() {
  # Vérif minimale : objets attendus en global env
  required_vars <- c(
    "dbms", "server",
    "cdmDatabaseSchema",
    "cohortDatabaseSchema", "cohortTable",
    "targetCohortId", "outcomeCohortId",
    "targetJsonFile", "outcomeJsonFile"
  )

  missing <- required_vars[!vapply(required_vars, exists, logical(1))]
  if (length(missing) > 0) {
    stop(
      sprintf(
        "[PRECHECK] Missing required config variables: %s",
        paste(missing, collapse = ", ")
      )
    )
  }

  if (!file.exists(targetJsonFile)) {
    stop(sprintf("[PRECHECK] Target cohort JSON not found: %s", targetJsonFile))
  }
  if (!file.exists(outcomeJsonFile)) {
    stop(sprintf("[PRECHECK] Outcome cohort JSON not found: %s", outcomeJsonFile))
  }

  invisible(TRUE)
}

precheck_test_connection <- function(connectionDetails) {
  message("[PRECHECK] Testing database connection")

  conn <- NULL
  ok <- FALSE

  tryCatch({
    conn <- DatabaseConnector::connect(connectionDetails)
    DatabaseConnector::querySql(conn, "SELECT 1 AS test_value;")
    ok <- TRUE
  }, error = function(e) {
    stop(sprintf("[PRECHECK] Database connection check failed: %s", e$message))
  }, finally = {
    if (!is.null(conn)) {
      DatabaseConnector::disconnect(conn)
    }
  })

  if (!ok) {
    stop("[PRECHECK] Database connection check did not succeed")
  }

  invisible(TRUE)
}

precheck_count_cohorts <- function(connectionDetails,
                                   cohortDatabaseSchema,
                                   cohortTable,
                                   targetCohortId,
                                   outcomeCohortId) {
  message("[PRECHECK] Counting cohort entries and subjects")

  sql <- "
    SELECT cohort_definition_id,
           COUNT(*) AS cohort_entries,
           COUNT(DISTINCT subject_id) AS cohort_subjects
    FROM @cohort_database_schema.@cohort_table
    WHERE cohort_definition_id IN (@target_cohort_id, @outcome_cohort_id)
    GROUP BY cohort_definition_id
    ORDER BY cohort_definition_id;
  "

  renderedSql <- SqlRender::render(
    sql,
    cohort_database_schema = cohortDatabaseSchema,
    cohort_table           = cohortTable,
    target_cohort_id       = targetCohortId,
    outcome_cohort_id      = outcomeCohortId
  )

  translatedSql <- SqlRender::translate(
    renderedSql,
    targetDialect = connectionDetails$dbms
  )

  conn <- NULL
  result <- NULL

  tryCatch({
    conn   <- DatabaseConnector::connect(connectionDetails)
    result <- DatabaseConnector::querySql(conn, translatedSql)
  }, error = function(e) {
    stop(sprintf("[PRECHECK] Cohort count query failed: %s", e$message))
  }, finally = {
    if (!is.null(conn)) {
      DatabaseConnector::disconnect(conn)
    }
  })

  result
}

run_precheck <- function(connectionDetails,
                         minTargetSubjects = 1,
                         minOutcomeSubjects = 1,
                         failOnEmpty = TRUE) {
  # Niveau 1 : validation config + fichiers JSON
  message("[PRECHECK] Level 1: config & JSON files")
  precheck_validate_config()

  # Niveau 1 bis : test de connexion
  precheck_test_connection(connectionDetails)

  # Niveau 2 : comptage des cohortes
  message("[PRECHECK] Level 2: cohort counts in cohort table")
  counts <- precheck_count_cohorts(
    connectionDetails    = connectionDetails,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable          = cohortTable,
    targetCohortId       = targetCohortId,
    outcomeCohortId      = outcomeCohortId
  )

  print(counts)

  get_subjects <- function(id) {
    if (!("cohort_definition_id" %in% names(counts))) return(0L)
    if (!("cohort_subjects" %in% names(counts))) return(0L)
    idx <- which(counts$cohort_definition_id == id)
    if (length(idx) == 0) return(0L)
    as.integer(counts$cohort_subjects[idx[1]])
  }

  n_target  <- get_subjects(targetCohortId)
  n_outcome <- get_subjects(outcomeCohortId)

  message(sprintf(
    "[PRECHECK] Target cohort (%s): %d subjects",
    as.character(targetCohortId), n_target
  ))
  message(sprintf(
    "[PRECHECK] Outcome cohort (%s): %d subjects",
    as.character(outcomeCohortId), n_outcome
  ))

  if (failOnEmpty && n_target < minTargetSubjects) {
    stop(
      sprintf(
        "[PRECHECK] Target cohort below minimum (%d < %d)",
        n_target, minTargetSubjects
      )
    )
  }

  if (failOnEmpty && n_outcome < minOutcomeSubjects) {
    stop(
      sprintf(
        "[PRECHECK] Outcome cohort below minimum (%d < %d)",
        n_outcome, minOutcomeSubjects
      )
    )
  }

  invisible(counts)
}