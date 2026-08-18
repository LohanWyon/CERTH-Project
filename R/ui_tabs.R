# R/ui_tabs.R

cohort_json_selector_ui <- function(prefix, label) {
  tagList(
    selectInput(
      inputId = paste0(prefix, "_json_choice"),
      label = paste0(label, " JSON definition"),
      choices = c(
        "Select an existing cohort JSON" = "",
        "Import a new cohort JSON" = "__new__"
      ),
      selected = ""
    ),
    conditionalPanel(
      condition = sprintf("input['%s'] === '__new__'", paste0(prefix, "_json_choice")),
      textInput(
        inputId = paste0(prefix, "_json_name"),
        label = paste0(label, " JSON file name"),
        value = ""
      ),
      textAreaInput(
        inputId = paste0(prefix, "_json_text"),
        label = paste0(label, " ATLAS JSON"),
        value = "",
        rows = 12,
        resize = "vertical",
        placeholder = "Paste the exported ATLAS JSON here"
      ),
      actionButton(
        inputId = paste0(prefix, "_save_json"),
        label = paste0("Save ", label, " JSON"),
        class = "btn-secondary"
      ),
      br(), br()
    ),
    helpText("Cohort IDs are assigned automatically by the application.")
  )
}

covariate_picker_ui <- function(prefix, title) {
  card(
    card_header(title),
    card_body(
      div(
        class = "covariate-table-block",
        div(
          class = "covariate-table-title",
          "Selected covariates"
        ),
        div(
          class = "covariate-table-wrap",
          DT::dataTableOutput(paste0(prefix, "_selected_table"))
        )
      ),
      br(),
      div(
        class = "covariate-actions-block",
        div(
          class = "covariate-actions-title",
          "Search and actions"
        ),
        selectizeInput(
          inputId = paste0(prefix, "_search"),
          label = "Search covariates by name or ID",
          choices = NULL,
          selected = NULL,
          multiple = FALSE,
          options = list(
            placeholder = "Type a covariate name or ID",
            maxOptions = 50
          )
        ),
        fluidRow(
          column(
            4,
            actionButton(
              inputId = paste0(prefix, "_add"),
              label = "Add selected",
              class = "btn-secondary w-100"
            )
          ),
          column(
            4,
            actionButton(
              inputId = paste0(prefix, "_add_same_concept"),
              label = "Add same concept ID",
              class = "btn-secondary w-100"
            )
          ),
          column(
            4,
            actionButton(
              inputId = paste0(prefix, "_add_with_subcov"),
              label = "Add grouped variants",
              class = "btn-secondary w-100"
            )
          )
        ),
        br(),
        fluidRow(
          column(
            6,
            actionButton(
              inputId = paste0(prefix, "_remove_selected"),
              label = "Remove selected",
              class = "btn-outline-secondary w-100"
            )
          ),
          column(
            6,
            actionButton(
              inputId = paste0(prefix, "_clear"),
              label = "Clear list",
              class = "btn-outline-danger w-100"
            )
          )
        ),
        br(),
        helpText("Use 'Add same concept ID' to add all covariates sharing the same OMOP concept ID.")
      )
    )
  )
}

