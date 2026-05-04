# shiny/R/build_cohorts.R

cohort_definition_ui <- function(prefix, n_criteria = 0) {
  ns <- function(id) paste0(prefix, "_", id)

  tagList(
    h4("Index event"),
    selectInput(
      ns("type"),
      "Index type",
      choices = c("Condition", "Drug"),
      selected = "Condition"
    ),
    numericInput(ns("conceptId"), "Index concept ID", value = NA, min = 1),
    numericInput(
      ns("priorObsDays"),
      "Required prior observation days",
      value = 365,
      min = 0
    ),
    hr(),
    h4("Additional criteria"),
    actionButton(ns("addCriterion"), "Add criterion"),
    tags$br(), tags$br(),
    uiOutput(ns("criteriaUI")),
    hr(),
    actionButton(ns("create"), "Create / preview cohort")
  )
}

criterion_row_ui <- function(prefix, id) {
  ns <- function(x) paste0(prefix, "_crit_", id, "_", x)

  fluidRow(
    column(
      width = 2,
      selectInput(
        ns("mode"),
        "Mode",
        choices = c("Inclusion", "Exclusion"),
        selected = "Inclusion"
      )
    ),
    column(
      width = 2,
      selectInput(
        ns("type"),
        "Criterion type",
        choices = c("Age", "Gender", "Condition", "Drug", "Observation"),
        selected = "Age"
      )
    ),
    column(
      width = 2,
      uiOutput(ns("valueUI"))
    ),
    column(
      width = 2,
      numericInput(ns("windowStart"), "Window start", value = -365)
    ),
    column(
      width = 2,
      numericInput(ns("windowEnd"), "Window end", value = 0)
    ),
    column(
      width = 2,
      actionButton(ns("remove"), "Remove")
    )
  )
}

criterion_value_ui <- function(prefix, id, type) {
  ns <- function(x) paste0(prefix, "_crit_", id, "_", x)

  switch(type,
    "Age" = tagList(
      numericInput(ns("minAge"), "Min age", value = NA, min = 0),
      numericInput(ns("maxAge"), "Max age", value = NA, min = 0)
    ),
    "Gender" = selectInput(
      ns("gender"),
      "Gender",
      choices = c("Male", "Female")
    ),
    "Condition" = numericInput(
      ns("conceptId"),
      "Condition concept ID",
      value = NA,
      min = 1
    ),
    "Drug" = numericInput(
      ns("conceptId"),
      "Drug concept ID",
      value = NA,
      min = 1
    ),
    "Observation" = numericInput(
      ns("obsDays"),
      "Observation days",
      value = 365,
      min = 0
    )
  )
}

