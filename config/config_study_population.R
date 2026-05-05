studyPopulationConfig <- list(
  removeDuplicateSubjects = "keep first",
  removeSubjectsWithPriorOutcome = TRUE,
  priorOutcomeLookback = 99999,
  requireTimeAtRisk = TRUE,
  minTimeAtRisk = 1,
  riskWindowStart = 1,
  startAnchor = "cohort start",
  riskWindowEnd = 30,
  endAnchor = "cohort end",
  restrictToCommonPeriod = FALSE,
  firstExposureOnly = TRUE,
  washoutPeriod = 365
)