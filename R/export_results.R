export_results <- function(outputFolder,
                           outcomeModel,
                           ps,
                           adjustedPopulation,
                           runtimeConfig) {

  if (isTRUE(runtimeConfig$verbose)) {
    message("Exporting results...")
  }

  if (!dir.exists(outputFolder)) {
    dir.create(outputFolder, recursive = TRUE, showWarnings = FALSE)
  }

  # Sauvegarde des objets intermédiaires si demandé
  if (isTRUE(runtimeConfig$saveIntermediateRds)) {
    saveRDS(ps, file.path(outputFolder, "ps.rds"))
    saveRDS(adjustedPopulation, file.path(outputFolder, "population.rds"))
    saveRDS(outcomeModel, file.path(outputFolder, "outcome_model.rds"))
  }

  # Résumé de la population ajustée
  populationSummary <- data.frame(
    nRows = if (is.null(adjustedPopulation)) 0 else nrow(adjustedPopulation),
    nTreated = if (!is.null(adjustedPopulation) && "treatment" %in% colnames(adjustedPopulation)) {
      sum(adjustedPopulation$treatment == 1, na.rm = TRUE)
    } else {
      NA_integer_
    },
    nComparator = if (!is.null(adjustedPopulation) && "treatment" %in% colnames(adjustedPopulation)) {
      sum(adjustedPopulation$treatment == 0, na.rm = TRUE)
    } else {
      NA_integer_
    }
  )

  readr::write_csv(populationSummary,
                   file.path(outputFolder, "population_summary.csv"))

  # Cas 1 : pas de modèle outcome exploitable
  if (is.null(outcomeModel)) {
    statusDf <- data.frame(
      status = "NO_OUTCOME_MODEL_OBJECT",
      rr = NA_real_,
      ci95Lower = NA_real_,
      ci95Upper = NA_real_,
      seLogRr = NA_real_,
      p = NA_real_
    )
    readr::write_csv(statusDf, file.path(outputFolder, "ple_summary.csv"))
    return(invisible(statusDf))
  }

  # Statut du modèle
  modelStatus <- if ("outcomeModelStatus" %in% names(outcomeModel)) {
    as.character(outcomeModel$outcomeModelStatus)
  } else if ("status" %in% names(outcomeModel)) {
    as.character(outcomeModel$status)
  } else {
    NA_character_
  }

  # Extraction des estimations depuis outcomeModelTreatmentEstimate
  est <- outcomeModel$outcomeModelTreatmentEstimate

  if (!is.null(est) && nrow(est) >= 1) {
    logRr   <- est$logRr[1]
    logLb95 <- est$logLb95[1]
    logUb95 <- est$logUb95[1]
    seLogRr <- est$seLogRr[1]

    rr        <- exp(logRr)
    ci95Lower <- exp(logLb95)
    ci95Upper <- exp(logUb95)

    # p-value bilatérale approximative
    z <- logRr / seLogRr
    p <- 2 * (1 - pnorm(abs(z)))
  } else {
    rr <- ci95Lower <- ci95Upper <- seLogRr <- p <- NA_real_
  }

  summaryDf <- data.frame(
    status = modelStatus,
    rr = rr,
    ci95Lower = ci95Lower,
    ci95Upper = ci95Upper,
    seLogRr = seLogRr,
    p = p
  )

  readr::write_csv(summaryDf, file.path(outputFolder, "ple_summary.csv"))

  # Version texte lisible rapidement
  summaryLines <- c(
    paste("Status:", ifelse(is.na(modelStatus), "NA", modelStatus)),
    paste("RR:", ifelse(is.na(rr), "NA", format(rr, digits = 4))),
    paste("95% CI lower:", ifelse(is.na(ci95Lower), "NA", format(ci95Lower, digits = 4))),
    paste("95% CI upper:", ifelse(is.na(ci95Upper), "NA", format(ci95Upper, digits = 4))),
    paste("SE(logRR):", ifelse(is.na(seLogRr), "NA", format(seLogRr, digits = 4))),
    paste("p-value:", ifelse(is.na(p), "NA", format(p, digits = 4)))
  )

  writeLines(summaryLines, file.path(outputFolder, "ple_summary.txt"))

  invisible(summaryDf)
}