configuration_tab <- function() {
  tabPanel(
    title = "Configuration",
    value = "configuration",
    fluidPage(
      tags$head(
        tags$style(HTML("
          .covariate-table-block,
          .covariate-actions-block {
            border: 1px solid #dee2e6;
            border-radius: 0.5rem;
            padding: 0.9rem;
            background-color: #ffffff;
          }

          .covariate-table-title,
          .covariate-actions-title {
            font-weight: 600;
            margin-bottom: 0.75rem;
          }

          .covariate-table-wrap {
            width: 100%;
            overflow-x: auto;
          }

          .covariate-table-wrap .dataTables_wrapper {
            width: 100%;
          }

          .covariate-table-wrap table.dataTable th,
          .covariate-table-wrap table.dataTable td {
            white-space: nowrap;
            vertical-align: top;
          }
        "))
      ),
      br(),
      card(
        card_header("Database connection"),
        card_body(
          fluidRow(
            column(
              6,
              checkboxInput(
                "use_demo_connection",
                "Use demo Eunomia connection",
                value = TRUE
              ),
              conditionalPanel(
                condition = "!input.use_demo_connection",
                selectInput(
                  "dbms",
                  "Database platform",
                  choices = c("postgresql", "sql server", "oracle", "redshift", "duckdb"),
                  selected = "postgresql"
                ),
                textInput("server", "Server", value = ""),
                textInput("port", "Port", value = ""),
                textInput("user", "Username", value = ""),
                passwordInput("password", "Password", value = ""),
                textInput("oracle_temp_schema", "Oracle temp schema", value = "")
              ),
              helpText("Demo mode uses Eunomia with automatic technical defaults.")
            ),
            column(
              6,
              h5("Current connection status"),
              verbatimTextOutput("connection_status"),
              br(),
              h5("Connection details"),
              verbatimTextOutput("source_db_path"),
              verbatimTextOutput("connection_details_text")
            )
          )
        )
      ),
      br(),
      card(
        card_header("Cohort definitions"),
        card_body(
          fluidRow(
            column(
              6,
              textInput(
                "cohort_json_folder",
                "Cohort JSON folder",
                value = "cohorts_json"
              ),
              checkboxInput(
                "generate_cohorts_from_json",
                "Generate cohorts from stored / imported ATLAS JSON definitions",
                value = TRUE
              ),
              helpText("A single shared folder is used for target, comparator, and outcome JSON files.")
            ),
            column(
              6,
              textInput(
                "output_folder",
                "Output folder",
                value = ""
              ),
              helpText("Leave empty to use the default analysis output folder.")
            )
          ),
          br(),
          tags$hr(),
          br(),
          fluidRow(
            column(
              4,
              cohort_json_selector_ui("target", "Target")
            ),
            column(
              4,
              cohort_json_selector_ui("comparator", "Comparator")
            ),
            column(
              4,
              cohort_json_selector_ui("outcome", "Primary outcome")
            )
          ),
          br(),
          textInput(
            "outcome_cohort_ids",
            "Additional outcome cohort IDs (comma-separated, optional)",
            value = ""
          ),
          helpText("Optional. The primary analysis uses the primary outcome cohort above.")
        )
      ),
      br(),
      card(
        card_header("Protocol options"),
        card_body(
          fluidRow(
            column(
              6,
              textInput(
                "study_start_date",
                "Study start date (optional, YYYY-MM-DD)",
                value = ""
              ),
              textInput(
                "study_end_date",
                "Study end date (optional, YYYY-MM-DD)",
                value = ""
              ),
              helpText("Leave empty to use all available data. Core protocol parameters remain fixed in the backend.")
            ),
            column(
              6,
              actionButton(
                "load_covariate_catalog",
                "Load covariate catalog",
                class = "btn-secondary"
              ),
              br(), br(),
              textOutput("covariate_catalog_status")
            )
          ),
          br(),
          fluidRow(
            column(
              6,
              covariate_picker_ui("forced_covariates", "Clinically forced covariates")
            ),
            column(
              6,
              covariate_picker_ui("excluded_covariates", "Excluded artefactual covariates")
            )
          )
        )
      ),
      br(),
      card(
        card_header("Technical settings"),
        card_body(
          fluidRow(
            column(
              4,
              textInput(
                "cdm_database_schema",
                "CDM database schema",
                value = "main"
              )
            ),
            column(
              4,
              textInput(
                "cohort_database_schema",
                "Cohort database schema",
                value = "main"
              )
            ),
            column(
              4,
              textInput(
                "cohort_table",
                "Cohort table",
                value = "cohort"
              )
            )
          ),
          helpText("Automatically prefilled for Eunomia demo. Advanced users may change these values for external databases.")
        )
      )
    )
  )
}

advanced_tuning_tab <- function() {
  tabPanel(
    title = "Advanced tuning",
    value = "advanced_tuning",
    fluidPage(
      br(),
      card(
        card_header("Optional technical adaptation"),
        card_body(
          p("These settings are optional. Default values match the primary protocol and can usually be left unchanged."),
          p("They are intended for technical adaptation to database size, propensity score overlap, model stability, and development or debugging workflows.")
        )
      ),
      br(),
      fluidRow(
        column(
          6,
          card(
            card_header("Pre-screening"),
            card_body(
              checkboxInput(
                "screening_enabled",
                "Enable covariate pre-screening",
                value = TRUE
              ),
              numericInput(
                "screening_number_of_runs",
                "Number of screening runs",
                value = 5,
                min = 1,
                step = 1
              ),
              numericInput(
                "screening_top_covariates_per_run",
                "Top covariates retained per run",
                value = 1000,
                min = 1,
                step = 50
              ),
              numericInput(
                "screening_min_subjects_per_group",
                "Minimum subjects per group for screening",
                value = 500,
                min = 50,
                step = 50
              )
            )
          )
        ),
        column(
          6,
          card(
            card_header("Matching"),
            card_body(
              numericInput(
                "matching_caliper",
                "Initial caliper",
                value = 0.2,
                min = 0.01,
                max = 1,
                step = 0.01
              ),
              checkboxInput(
                "matching_allow_caliper_adaptation",
                "Enable rule-based caliper adaptation",
                value = TRUE
              ),
              numericInput(
                "matching_low_match_rate_threshold",
                "Low match rate threshold",
                value = 0.25,
                min = 0,
                max = 1,
                step = 0.01
              ),
              numericInput(
                "matching_caliper_if_low_match_rate",
                "Caliper if low match rate",
                value = 0.25,
                min = 0.01,
                max = 1,
                step = 0.01
              ),
              numericInput(
                "matching_high_match_rate_threshold",
                "High match rate threshold",
                value = 0.90,
                min = 0,
                max = 1,
                step = 0.01
              ),
              numericInput(
                "matching_poor_balance_threshold",
                "Poor balance threshold",
                value = 0.10,
                min = 0,
                max = 1,
                step = 0.01
              ),
              numericInput(
                "matching_caliper_if_poor_balance",
                "Caliper if poor balance",
                value = 0.15,
                min = 0.01,
                max = 1,
                step = 0.01
              )
            )
          )
        )
      ),
      br(),
      fluidRow(
        column(
          6,
          card(
            card_header("Trimming"),
            card_body(
              checkboxInput(
                "trimming_enabled",
                "Enable propensity score trimming",
                value = FALSE
              ),
              numericInput(
                "trimming_lower_percentile",
                "Lower percentile",
                value = 0.01,
                min = 0,
                max = 0.49,
                step = 0.01
              ),
              numericInput(
                "trimming_upper_percentile",
                "Upper percentile",
                value = 0.99,
                min = 0.51,
                max = 1,
                step = 0.01
              )
            )
          )
        ),
        column(
          6,
          card(
            card_header("Outcome model stability"),
            card_body(
              numericInput(
                "outcome_prior_variance",
                "Outcome prior variance",
                value = 2,
                min = 0.001,
                step = 0.5
              ),
              checkboxInput(
                "outcome_use_cross_validation",
                "Use cross-validation for outcome model",
                value = FALSE
              )
            )
          )
        )
      ),
      br(),
      card(
        card_header("Saved files"),
        card_body(
          checkboxInput(
            "save_dev_files",
            "Save additional development files",
            value = FALSE
          ),
          checkboxInput(
            "save_debug_files",
            "Save additional debug files",
            value = FALSE
          ),
          helpText("Final analysis outputs are always saved automatically. Development and debug files are optional and are written to separate subfolders.")
        )
      )
    )
  )
}

execution_tab <- function() {
  tabPanel(
    title = "Execution",
    value = "execution",
    fluidPage(
      br(),
      fluidRow(
        column(
          4,
          card(
            card_header("Actions"),
            card_body(
              actionButton(
                "initialize_connection",
                "Initialize connection",
                class = "btn-secondary w-100"
              ),
              br(), br(),
              actionButton(
                "run_primary_analysis",
                "Run primary analysis",
                class = "btn-primary w-100"
              ),
              br(), br(),
              downloadButton(
                "download_summary",
                "Download summary",
                class = "w-100"
              )
            )
          )
        ),
        column(
          8,
          card(
            card_header(
              div(
                style = "display: flex; justify-content: space-between; align-items: center; width: 100%;",
                span("Execution log"),
                actionButton(
                  "clear_log",
                  "Clear log",
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
    title = "Results",
    value = "results",
    fluidPage(
      br(),
      tabsetPanel(
        tabPanel(
          "Summary",
          br(),
          tableOutput("analysis_summary_table"),
          br(),
          tableOutput("matching_summary_table")
        ),
        tabPanel(
          "Propensity score",
          br(),
          plotlyOutput("ps_distribution_plot_before"),
          br(),
          plotlyOutput("ps_distribution_plot_after")
        ),
        tabPanel(
          "Covariate balance",
          br(),
          plotlyOutput("smd_plot_before"),
          br(),
          plotlyOutput("smd_plot_after")
        ),
        tabPanel(
          "Outcome diagnostics",
          br(),
          plotlyOutput("kaplan_meier_plot"),
          br(),
          tableOutput("ph_diagnostics_table")
        ),
        tabPanel(
          "Files",
          br(),
          uiOutput("results_files_ui")
        )
      )
    )
  )
}