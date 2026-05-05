cohortsConfig <- list(
  cohortDatabaseSchema = "main",
  cohortTable = "cohort",
  targetId = 1,
  comparatorId = 2,
  outcomeIds = c(3),
  primaryOutcomeId = 3,
  targetName = "target",
  comparatorName = "comparator",
  targetJsonFile = "inst/cohorts/target.json",
  comparatorJsonFile = "inst/cohorts/comparator.json",
  outcomeJsonFiles = c("inst/cohorts/outcome.json")
)