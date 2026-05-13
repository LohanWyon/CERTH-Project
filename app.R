library(shiny)
library(bslib)
library(DT)
library(readr)
library(CDMConnector)
library(plotly)

source("R/app_helpers.R")
source("R/run_pipeline_shiny.R")
source("R/default_preset.R")
source("R/ui_tabs.R")
source("R/results_outputs.R")

ui <- navbarPage(
  title = "PLE Shiny App",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  configuration_tab(),
  execution_tab(),
  results_tab()
)

server <- function(input, output, session) {
  log_store <- reactiveVal("Ready.\n")
  run_state <- reactiveVal(FALSE)

  append_log <- function(...) {
    isolate({
      old <- log_store()
      new_line <- paste0(..., collapse = "")
      log_store(paste0(old, new_line, "\n"))
    })
  }

  apply_preset <- function(preset, session) {
    if (!is.list(preset)) {
      return(invisible(NULL))
    }

    if (!is.null(preset$dbms)) updateTextInput(session, "dbms", value = preset$dbms)
    if (!is.null(preset$oracleTempSchema)) updateTextInput(session, "oracleTempSchema", value = preset$oracleTempSchema)

    if (!is.null(preset$cohortDatabaseSchema)) updateTextInput(session, "cohortDatabaseSchema", value = preset$cohortDatabaseSchema)
    if (!is.null(preset$cohortTable)) updateTextInput(session, "cohortTable", value = preset$cohortTable)
    if (!is.null(preset$targetId)) updateNumericInput(session, "targetId", value = preset$targetId)
    if (!is.null(preset$comparatorId)) updateNumericInput(session, "comparatorId", value = preset$comparatorId)
    if (!is.null(preset$outcomeIds)) updateTextInput(session, "outcomeIds", value = preset$outcomeIds)
    if (!is.null(preset$primaryOutcomeId)) updateNumericInput(session, "primaryOutcomeId", value = preset$primaryOutcomeId)
    if (!is.null(preset$targetJsonFile)) updateTextInput(session, "targetJsonFile", value = preset$targetJsonFile)
    if (!is.null(preset$comparatorJsonFile)) updateTextInput(session, "comparatorJsonFile", value = preset$comparatorJsonFile)
    if (!is.null(preset$outcomeJsonFiles)) updateTextInput(session, "outcomeJsonFiles", value = preset$outcomeJsonFiles)

    if (!is.null(preset$cdmDatabaseSchema)) updateTextInput(session, "cdmDatabaseSchema", value = preset$cdmDatabaseSchema)
    if (!is.null(preset$studyStartDate)) updateTextInput(session, "studyStartDate", value = preset$studyStartDate)
    if (!is.null(preset$studyEndDate)) updateTextInput(session, "studyEndDate", value = preset$studyEndDate)

    if (!is.null(preset$firstExposureOnly)) updateCheckboxInput(session, "firstExposureOnly", value = preset$firstExposureOnly)
    if (!is.null(preset$washoutPeriod)) updateNumericInput(session, "washoutPeriod", value = preset$washoutPeriod)
    if (!is.null(preset$removeSubjectsWithPriorOutcome)) updateCheckboxInput(session, "removeSubjectsWithPriorOutcome", value = preset$removeSubjectsWithPriorOutcome)
    if (!is.null(preset$priorOutcomeLookback)) updateNumericInput(session, "priorOutcomeLookback", value = preset$priorOutcomeLookback)
    if (!is.null(preset$riskWindowStart)) updateNumericInput(session, "riskWindowStart", value = preset$riskWindowStart)
    if (!is.null(preset$riskWindowEnd)) updateNumericInput(session, "riskWindowEnd", value = preset$riskWindowEnd)
    if (!is.null(preset$startAnchor)) updateTextInput(session, "startAnchor", value = preset$startAnchor)
    if (!is.null(preset$endAnchor)) updateTextInput(session, "endAnchor", value = preset$endAnchor)
    if (!is.null(preset$removeDuplicateSubjects)) updateSelectInput(session, "removeDuplicateSubjects", selected = preset$removeDuplicateSubjects)
    if (!is.null(preset$restrictToCommonPeriod)) updateCheckboxInput(session, "restrictToCommonPeriod", value = preset$restrictToCommonPeriod)

    if (!is.null(preset$maxCohortSizeForFitting)) updateNumericInput(session, "maxCohortSizeForFitting", value = preset$maxCohortSizeForFitting)
    if (!is.null(preset$psScreening_enabled)) updateCheckboxInput(session, "psScreening_enabled", value = preset$psScreening_enabled)
    if (!is.null(preset$psScreening_sampleSize)) updateNumericInput(session, "psScreening_sampleSize", value = preset$psScreening_sampleSize)
    if (!is.null(preset$psScreening_topCovariates)) updateNumericInput(session, "psScreening_topCovariates", value = preset$psScreening_topCovariates)
    if (!is.null(preset$psScreening_seed)) updateNumericInput(session, "psScreening_seed", value = preset$psScreening_seed)
    if (!is.null(preset$adjustment_method)) updateSelectInput(session, "adjustment_method", selected = preset$adjustment_method)
    if (!is.null(preset$modelType)) updateSelectInput(session, "modelType", selected = preset$modelType)
    if (!is.null(preset$stratified)) updateCheckboxInput(session, "stratified", value = preset$stratified)
    if (!is.null(preset$caliper) && !is.na(preset$caliper)) updateNumericInput(session, "caliper", value = preset$caliper)
    if (!is.null(preset$maxRatio) && !is.na(preset$maxRatio)) updateNumericInput(session, "maxRatio", value = preset$maxRatio)
    if (!is.null(preset$trimFraction) && !is.na(preset$trimFraction)) updateNumericInput(session, "trimFraction", value = preset$trimFraction)
    if (!is.null(preset$outputFolder)) updateTextInput(session, "outputFolder", value = preset$outputFolder)
    if (!is.null(preset$createCohorts)) updateCheckboxInput(session, "createCohorts", value = preset$createCohorts)
    if (!is.null(preset$saveIntermediateRds)) updateCheckboxInput(session, "saveIntermediateRds", value = preset$saveIntermediateRds)
    if (!is.null(preset$verbose)) updateCheckboxInput(session, "verbose", value = preset$verbose)
  }

  source_db_path <- CDMConnector::eunomiaDir()
  duckdb_path <- file.path(
    tempdir(),
    paste0("ple_session_", gsub("[^A-Za-z0-9]", "_", session$token), ".duckdb")
  )

  session$userData$source_db_path <- source_db_path
  session$userData$duckdb_path <- duckdb_path

  initialize_session_db <- function() {
    if (!file.exists(session$userData$source_db_path)) {
      stop("Source Eunomia database not found at: ", session$userData$source_db_path)
    }

    if (file.exists(session$userData$duckdb_path)) {
      unlink(session$userData$duckdb_path, force = TRUE)
    }

    ok <- file.copy(session$userData$source_db_path, session$userData$duckdb_path, overwrite = TRUE)
    if (!isTRUE(ok)) {
      stop("Failed to copy source database to session database.")
    }
  }

  tryCatch(
    {
      initialize_session_db()
      append_log("Session DB initialized from Eunomia.")
    },
    error = function(e) {
      append_log("Session DB initialization failed: ", conditionMessage(e))
    }
  )

  observeEvent(input$load_preset, ignoreInit = TRUE, {
    append_log("Applying built-in preset matching non-Shiny config.")
    apply_preset(defaultPreset, session)
  })

  session$onSessionEnded(function() {
    if (!is.null(session$userData$duckdb_path) && file.exists(session$userData$duckdb_path)) {
      try(unlink(session$userData$duckdb_path, force = TRUE), silent = TRUE)
    }
  })

  current_config <- reactive({
    build_config_from_input(input, duckdb_path = session$userData$duckdb_path)
  })

  observeEvent(input$initialize_session_db, ignoreInit = TRUE, {
    tryCatch(
      {
        initialize_session_db()
        append_log("Session DB re-initialized from Eunomia.")
        append_log("Source DB path: ", session$userData$source_db_path)
        append_log("Session DB path: ", session$userData$duckdb_path)
      },
      error = function(e) {
        append_log("Session DB initialization failed: ", conditionMessage(e))
      }
    )
  })

  observeEvent(input$save_config, ignoreInit = TRUE, {
    cfg <- current_config()
    write_all_config_files(cfg)
    append_log("Configuration files saved.")
    append_log("Source DB path: ", session$userData$source_db_path)
    append_log("Session DB path: ", session$userData$duckdb_path)
  })

  observeEvent(input$run_analysis, ignoreInit = TRUE, {
    run_state(TRUE)

    append_log("Saving configuration before run...")
    cfg <- current_config()
    write_all_config_files(cfg)

    append_log("Launching PLE pipeline...")
    append_log("Source DB path: ", session$userData$source_db_path)
    append_log("Session DB path: ", session$userData$duckdb_path)

    res <- run_pipeline_safe()

    if (isTRUE(res$success)) {
      append_log("Pipeline completed successfully.")
    } else {
      append_log("Pipeline failed: ", res$error)
    }

    run_state(FALSE)
  })

  output$preset_status <- renderText({
    "Built-in preset matches the non-Shiny configuration values."
  })

  output$source_db_path <- renderText({
    paste("Source Eunomia path:", session$userData$source_db_path)
  })

  output$session_db_path <- renderText({
    paste("Session DuckDB path:", session$userData$duckdb_path)
  })

  output$log_output <- renderText({
    log_store()
  })

  register_results_outputs(
    output = output,
    input = input,
    session = session,
    current_config = current_config
  )
}

shinyApp(ui = ui, server = server)