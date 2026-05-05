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

  # Infos de base sur la population ajustée
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

  readr::write_csv(populationSummary, file.path(outputFolder, "population_summary.csv"))

  # Cas 1 : pas de modèle outcome exploitable
  if (is.null(outcomeModel)) {
    statusDf <- data.frame(
      status = "NO_OUTCOME_MODEL_OBJECT",
      rr = NA_real_,
      ci95Lower = NA_real_,
      ci95Upper = NA_real_
    )
    readr::write_csv(statusDf, file.path(outputFolder, "ple_summary.csv"))
    return(invisible(statusDf))
  }

  # Statut du modèle si disponible
  modelStatus <- if ("status" %in% names(outcomeModel)) {
    as.character(outcomeModel$status)
  } else {
    NA_character_
  }

  # Extraction robuste des champs
  rr <- if ("rr" %in% names(outcomeModel) && length(outcomeModel$rr) > 0) outcomeModel$rr else NA_real_
  ci95Lower <- if ("ci95Lb" %in% names(outcomeModel) && length(outcomeModel$ci95Lb) > 0) outcomeModel$ci95Lb else NA_real_
  ci95Upper <- if ("ci95Ub" %in% names(outcomeModel) && length(outcomeModel$ci95Ub) > 0) outcomeModel$ci95Ub else NA_real_
  seLogRr <- if ("seLogRr" %in% names(outcomeModel) && length(outcomeModel$seLogRr) > 0) outcomeModel$seLogRr else NA_real_
  p <- if ("p" %in% names(outcomeModel) && length(outcomeModel$p) > 0) outcomeModel$p else NA_real_

  summaryDf <- data.frame(
    status = modelStatus,
    rr = rr,
    ci95Lower = ci95Lower,
    ci95Upper = ci95Upper,
    seLogRr = seLogRr,
    p = p
  )

  readr::write_csv(summaryDf, file.path(outputFolder, "ple_summary.csv"))

  # Petit fichier texte lisible rapidement
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