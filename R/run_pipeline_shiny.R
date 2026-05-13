run_pipeline_safe <- function() {
  tryCatch(
    {
      source("run_ple_from_config.R", local = new.env(parent = globalenv()))
      list(success = TRUE, error = NULL)
    },
    error = function(e) {
      list(success = FALSE, error = conditionMessage(e))
    }
  )
}