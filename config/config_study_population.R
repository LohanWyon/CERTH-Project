studyPopulationConfig <-
list(firstExposureOnly = TRUE, washoutPeriod = 183L, removeSubjectsWithPriorOutcome = TRUE, 
    priorOutcomeLookback = 99999L, riskWindowStart = 1L, riskWindowEnd = 30L, 
    startAnchor = "cohort start", endAnchor = "cohort start", 
    removeDuplicateSubjects = "keep first", restrictToCommonPeriod = FALSE)