ensure_cohort_table <- function(connDetails, cohortDatabaseSchema, cohortTable) {
  sql <- "
    CREATE TABLE IF NOT EXISTS @cohort_schema.@cohort_table (
      cohort_definition_id INTEGER,
      subject_id INTEGER,
      cohort_start_date DATE,
      cohort_end_date DATE
    );
  "

  rendered <- SqlRender::render(
    sql,
    cohort_schema = cohortDatabaseSchema,
    cohort_table  = cohortTable
  )
  translated <- SqlRender::translate(rendered, targetDialect = connDetails$dbms)

  conn <- DatabaseConnector::connect(connDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  DatabaseConnector::executeSql(conn, translated)
}

build_index_event_sql <- function(indexType,
                                  cdmSchema,
                                  conceptId,
                                  priorObsDays) {
  if (indexType == "Condition") {
    return(SqlRender::render("
      SELECT
        co.person_id,
        co.condition_start_date AS index_date
      FROM @cdm_schema.condition_occurrence co
      JOIN @cdm_schema.observation_period op
        ON op.person_id = co.person_id
      WHERE co.condition_concept_id = @concept_id
        AND op.observation_period_start_date <= DATEADD(day, -@prior_obs_days, co.condition_start_date)
        AND op.observation_period_end_date >= co.condition_start_date
    ",
      cdm_schema = cdmSchema,
      concept_id = conceptId,
      prior_obs_days = priorObsDays
    ))
  }

  if (indexType == "Drug") {
    return(SqlRender::render("
      SELECT
        de.person_id,
        de.drug_exposure_start_date AS index_date
      FROM @cdm_schema.drug_exposure de
      JOIN @cdm_schema.observation_period op
        ON op.person_id = de.person_id
      WHERE de.drug_concept_id = @concept_id
        AND op.observation_period_start_date <= DATEADD(day, -@prior_obs_days, de.drug_exposure_start_date)
        AND op.observation_period_end_date >= de.drug_exposure_start_date
    ",
      cdm_schema = cdmSchema,
      concept_id = conceptId,
      prior_obs_days = priorObsDays
    ))
  }

  stop("Unsupported index type")
}

build_criterion_sql <- function(criterion, cdmSchema) {
  type <- criterion$type
  mode <- criterion$mode

  if (type == "Age") {
    minAge <- criterion$minAge
    maxAge <- criterion$maxAge

    sql <- "
      SELECT i.person_id
      FROM #index_cohort i
      JOIN @cdm_schema.person p
        ON p.person_id = i.person_id
      WHERE 1 = 1
    "

    if (!is.null(minAge) && !is.na(minAge)) {
      sql <- paste0(sql, "\n AND DATEDIFF(year, MAKEDATE(p.year_of_birth, 1, 1), i.index_date) >= @min_age")
    }
    if (!is.null(maxAge) && !is.na(maxAge)) {
      sql <- paste0(sql, "\n AND DATEDIFF(year, MAKEDATE(p.year_of_birth, 1, 1), i.index_date) <= @max_age")
    }

    return(list(
      sql = SqlRender::render(
        sql,
        cdm_schema = cdmSchema,
        min_age = minAge,
        max_age = maxAge
      ),
      mode = mode
    ))
  }

  if (type == "Gender") {
    genderConceptId <- if (criterion$gender == "Male") 8507 else 8532

    return(list(
      sql = SqlRender::render("
        SELECT i.person_id
        FROM #index_cohort i
        JOIN @cdm_schema.person p
          ON p.person_id = i.person_id
        WHERE p.gender_concept_id = @gender_concept_id
      ",
        cdm_schema = cdmSchema,
        gender_concept_id = genderConceptId
      ),
      mode = mode
    ))
  }

  if (type == "Condition") {
    return(list(
      sql = SqlRender::render("
        SELECT DISTINCT i.person_id
        FROM #index_cohort i
        JOIN @cdm_schema.condition_occurrence co
          ON co.person_id = i.person_id
        WHERE co.condition_concept_id = @concept_id
          AND co.condition_start_date BETWEEN DATEADD(day, @window_start, i.index_date)
                                          AND DATEADD(day, @window_end, i.index_date)
      ",
        cdm_schema = cdmSchema,
        concept_id = criterion$conceptId,
        window_start = criterion$windowStart,
        window_end = criterion$windowEnd
      ),
      mode = mode
    ))
  }

  if (type == "Drug") {
    return(list(
      sql = SqlRender::render("
        SELECT DISTINCT i.person_id
        FROM #index_cohort i
        JOIN @cdm_schema.drug_exposure de
          ON de.person_id = i.person_id
        WHERE de.drug_concept_id = @concept_id
          AND de.drug_exposure_start_date BETWEEN DATEADD(day, @window_start, i.index_date)
                                             AND DATEADD(day, @window_end, i.index_date)
      ",
        cdm_schema = cdmSchema,
        concept_id = criterion$conceptId,
        window_start = criterion$windowStart,
        window_end = criterion$windowEnd
      ),
      mode = mode
    ))
  }

  if (type == "Observation") {
    return(list(
      sql = SqlRender::render("
        SELECT DISTINCT i.person_id
        FROM #index_cohort i
        JOIN @cdm_schema.observation_period op
          ON op.person_id = i.person_id
        WHERE op.observation_period_start_date <= DATEADD(day, -@obs_days, i.index_date)
          AND op.observation_period_end_date >= i.index_date
      ",
        cdm_schema = cdmSchema,
        obs_days = criterion$obsDays
      ),
      mode = mode
    ))
  }

  stop("Unsupported criterion type")
}

collect_criteria_from_input <- function(input, prefix, criterion_ids) {
  criteria <- list()

  for (id in criterion_ids) {
    type <- input[[paste0(prefix, "_crit_", id, "_type")]]
    mode <- input[[paste0(prefix, "_crit_", id, "_mode")]]

    criterion <- list(
      id = id,
      type = type,
      mode = mode,
      windowStart = input[[paste0(prefix, "_crit_", id, "_windowStart")]],
      windowEnd = input[[paste0(prefix, "_crit_", id, "_windowEnd")]]
    )

    if (type == "Age") {
      criterion$minAge <- input[[paste0(prefix, "_crit_", id, "_minAge")]]
      criterion$maxAge <- input[[paste0(prefix, "_crit_", id, "_maxAge")]]
    }

    if (type == "Gender") {
      criterion$gender <- input[[paste0(prefix, "_crit_", id, "_gender")]]
    }

    if (type %in% c("Condition", "Drug")) {
      criterion$conceptId <- input[[paste0(prefix, "_crit_", id, "_conceptId")]]
    }

    if (type == "Observation") {
      criterion$obsDays <- input[[paste0(prefix, "_crit_", id, "_obsDays")]]
    }

    criteria[[length(criteria) + 1]] <- criterion
  }

  criteria
}

build_and_preview_cohort_v2 <- function(connDetails,
                                        cdmDatabaseSchema,
                                        cohortDatabaseSchema,
                                        cohortTable,
                                        cohortId,
                                        indexType,
                                        indexConceptId,
                                        priorObsDays,
                                        criteria = list()) {
  if (is.null(indexConceptId) || is.na(indexConceptId)) {
    return(NULL)
  }

  ensure_cohort_table(connDetails, cohortDatabaseSchema, cohortTable)

  conn <- DatabaseConnector::connect(connDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  tempSchema <- getOption("sqlRenderTempEmulationSchema", default = cohortDatabaseSchema)

  indexSql <- build_index_event_sql(
    indexType = indexType,
    cdmSchema = cdmDatabaseSchema,
    conceptId = indexConceptId,
    priorObsDays = priorObsDays
  )

  createIndexSql <- paste0("
    DROP TABLE IF EXISTS #index_cohort;

    CREATE TABLE #index_cohort AS
    ", indexSql, ";
  ")

  DatabaseConnector::renderTranslateExecuteSql(
    connection = conn,
    sql = createIndexSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema
  )

  for (crit in criteria) {
    critSqlObj <- build_criterion_sql(crit, cdmDatabaseSchema)

    createCriterionSql <- paste0("
      DROP TABLE IF EXISTS #criterion_match;

      CREATE TABLE #criterion_match AS
      ", critSqlObj$sql, ";
    ")

    DatabaseConnector::renderTranslateExecuteSql(
      connection = conn,
      sql = createCriterionSql,
      dbms = connDetails$dbms,
      tempEmulationSchema = tempSchema
    )

    if (critSqlObj$mode == "Inclusion") {
      filterSql <- "
        DELETE FROM #index_cohort
        WHERE person_id NOT IN (
          SELECT person_id FROM #criterion_match
        );
      "
    } else {
      filterSql <- "
        DELETE FROM #index_cohort
        WHERE person_id IN (
          SELECT person_id FROM #criterion_match
        );
      "
    }

    DatabaseConnector::renderTranslateExecuteSql(
      connection = conn,
      sql = filterSql,
      dbms = connDetails$dbms,
      tempEmulationSchema = tempSchema
    )
  }

  deleteSql <- "
    DELETE FROM @cohort_schema.@cohort_table
    WHERE cohort_definition_id = @cohort_id;
  "

  DatabaseConnector::renderTranslateExecuteSql(
    connection = conn,
    sql = deleteSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema,
    cohort_schema = cohortDatabaseSchema,
    cohort_table = cohortTable,
    cohort_id = cohortId
  )

  insertSql <- "
    INSERT INTO @cohort_schema.@cohort_table (
      cohort_definition_id,
      subject_id,
      cohort_start_date,
      cohort_end_date
    )
    SELECT
      @cohort_id,
      person_id,
      index_date,
      index_date
    FROM #index_cohort;
  "

  DatabaseConnector::renderTranslateExecuteSql(
    connection = conn,
    sql = insertSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema,
    cohort_schema = cohortDatabaseSchema,
    cohort_table = cohortTable,
    cohort_id = cohortId
  )

  previewSql <- "
    SELECT
      COUNT(*) AS cohort_entries,
      COUNT(DISTINCT person_id) AS cohort_subjects
    FROM #index_cohort;
  "

  res <- DatabaseConnector::renderTranslateQuerySql(
    connection = conn,
    sql = previewSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema
  )

  DatabaseConnector::renderTranslateExecuteSql(
    connection = conn,
    sql = "
      DROP TABLE IF EXISTS #criterion_match;
      DROP TABLE IF EXISTS #index_cohort;
    ",
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema
  )

  res
}

build_and_preview_cohort_from_json <- function(connDetails,
                                               cdmDatabaseSchema,
                                               cohortDatabaseSchema,
                                               cohortTable,
                                               cohortId,
                                               jsonText) {
  if (is.null(jsonText) || !nzchar(trimws(jsonText))) {
    return(NULL)
  }

  ensure_cohort_table(connDetails, cohortDatabaseSchema, cohortTable)

  conn <- DatabaseConnector::connect(connDetails)
  on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

  tempSchema <- getOption("sqlRenderTempEmulationSchema", default = cohortDatabaseSchema)

  expression <- CirceR::cohortExpressionFromJson(jsonText)

  options <- CirceR::createGenerateOptions(
    cohortIdFieldName = "cohort_definition_id",
    cohortId = cohortId,
    cdmSchema = cdmDatabaseSchema,
    targetTable = cohortTable,
    resultSchema = cohortDatabaseSchema,
    vocabularySchema = cdmDatabaseSchema,
    generateStats = FALSE
  )

  cohortSql <- CirceR::buildCohortQuery(expression, options)

  deleteSql <- "
    DELETE FROM @cohort_schema.@cohort_table
    WHERE cohort_definition_id = @cohort_id;
  "

  DatabaseConnector::renderTranslateExecuteSql(
    connection = conn,
    sql = deleteSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema,
    cohort_schema = cohortDatabaseSchema,
    cohort_table = cohortTable,
    cohort_id = cohortId
  )

  DatabaseConnector::renderTranslateExecuteSql(
    connection = conn,
    sql = cohortSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema
  )

  previewSql <- "
    SELECT
      COUNT(*) AS cohort_entries,
      COUNT(DISTINCT subject_id) AS cohort_subjects
    FROM @cohort_schema.@cohort_table
    WHERE cohort_definition_id = @cohort_id;
  "

  DatabaseConnector::renderTranslateQuerySql(
    connection = conn,
    sql = previewSql,
    dbms = connDetails$dbms,
    tempEmulationSchema = tempSchema,
    cohort_schema = cohortDatabaseSchema,
    cohort_table = cohortTable,
    cohort_id = cohortId
  )
}
