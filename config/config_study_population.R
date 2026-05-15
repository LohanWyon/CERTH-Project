# studyPopulationConfig.R

studyPopulationConfig <-
list(removeDuplicateSubjects = "keep first", removeSubjectsWithPriorOutcome = TRUE, 
    priorOutcomeLookback = 99999L, requireTimeAtRisk = TRUE, 
    minTimeAtRisk = 1, riskWindowStart = 1L, startAnchor = "cohort start", 
    riskWindowEnd = 30L, endAnchor = "cohort end", restrictToCommonPeriod = FALSE, 
    firstExposureOnly = TRUE, washoutPeriod = 365L)