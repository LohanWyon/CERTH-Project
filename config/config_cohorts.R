# config/config_cohorts.R
# Cohort generation settings

cohortTable <- "cohort"
outcomeTable <- "cohort"

targetCohortId <- 1L
outcomeCohortId <- 2L

targetCohortName <- "Target cohort"
outcomeCohortName <- "Outcome cohort"

targetJsonFile <- file.path(getwd(), "cohorts", "target.json")
outcomeJsonFile <- file.path(getwd(), "cohorts", "outcome.json")

# CohortGenerator options
incremental <- FALSE
generateStats <- FALSE