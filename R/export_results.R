export_results <- function(outputFolder,
                           outcomeModel,
                           ps,
                           adjustedPopulation,
                           runtimeConfig) {

  if (isTRUE(runtimeConfig$verbose)) {
    message("Exporting results...")
  }

  # Si aucun sujet -> on enregistre juste un message et on sort
  if (is.null(outcomeModel) ||
      is.null(outcomeModel$rr) ||
      length(outcomeModel$rr) == 0) {

    message("No subjects in adjusted population; no outcome model results to export.")
    # Tu peux soit écrire un petit fichier texte:
    # writeLines("No subjects in adjusted population; no outcome model.", file.path(outputFolder, "outcome_summary.txt"))
    return(invisible(NULL))
  }

  # ici seulement tu construis ton data.frame
  resultsDf <- data.frame(
    rr       = outcomeModel$rr,
    ci95Lower = outcomeModel$ci95Lb,
    ci95Upper = outcomeModel$ci95Ub
  )

  # ... suite de ton export (write_csv, etc.)
}