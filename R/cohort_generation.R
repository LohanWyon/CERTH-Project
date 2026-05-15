# cohort_generation.R

read_json_text <- function(path) {
  if (is.null(path) || !file.exists(path)) {
    stop("JSON file not found: ", path)
  }
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

generate_cohorts_if_requested <- function(connectionDetails, cohortsConfig, cmDataConfig, runtimeConfig) {
  if (!isTRUE(runtimeConfig$createCohorts)) {
    if (isTRUE(runtimeConfig$verbose)) {
      message("Cohort generation disabled; assuming cohorts already exist.")
    }
    return(invisible(NULL))
  }

  if (isTRUE(runtimeConfig$verbose)) {
    message("Cohort generation enabled.")
    message("Target JSON: ", cohortsConfig$targetJsonFile)
    message("Comparator JSON: ", cohortsConfig$comparatorJsonFile)
    message("Outcome JSON(s): ", paste(cohortsConfig$outcomeJsonFiles, collapse = ", "))
  }

  cohortTableNames <- CohortGenerator::getCohortTableNames(
    cohortTable = cohortsConfig$cohortTable
  )

  if (isTRUE(runtimeConfig$verbose)) {
    message("Creating cohort tables in schema: ", cohortsConfig$cohortDatabaseSchema)
  }

  CohortGenerator::createCohortTables(
    connectionDetails = connectionDetails,
    cohortDatabaseSchema = cohortsConfig$cohortDatabaseSchema,
    cohortTableNames = cohortTableNames,
    incremental = FALSE
  )

  cohortDefinitionSet <- data.frame(
    cohortId = integer(),
    cohortName = character(),
    json = character(),
    sql = character(),
    stringsAsFactors = FALSE
  )

  add_definition <- function(id, name, file) {
    json <- read_json_text(file)
    expr <- CirceR::cohortExpressionFromJson(json)
    sql <- CirceR::buildCohortQuery(
      expr,
      options = CirceR::createGenerateOptions(generateStats = FALSE)
    )
    data.frame(
      cohortId = id,
      cohortName = name,
      json = json,
      sql = sql,
      stringsAsFactors = FALSE
    )
  }

  cohortDefinitionSet <- rbind(
    cohortDefinitionSet,
    add_definition(cohortsConfig$targetId, cohortsConfig$targetName, cohortsConfig$targetJsonFile)
  )

  cohortDefinitionSet <- rbind(
    cohortDefinitionSet,
    add_definition(cohortsConfig$comparatorId, cohortsConfig$comparatorName, cohortsConfig$comparatorJsonFile)
  )

  for (i in seq_along(cohortsConfig$outcomeJsonFiles)) {
    cohortDefinitionSet <- rbind(
      cohortDefinitionSet,
      add_definition(
        cohortsConfig$outcomeIds[i],
        paste0("outcome_", cohortsConfig$outcomeIds[i]),
        cohortsConfig$outcomeJsonFiles[i]
      )
    )
  }

  if (isTRUE(runtimeConfig$verbose)) {
    message("Generating cohort set...")
  }

  CohortGenerator::generateCohortSet(
    connectionDetails = connectionDetails,
    cdmDatabaseSchema = cmDataConfig$cdmDatabaseSchema,
    cohortDatabaseSchema = cohortsConfig$cohortDatabaseSchema,
    cohortTableNames = cohortTableNames,
    cohortDefinitionSet = cohortDefinitionSet
  )

  if (isTRUE(runtimeConfig$verbose)) {
    message("Cohort generation completed.")
  }
}