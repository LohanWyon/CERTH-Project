# config/config_model.R
# Model, population, and split settings

modelSettings <- PatientLevelPrediction::setLassoLogisticRegression()

populationSettings <- PatientLevelPrediction::createStudyPopulationSettings(
  firstExposureOnly = FALSE,
  washoutPeriod = 0,
  removeSubjectsWithPriorOutcome = TRUE,
  priorOutcomeLookback = 9999,
  riskWindowStart = 1,
  riskWindowEnd = 365
)

splitSettings <- PatientLevelPrediction::createDefaultSplitSetting(
  testFraction = 0.25
)