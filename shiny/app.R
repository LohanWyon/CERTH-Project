# shiny/app.R

library(shiny)
library(DT)
library(DatabaseConnector)
library(SqlRender)
library(PatientLevelPrediction)
library(CirceR)

options(sqlRenderTempEmulationSchema = "main")

source("../precheck_plp.R")
source("../config/config_connection.R")
source("../config/config_cohorts.R")
source("../config/config_runtime.R")
source("../config/config_model.R")
source("R/explore_cdm.R")
source("R/build_cohorts.R")

cfg <- function(x, default = NULL) {
    if (exists(x, inherits = TRUE)) get(x, inherits = TRUE) else default
}

project_root <- normalizePath(file.path(getwd(), ".."), winslash = "/", mustWork = TRUE)

default_target_json <- NULL
default_outcome_json <- NULL

target_json_path <- file.path(project_root, "cohorts", "target.json")
outcome_json_path <- file.path(project_root, "cohorts", "outcome.json")

if (file.exists(target_json_path)) {
    default_target_json <- paste(readLines(target_json_path, warn = FALSE), collapse = "\n")
}

if (file.exists(outcome_json_path)) {
    default_outcome_json <- paste(readLines(outcome_json_path, warn = FALSE), collapse = "\n")
}

ui <- navbarPage(
    title = "CERTH PLP Shiny",
    tabPanel(
        "Cohorts",
        sidebarLayout(
            sidebarPanel(
                h3("Database connection"),
                textInput("dbms", "DBMS", value = cfg("dbms", "duckdb")),
                textInput("server", "Server", value = cfg("server", "main")),
                textInput("cdmSchema", "CDM schema", value = cfg("cdmDatabaseSchema", "main")),
                textInput("cohortSchema", "Cohort schema", value = cfg("cohortDatabaseSchema", "main")),
                textInput("cohortTable", "Cohort table", value = cfg("cohortTable", "cohort")),
                actionButton("testConn", "Test connection"),
                br(), br(),
                verbatimTextOutput("connStatus")
            ),
            mainPanel(
                tabsetPanel(
                    tabPanel(
                        "Explore DB",
                        h3("Top conditions"),
                        DT::DTOutput("topConditions"),
                        br(),
                        h3("Top drugs"),
                        DT::DTOutput("topDrugs")
                    ),
                    tabPanel(
                        "Target cohort",
                        h3("Define Target cohort"),
                        uiOutput("targetCohortUI"),
                        br(),
                        verbatimTextOutput("targetPreview")
                    ),
                    tabPanel(
                        "Outcome cohort",
                        h3("Define Outcome cohort"),
                        uiOutput("outcomeCohortUI"),
                        br(),
                        verbatimTextOutput("outcomePreview")
                    ),
                    tabPanel(
                        "Summary",
                        h3("Cohort counts"),
                        tableOutput("cohortCountsSummary")
                    )
                )
            )
        )
    ),
    tabPanel(
        "Training",
        sidebarLayout(
            sidebarPanel(
                numericInput("targetId", "Target cohort ID", value = cfg("targetCohortId", 1), min = 1),
                textInput("targetName", "Target cohort name", value = cfg("targetCohortName", "Target cohort")),
                numericInput("outcomeId", "Outcome cohort ID", value = cfg("outcomeCohortId", 2), min = 1),
                textInput("outcomeName", "Outcome cohort name", value = cfg("outcomeCohortName", "Outcome cohort")),
                hr(),
                textInput("outputFolder", "Output folder", value = cfg("outputFolder", "output/plp_run")),
                numericInput("sampleSizePlp", "Sample size", value = cfg("sampleSizePlp", 1000), min = 1),
                textInput("analysisId", "Analysis ID", value = as.character(cfg("analysisId", 1))),
                textInput("analysisName", "Analysis name", value = cfg("analysisName", "PLP analysis")),
                actionButton("runPlp", "Run PLP"),
                br(), br(),
                verbatimTextOutput("trainStatus")
            ),
            mainPanel(
                h3("Training progress"),
                textOutput("trainProgress")
            )
        )
    ),
    tabPanel(
        "Results",
        h3("PLP Results"),
        verbatimTextOutput("resultsSummary")
    )
)

