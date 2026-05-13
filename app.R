library(shiny)
library(bslib)
library(DT)
library(readr)
library(CDMConnector)

source("R/app_helpers.R")
source("R/run_pipeline_shiny.R")

ui <- navbarPage(
  title = "PLE Shiny App",
  theme = bs_theme(version = 5, bootswatch = "flatly"),

  tabPanel(
    "Configuration",
    fluidPage(
      br(),
      fluidRow(
        column(
          12,
          card(
            card_header("Preset"),
            card_body(
              actionButton("load_preset", "Load preset", class = "btn-secondary"),
              br(), br(),
              textOutput("preset_status")
            )
          )
        )
      ),
      br(),
      card(
        card_header("Study configuration"),
        card_body(
          tabsetPanel(
            id = "config_tabs",

            tabPanel(
              "Connection",
              br(),
              fluidRow(
                column(
                  6,
                  h5("Session database"),
                  verbatimTextOutput("session_db_path"),
                  verbatimTextOutput("source_db_path")
                ),
                column(
                  6,
                  h5("Connection settings"),
                  textInput("dbms", "DBMS", value = "duckdb"),
                  textInput("oracleTempSchema", "Oracle temp schema", value = "")
                )
              )
            ),

            tabPanel(
              "Cohorts",
              br(),
              fluidRow(
                column(
                  6,
                  textInput("cohortDatabaseSchema", "Cohort schema", value = ""),
                  textInput("cohortTable", "Cohort table", value = ""),
                  numericInput("targetId", "Target ID", value = NA, min = 1),
                  numericInput("comparatorId", "Comparator ID", value = NA, min = 1)
                ),
                column(
                  6,
                  textInput("outcomeIds", "Outcome IDs (comma-separated)", value = ""),
                  numericInput("primaryOutcomeId", "Primary outcome ID", value = NA, min = 1),
                  textInput("targetJsonFile", "Target JSON", value = ""),
                  textInput("comparatorJsonFile", "Comparator JSON", value = ""),
                  textInput("outcomeJsonFiles", "Outcome JSON files (comma-separated)", value = "")
                )
              )
            ),

            tabPanel(
              "CM data",
              br(),
              fluidRow(
                column(
                  6,
                  textInput("cdmDatabaseSchema", "CDM schema", value = ""),
                  textInput("studyStartDate", "Study start date", value = "")
                ),
                column(
                  6,
                  textInput("studyEndDate", "Study end date", value = "")
                )
              )
            ),

            tabPanel(
              "Study population",
              br(),
              fluidRow(
                column(
                  6,
                  checkboxInput("firstExposureOnly", "First exposure only", value = FALSE),
                  numericInput("washoutPeriod", "Washout period", value = NA, min = 0),
                  checkboxInput("removeSubjectsWithPriorOutcome", "Remove subjects with prior outcome", value = FALSE),
                  numericInput("priorOutcomeLookback", "Prior outcome lookback", value = NA, min = 0),
                  numericInput("riskWindowStart", "Risk window start", value = NA)
                ),
                column(
                  6,
                  numericInput("riskWindowEnd", "Risk window end", value = NA),
                  textInput("startAnchor", "Start anchor", value = ""),
                  textInput("endAnchor", "End anchor", value = ""),
                  selectInput(
                    "removeDuplicateSubjects",
                    "Remove duplicate subjects",
                    choices = c(
                      "keep all",
                      "keep first, truncate to second",
                      "keep first",
                      "remove all"
                    ),
                    selected = "keep all"
                  ),
                  checkboxInput("restrictToCommonPeriod", "Restrict to common period", value = FALSE)
                )
              )
            ),

            tabPanel(
              "Analysis",
              br(),
              fluidRow(
                column(
                  6,
                  numericInput("ps_prior", "PS prior variance", value = NA, min = 0),
                  numericInput("maxCohortSizeForFitting", "Max cohort size for fitting", value = NA, min = 100),
                  checkboxInput("psScreening_enabled", "Enable PS screening", value = FALSE),
                  numericInput("psScreening_sampleSize", "PS screening sample size", value = NA, min = 100),
                  numericInput("psScreening_topCovariates", "Top covariates", value = NA, min = 1)
                ),
                column(
                  6,
                  numericInput("psScreening_seed", "PS screening seed", value = NA, min = 1),
                  selectInput(
                    "adjustment_method",
                    "Adjustment method",
                    choices = c("stratification", "matching", "trimming"),
                    selected = "stratification"
                  ),
                  numericInput("caliper", "Matching caliper", value = NA, min = 0),
                  numericInput("maxRatio", "Matching max ratio", value = NA, min = 1),
                  numericInput("trimFraction", "Trim fraction", value = NA, min = 0, max = 1, step = 0.01),
                  selectInput(
                    "modelType",
                    "Outcome model",
                    choices = c("cox"),
                    selected = "cox"
                  ),
                  checkboxInput("stratified", "Stratified outcome model", value = FALSE)
                )
              )
            ),

            tabPanel(
              "Runtime",
              br(),
              fluidRow(
                column(
                  6,
                  textInput("outputFolder", "Output folder", value = "")
                ),
                column(
                  6,
                  checkboxInput("createCohorts", "Create cohorts", value = FALSE),
                  checkboxInput("saveIntermediateRds", "Save intermediate RDS", value = FALSE),
                  checkboxInput("verbose", "Verbose", value = FALSE)
                )
              )
            )
          )
        )
      )
    )
  ),

  tabPanel(
    "Execution",
    fluidPage(
      br(),
      fluidRow(
        column(
          4,
          card(
            card_header("Actions"),
            card_body(
              actionButton("initialize_session_db", "Initialize session DB", class = "btn-secondary w-100"),
              br(), br(),
              actionButton("save_config", "Save config files", class = "btn-secondary w-100"),
              br(), br(),
              actionButton("run_analysis", "Run analysis", class = "btn-primary w-100"),
              br(), br(),
              downloadButton("download_summary", "Download ple_summary.csv", class = "w-100")
            )
          )
        ),
        column(
          8,
          card(
            card_header("Execution logs"),
            card_body(
              verbatimTextOutput("log_output")
            )
          )
        )
      )
    )
  ),

  tabPanel(
    "Results",
    fluidPage(
      br(),
      tabsetPanel(
        tabPanel(
          "Summary",
          br(),
          tableOutput("summary_table"),
          br(),
          tableOutput("population_table")
        ),
        tabPanel(
          "Files",
          br(),
          uiOutput("files_ui")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  log_store <- reactiveVal("Ready.\n")
  run_state <- reactiveVal(FALSE)

  defaultPreset <- list(
    dbms = "duckdb",
    oracleTempSchema = "",
    cohortDatabaseSchema = "main",
    cohortTable = "cohort",
    targetId = 1,
    comparatorId = 2,
    outcomeIds = "3",
    primaryOutcomeId = 3,
    targetJsonFile = "inst/cohorts/target.json",
    comparatorJsonFile = "inst/cohorts/comparator.json",
    outcomeJsonFiles = "inst/cohorts/outcome.json",
    cdmDatabaseSchema = "main",
    studyStartDate = "",
    studyEndDate = "",
    firstExposureOnly = TRUE,
    washoutPeriod = 183,
    removeSubjectsWithPriorOutcome = TRUE,
    priorOutcomeLookback = 99999,
    riskWindowStart = 1,
    riskWindowEnd = 30,
    startAnchor = "cohort start",
    endAnchor = "cohort start",
    removeDuplicateSubjects = "keep first",
    restrictToCommonPeriod = FALSE,
    ps_prior = 0.01,
    maxCohortSizeForFitting = 250000,
    psScreening_enabled = TRUE,
    psScreening_sampleSize = 10000,
    psScreening_topCovariates = 200,
    psScreening_seed = 123,
    adjustment_method = "stratification",
    caliper = 0.2,
    maxRatio = 1,
    trimFraction = 0.1,
    modelType = "cox",
    stratified = TRUE,
    outputFolder = "results",
    createCohorts = TRUE,
    saveIntermediateRds = TRUE,
    verbose = TRUE
  )

  append_log <- function(...) {
    isolate({
      old <- log_store()
      new_line <- paste0(..., collapse = "")
      log_store(paste0(old, new_line, "\n"))
    })
  }

  apply_preset <- function(preset, session) {
    if (!is.list(preset)) return(invisible(NULL))

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

    if (!is.null(preset$ps_prior)) updateNumericInput(session, "ps_prior", value = preset$ps_prior)
    if (!is.null(preset$maxCohortSizeForFitting)) updateNumericInput(session, "maxCohortSizeForFitting", value = preset$maxCohortSizeForFitting)
    if (!is.null(preset$psScreening_enabled)) updateCheckboxInput(session, "psScreening_enabled", value = preset$psScreening_enabled)
    if (!is.null(preset$psScreening_sampleSize)) updateNumericInput(session, "psScreening_sampleSize", value = preset$psScreening_sampleSize)
    if (!is.null(preset$psScreening_topCovariates)) updateNumericInput(session, "psScreening_topCovariates", value = preset$psScreening_topCovariates)
    if (!is.null(preset$psScreening_seed)) updateNumericInput(session, "psScreening_seed", value = preset$psScreening_seed)
    if (!is.null(preset$adjustment_method)) updateSelectInput(session, "adjustment_method", selected = preset$adjustment_method)
    if (!is.null(preset$caliper)) updateNumericInput(session, "caliper", value = preset$caliper)
    if (!is.null(preset$maxRatio)) updateNumericInput(session, "maxRatio", value = preset$maxRatio)
    if (!is.null(preset$trimFraction)) updateNumericInput(session, "trimFraction", value = preset$trimFraction)
    if (!is.null(preset$modelType)) updateSelectInput(session, "modelType", selected = preset$modelType)
    if (!is.null(preset$stratified)) updateCheckboxInput(session, "stratified", value = preset$stratified)

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
    append_log("Applying built-in default preset.")
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
    "Built-in default preset available. Click 'Load preset' to fill the form."
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

  output$summary_table <- renderTable({
    path <- file.path(current_config()$runtimeConfig$outputFolder, "ple_summary.csv")
    if (file.exists(path)) readr::read_csv(path, show_col_types = FALSE)
  })

  output$population_table <- renderTable({
    path <- file.path(current_config()$runtimeConfig$outputFolder, "population_summary.csv")
    if (file.exists(path)) readr::read_csv(path, show_col_types = FALSE)
  })

  output$files_ui <- renderUI({
    out_dir <- current_config()$runtimeConfig$outputFolder
    if (!dir.exists(out_dir)) {
      return(tags$p("No results folder yet."))
    }
    files <- list.files(out_dir, full.names = FALSE)
    if (length(files) == 0) {
      return(tags$p("Results folder is empty."))
    }
    tagList(lapply(files, tags$p))
  })

  output$download_summary <- downloadHandler(
    filename = function() {
      "ple_summary.csv"
    },
    content = function(file) {
      src <- file.path(current_config()$runtimeConfig$outputFolder, "ple_summary.csv")
      if (file.exists(src)) {
        file.copy(src, file, overwrite = TRUE)
      }
    }
  )
}

shinyApp(ui = ui, server = server)