# shiny/R/explore_cdm.R

explore_top_conditions <- function(connectionDetails, cdmDatabaseSchema, n = 50) {
  sql <- "
    SELECT co.condition_concept_id,
           c.concept_name,
           COUNT(DISTINCT co.person_id) AS n_persons
    FROM @cdm_schema.condition_occurrence co
    JOIN @cdm_schema.concept c
      ON c.concept_id = co.condition_concept_id
    GROUP BY co.condition_concept_id, c.concept_name
    ORDER BY n_persons DESC
    LIMIT @n;
  "

  rendered <- SqlRender::render(
    sql,
    cdm_schema = cdmDatabaseSchema,
    n = n
  )
  translated <- SqlRender::translate(rendered, targetDialect = connectionDetails$dbms)

  conn <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  DatabaseConnector::querySql(conn, translated)
}

explore_top_drugs <- function(connectionDetails, cdmDatabaseSchema, n = 50) {
  sql <- "
    SELECT de.drug_concept_id,
           c.concept_name,
           COUNT(DISTINCT de.person_id) AS n_persons
    FROM @cdm_schema.drug_exposure de
    JOIN @cdm_schema.concept c
      ON c.concept_id = de.drug_concept_id
    GROUP BY de.drug_concept_id, c.concept_name
    ORDER BY n_persons DESC
    LIMIT @n;
  "

  rendered <- SqlRender::render(
    sql,
    cdm_schema = cdmDatabaseSchema,
    n = n
  )
  translated <- SqlRender::translate(rendered, targetDialect = connectionDetails$dbms)

  conn <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  DatabaseConnector::querySql(conn, translated)
}

summarize_cohort_counts <- function(connectionDetails,
                                    cohortDatabaseSchema,
                                    cohortTable,
                                    targetId,
                                    outcomeId) {
  ensure_cohort_table(
    connDetails = connectionDetails,
    cohortDatabaseSchema = cohortDatabaseSchema,
    cohortTable = cohortTable
  )

  sql <- "
    SELECT cohort_definition_id,
           COUNT(*) AS cohort_entries,
           COUNT(DISTINCT subject_id) AS cohort_subjects
    FROM @cohort_schema.@cohort_table
    WHERE cohort_definition_id IN (@target_id, @outcome_id)
    GROUP BY cohort_definition_id
    ORDER BY cohort_definition_id;
  "

  rendered <- SqlRender::render(
    sql,
    cohort_schema = cohortDatabaseSchema,
    cohort_table  = cohortTable,
    target_id     = targetId,
    outcome_id    = outcomeId
  )
  translated <- SqlRender::translate(rendered, targetDialect = connectionDetails$dbms)

  conn <- DatabaseConnector::connect(connectionDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  res <- DatabaseConnector::querySql(conn, translated)

  if (nrow(res) == 0) {
    out <- data.frame(
      cohort_definition_id = c(targetId, outcomeId),
      cohort_entries = c(0, 0),
      cohort_subjects = c(0, 0)
    )
  } else {
    all_ids <- data.frame(cohort_definition_id = c(targetId, outcomeId))
    out <- merge(all_ids, res, by = "cohort_definition_id", all.x = TRUE)
    out$cohort_entries[is.na(out$cohort_entries)] <- 0
    out$cohort_subjects[is.na(out$cohort_subjects)] <- 0
  }

  out$role <- ifelse(
    out$cohort_definition_id == targetId,
    "Target",
    "Outcome"
  )

  out <- out[, c("role", "cohort_definition_id", "cohort_entries", "cohort_subjects")]

  rownames(out) <- NULL
  out
}