server <- function(input, output, session) {
    connDetails <- reactiveVal(NULL)

    observeEvent(input$testConn, {
        tryCatch(
            {
                cd <- DatabaseConnector::createConnectionDetails(
                    dbms   = input$dbms,
                    server = input$server
                )

                conn <- DatabaseConnector::connect(cd)
                on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

                DatabaseConnector::querySql(conn, "SELECT 1;")
                connDetails(cd)

                output$connStatus <- renderText("Connection OK")
            },
            error = function(e) {
                output$connStatus <- renderText(paste("Connection error:", e$message))
            }
        )
    })

    # ---------------------------
    # Exploration
    # ---------------------------
    output$topConditions <- DT::renderDT({
        req(connDetails())
        explore_top_conditions(connDetails(), input$cdmSchema)
    })

    output$topDrugs <- DT::renderDT({
        req(connDetails())
        explore_top_drugs(connDetails(), input$cdmSchema)
    })

    # ---------------------------
    # Cohort UIs
    # ---------------------------
    output$targetCohortUI <- renderUI({
        mode <- input$targetDefinitionMode
        if (is.null(mode) || length(mode) == 0) {
            mode <- "UI builder"
        }

        tagList(
            radioButtons(
                "targetDefinitionMode",
                "Definition mode",
                choices = c("UI builder", "JSON paste"),
                selected = mode,
                inline = TRUE
            ),
            if (identical(mode, "JSON paste")) {
                tagList(
                    textAreaInput(
                        "targetJson",
                        "Target cohort JSON",
                        value = if (!is.null(default_target_json)) default_target_json else "",
                        rows = 18,
                        width = "100%"
                    ),
                    actionButton("target_create_json", "Create / preview cohort from JSON")
                )
            } else {
                cohort_definition_ui("target")
            }
        )
    })

    output$outcomeCohortUI <- renderUI({
        mode <- input$outcomeDefinitionMode
        if (is.null(mode) || length(mode) == 0) {
            mode <- "UI builder"
        }

        tagList(
            radioButtons(
                "outcomeDefinitionMode",
                "Definition mode",
                choices = c("UI builder", "JSON paste"),
                selected = mode,
                inline = TRUE
            ),
            if (identical(mode, "JSON paste")) {
                tagList(
                    textAreaInput(
                        "outcomeJson",
                        "Outcome cohort JSON",
                        value = if (!is.null(default_outcome_json)) default_outcome_json else "",
                        rows = 18,
                        width = "100%"
                    ),
                    actionButton("outcome_create_json", "Create / preview cohort from JSON")
                )
            } else {
                cohort_definition_ui("outcome")
            }
        )
    })

    # ---------------------------
    # Target cohort action
    # ---------------------------
    observeEvent(input$target_create, ignoreInit = TRUE, {
        req(connDetails())
        req(!is.null(input$target_conceptId))
        req(!is.na(input$target_conceptId))

        tryCatch(
            {
                res <- build_and_preview_cohort_v2(
                    connDetails          = connDetails(),
                    cdmDatabaseSchema    = input$cdmSchema,
                    cohortDatabaseSchema = input$cohortSchema,
                    cohortTable          = input$cohortTable,
                    cohortId             = input$targetId,
                    indexType            = input$target_type,
                    indexConceptId       = input$target_conceptId,
                    priorObsDays         = input$target_priorObsDays,
                    criteria             = list()
                )

                output$targetPreview <- renderPrint({
                    if (is.null(res)) {
                        cat("No target cohort created yet.\n")
                    } else {
                        print(res)
                    }
                })
            },
            error = function(e) {
                output$targetPreview <- renderPrint({
                    cat("Error while creating target cohort:\n")
                    cat(e$message, "\n")
                })
            }
        )
    })

    observeEvent(input$target_create_json, ignoreInit = TRUE, {
        req(connDetails())
        req(input$targetJson)
        req(nzchar(trimws(input$targetJson)))

        tryCatch(
            {
                res <- build_and_preview_cohort_from_json(
                    connDetails = connDetails(),
                    cdmDatabaseSchema = input$cdmSchema,
                    cohortDatabaseSchema = input$cohortSchema,
                    cohortTable = input$cohortTable,
                    cohortId = input$targetId,
                    jsonText = input$targetJson
                )

                output$targetPreview <- renderPrint({
                    if (is.null(res)) {
                        cat("No target cohort created from JSON.\n")
                    } else {
                        print(res)
                    }
                })
            },
            error = function(e) {
                output$targetPreview <- renderPrint({
                    cat("Error while creating target cohort from JSON:\n")
                    cat(e$message, "\n")
                })
            }
        )
    })

    # ---------------------------
    # Outcome cohort action
    # ---------------------------
    observeEvent(input$outcome_create, ignoreInit = TRUE, {
        req(connDetails())
        req(!is.null(input$outcome_conceptId))
        req(!is.na(input$outcome_conceptId))

        tryCatch(
            {
                res <- build_and_preview_cohort_v2(
                    connDetails          = connDetails(),
                    cdmDatabaseSchema    = input$cdmSchema,
                    cohortDatabaseSchema = input$cohortSchema,
                    cohortTable          = input$cohortTable,
                    cohortId             = input$outcomeId,
                    indexType            = input$outcome_type,
                    indexConceptId       = input$outcome_conceptId,
                    priorObsDays         = input$outcome_priorObsDays,
                    criteria             = list()
                )

                output$outcomePreview <- renderPrint({
                    if (is.null(res)) {
                        cat("No outcome cohort created yet.\n")
                    } else {
                        print(res)
                    }
                })
            },
            error = function(e) {
                output$outcomePreview <- renderPrint({
                    cat("Error while creating outcome cohort:\n")
                    cat(e$message, "\n")
                })
            }
        )
    })

    observeEvent(input$outcome_create_json, ignoreInit = TRUE, {
        req(connDetails())
        req(input$outcomeJson)
        req(nzchar(trimws(input$outcomeJson)))

        tryCatch(
            {
                res <- build_and_preview_cohort_from_json(
                    connDetails = connDetails(),
                    cdmDatabaseSchema = input$cdmSchema,
                    cohortDatabaseSchema = input$cohortSchema,
                    cohortTable = input$cohortTable,
                    cohortId = input$outcomeId,
                    jsonText = input$outcomeJson
                )

                output$outcomePreview <- renderPrint({
                    if (is.null(res)) {
                        cat("No outcome cohort created from JSON.\n")
                    } else {
                        print(res)
                    }
                })
            },
            error = function(e) {
                output$outcomePreview <- renderPrint({
                    cat("Error while creating outcome cohort from JSON:\n")
                    cat(e$message, "\n")
                })
            }
        )
    })

    # ---------------------------
    # Summary
    # ---------------------------
    output$cohortCountsSummary <- renderTable({
        req(connDetails())

        summarize_cohort_counts(
            connectionDetails    = connDetails(),
            cohortDatabaseSchema = input$cohortSchema,
            cohortTable          = input$cohortTable,
            targetId             = input$targetId,
            outcomeId            = input$outcomeId
        )
    })

        # ---------------------------
    # Training
    # ---------------------------
    observeEvent(input$runPlp, ignoreInit = TRUE, {
        req(connDetails())

        output$trainStatus   <- renderText("Training started...")
        output$trainProgress <- renderText("Running pipeline...")

        tryCatch({
            app_dir      <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
            project_root <- normalizePath(file.path(app_dir, ".."), winslash = "/", mustWork = TRUE)
            run_script   <- file.path(project_root, "run_plp_from_config.R")

            if (!file.exists(run_script)) {
                stop(paste("run_plp_from_config.R not found at:", run_script))
            }

            # ---------
            # Variables pour le script PLP
            # ---------
            project_root_for_plp <- project_root

            # Connexion / schémas
            dbms                <- input$dbms
            server              <- input$server
            cdmDatabaseSchema   <- input$cdmSchema
            cohortDatabaseSchema<- input$cohortSchema
            cohortTable         <- input$cohortTable

            # Cohortes
            targetCohortId      <- input$targetId
            targetCohortName    <- input$targetName
            outcomeCohortId     <- input$outcomeId
            outcomeCohortName   <- input$outcomeName

            # Fichiers JSON (par défaut ceux du dossier cohorts)
            targetJsonFile      <- file.path(project_root, "cohorts", "target.json")
            outcomeJsonFile     <- file.path(project_root, "cohorts", "outcome.json")

            # Runtime
            outputFolder        <- input$outputFolder
            sampleSizePlp       <- input$sampleSizePlp
            analysisId          <- input$analysisId
            analysisName        <- input$analysisName

            # Autres valeurs de config (tirées de tes config_*.R)
            cdmDatabaseName     <- cfg("cdmDatabaseName", "SynPUF DuckDB")
            tempEmulationSchema <- cfg("tempEmulationSchema", "main")
            outcomeDatabaseSchema <- cfg("outcomeDatabaseSchema", cohortDatabaseSchema)
            outcomeTable        <- cfg("outcomeTable", cohortTable)
            cdmVersion          <- cfg("cdmVersion", "5.3")

            covariateSettings   <- cfg("covariateSettings")
            modelSettings       <- cfg("modelSettings")
            populationSettings  <- cfg("populationSettings")
            splitSettings       <- cfg("splitSettings")

            # Lancer le script dans cet environnement
            source(run_script, local = TRUE)

            output$trainStatus   <- renderText("Training completed")
            output$trainProgress <- renderText("Done")
            output$resultsSummary <- renderPrint({
                cat("PLP run completed.\n")
                cat("Check result folder:\n")
                cat(normalizePath(outputFolder, winslash = "/", mustWork = FALSE), "\n")
            })
        }, error = function(e) {
            output$trainStatus   <- renderText("Training failed")
            output$trainProgress <- renderText(paste("Error:", e$message))
        })
    })
}

shinyApp(ui, server)
