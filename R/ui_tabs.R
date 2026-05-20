# ui_tabs.R

configuration_tab <- function() {
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
                  numericInput("ps_prior", "PS prior variance (unused for matched config)", value = NA, min = 0),
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
  )
}

execution_tab <- function() {
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
            card_header(
              div(
                style = "display: flex; justify-content: space-between; align-items: center; width: 100%;",
                span("Execution logs"),
                actionButton(
                  "clear_logs",
                  "Clear logs",
                  class = "btn btn-outline-secondary btn-sm"
                )
              )
            ),
            card_body(
              verbatimTextOutput("log_output")
            )
          )
        )
      )
    )
  )
}

results_tab <- function() {
  tabPanel(
    "Results",
    fluidPage(
      br(),
      tabsetPanel(
        tabPanel(
          "Summary",
          br(),
          plotlyOutput("population_plot"),
          br(),
          plotlyOutput("effect_plot"),
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
}
