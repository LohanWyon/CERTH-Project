# config/config_model.R
# Model, population, and split settings

# ---------------------------
# Available PLP models
# ---------------------------
availableModels <- list(
  lasso = PatientLevelPrediction::setLassoLogisticRegression,
  randomForest = PatientLevelPrediction::setRandomForest,
  gradientBoosting = PatientLevelPrediction::setGradientBoostingMachine,
  decisionTree = PatientLevelPrediction::setDecisionTree,
  adaBoost = PatientLevelPrediction::setAdaBoost
)

# Selected model
selectedModel <- "lasso"

if (!selectedModel %in% names(availableModels)) {
  stop(
    paste0(
      "Unknown selectedModel: ", selectedModel,
      ". Available models are: ",
      paste(names(availableModels), collapse = ", ")
    )
  )
}

modelSettings <- availableModels[[selectedModel]]()

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