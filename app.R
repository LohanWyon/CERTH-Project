# app.R

library(shiny)
library(bslib)
library(DT)
library(readr)
library(plotly)
library(CDMConnector)
library(FeatureExtraction)
library(CirceR)
library(dplyr)

source("R/app_helpers.R", local = TRUE)
source("R/run_pipeline_shiny.R", local = TRUE)
source("R/ui_tabs.R", local = TRUE)
source("R/results_outputs.R", local = TRUE)

ui <- navbarPage(
  title = "PLE Shiny App",
  id = "main_nav",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  configuration_tab(),
  execution_tab(),
  results_tab()
)

server <- function(input, output, session) {
  log_store <- reactiveVal("Ready.\n")
  run_state <- reactiveVal(FALSE)
  active_connection_info <- reactiveVal(NULL)

  append_log <- function(...) {
    isolate({
      previous_log <- log_store()
      new_line <- paste0(..., collapse = "")
      log_store(paste0(previous_log, new_line, "\n"))
    })
  }

  app_defaults <- list(
    use_demo_connection = TRUE,
    demo_dbms = "duckdb",
    demo_source_path = CDMConnector::eunomiaDir(),
    cohort_json_folder = "cohorts_json"
  )

  refresh_cohort_json_choices <- function(selected_target = NULL,
                                          selected_comparator = NULL,
                                          selected_outcome = NULL) {
    folder <- normalize_optional_text(input$cohort_json_folder)
    if (is.null(folder)) {
      folder <- app_defaults$cohort_json_folder
    }

    choices <- list_available_cohort_json_files(folder)

    updateSelectInput(
      session,
      inputId = "target_json_choice",
      choices = choices,
      selected = selected_target %||% isolate(input$target_json_choice)
    )

    updateSelectInput(
      session,
      inputId = "comparator_json_choice",
      choices = choices,
      selected = selected_comparator %||% isolate(input$comparator_json_choice)
    )

    updateSelectInput(
      session,
      inputId = "outcome_json_choice",
      choices = choices,
      selected = selected_outcome %||% isolate(input$outcome_json_choice)
    )
  }

  save_single_cohort_json_from_input <- function(prefix, label) {
    folder <- normalize_optional_text(input$cohort_json_folder)
    if (is.null(folder)) {
      folder <- app_defaults$cohort_json_folder
    }

    choice <- input[[paste0(prefix, "_json_choice")]]

    if (!identical(choice, "__new__")) {
      append_log(label, " JSON: no new file to save.")
      return(invisible(NULL))
    }

    new_name <- input[[paste0(prefix, "_json_name")]]
    new_json_text <- input[[paste0(prefix, "_json_text")]]

    saved_path <- save_cohort_json_file(
      folder = folder,
      file_name = new_name,
      json_text = new_json_text,
      overwrite = FALSE
    )

    saved_file <- basename(saved_path)

    refresh_cohort_json_choices(
      selected_target = if (identical(prefix, "target")) saved_file else isolate(input$target_json_choice),
      selected_comparator = if (identical(prefix, "comparator")) saved_file else isolate(input$comparator_json_choice),
      selected_outcome = if (identical(prefix, "outcome")) saved_file else isolate(input$outcome_json_choice)
    )

    updateTextInput(session, paste0(prefix, "_json_name"), value = "")
    updateTextAreaInput(session, paste0(prefix, "_json_text"), value = "")

    append_log(label, " JSON saved: ", saved_file)
    invisible(saved_path)
  }

  initialize_connection <- function() {
    if (isTRUE(input$use_demo_connection)) {
      demo_source_path <- app_defaults$demo_source_path

      if (!file.exists(demo_source_path)) {
        stop("Demo Eunomia database not found at: ", demo_source_path)
      }

      connection_info <- list(
        connection_mode = "demo",
        dbms = app_defaults$demo_dbms,
        source_label = "Eunomia demo database",
        source_path = demo_source_path,
        server = NA_character_,
        port = NA_character_,
        user = NA_character_,
        password = NA_character_,
        oracle_temp_schema = NA_character_
      )
    } else {
      dbms <- trimws(input$dbms)
      server <- trimws(input$server)
      port <- trimws(input$port)
      user <- trimws(input$user)
      password <- input$password
      oracle_temp_schema <- trimws(input$oracle_temp_schema)

      if (identical(dbms, "")) {
        stop("Database platform is required.")
      }

      if (identical(server, "")) {
        stop("Server is required for a manual connection.")
      }

      if (identical(user, "")) {
        stop("Username is required for a manual connection.")
      }

      connection_info <- list(
        connection_mode = "manual",
        dbms = dbms,
        source_label = "Manual database connection",
        source_path = NA_character_,
        server = server,
        port = if (identical(port, "")) NA_character_ else port,
        user = user,
        password = password,
        oracle_temp_schema = if (identical(oracle_temp_schema, "")) NA_character_ else oracle_temp_schema
      )
    }

    active_connection_info(connection_info)
    session$userData$connection_info <- connection_info
    invisible(connection_info)
  }

  observe({
    refresh_cohort_json_choices()
  })

  observeEvent(input$target_save_json, ignoreInit = TRUE, {
    tryCatch(
      {
        save_single_cohort_json_from_input("target", "Target")
      },
      error = function(e) {
        append_log("Failed to save Target JSON: ", conditionMessage(e))
      }
    )
  })

  observeEvent(input$comparator_save_json, ignoreInit = TRUE, {
    tryCatch(
      {
        save_single_cohort_json_from_input("comparator", "Comparator")
      },
      error = function(e) {
        append_log("Failed to save Comparator JSON: ", conditionMessage(e))
      }
    )
  })

  observeEvent(input$outcome_save_json, ignoreInit = TRUE, {
    tryCatch(
      {
        save_single_cohort_json_from_input("outcome", "Primary outcome")
      },
      error = function(e) {
        append_log("Failed to save Primary outcome JSON: ", conditionMessage(e))
      }
    )
  })

  observeEvent(TRUE, {
    tryCatch(
      {
        connection_info <- initialize_connection()
        append_log("Connection initialized.")
        append_log("Connection mode: ", connection_info$connection_mode)
        append_log("DBMS: ", connection_info$dbms)

        if (identical(connection_info$connection_mode, "demo")) {
          append_log("Demo source path: ", connection_info$source_path)
        } else {
          append_log("Server: ", connection_info$server)
          append_log("Port: ", ifelse(is.na(connection_info$port), "(default)", connection_info$port))
          append_log("User: ", connection_info$user)
        }
      },
      error = function(e) {
        append_log("Connection initialization failed: ", conditionMessage(e))
      }
    )
  }, once = TRUE)

  observeEvent(input$clear_log, ignoreInit = TRUE, {
    log_store("")
  })

  current_config <- reactive({
    req(active_connection_info())

    build_config_from_input(
      input = input,
      connection_info = active_connection_info()
    )
  })

  observeEvent(input$initialize_connection, ignoreInit = TRUE, {
    tryCatch(
      {
        connection_info <- initialize_connection()
        append_log("Connection re-initialized.")
        append_log("Connection mode: ", connection_info$connection_mode)
        append_log("DBMS: ", connection_info$dbms)

        if (identical(connection_info$connection_mode, "demo")) {
          append_log("Demo source path: ", connection_info$source_path)
        } else {
          append_log("Server: ", connection_info$server)
          append_log("Port: ", ifelse(is.na(connection_info$port), "(default)", connection_info$port))
          append_log("User: ", connection_info$user)
        }
      },
      error = function(e) {
        append_log("Connection initialization failed: ", conditionMessage(e))
      }
    )
  })

  observeEvent(input$run_primary_analysis, ignoreInit = TRUE, {
    run_state(TRUE)

    tryCatch(
      {
        cfg <- current_config()

        append_log("Launching primary PLE pipeline...")
        append_log("Target cohort ID: ", cfg$cohorts$target_cohort_id)
        append_log("Comparator cohort ID: ", cfg$cohorts$comparator_cohort_id)
        append_log("Primary outcome cohort ID: ", cfg$cohorts$primary_outcome_cohort_id)

        if (isTRUE(cfg$cohorts$generate_cohorts_from_json)) {
          append_log("Cohort generation from JSON is enabled.")
          append_log("Target JSON: ", cfg$cohorts$target_json_file %||% "(none)")
          append_log("Comparator JSON: ", cfg$cohorts$comparator_json_file %||% "(none)")
          append_log("Primary outcome JSON: ", cfg$cohorts$primary_outcome_json_file %||% "(none)")
        }

        res <- run_pipeline_safe(cfg)

        if (isTRUE(res$success)) {
          append_log("Pipeline completed successfully.")
        } else {
          append_log("Pipeline failed: ", res$error)
        }
      },
      error = function(e) {
        append_log("Pipeline failed before execution: ", conditionMessage(e))
      }
    )

    run_state(FALSE)
  })

  output$connection_status <- renderText({
    connection_info <- active_connection_info()

    if (is.null(connection_info)) {
      return("Connection not initialized.")
    }

    if (identical(connection_info$connection_mode, "demo")) {
      paste(
        "Using demo Eunomia connection",
        sprintf("(DBMS: %s).", connection_info$dbms)
      )
    } else {
      paste(
        "Using manual connection",
        sprintf("(DBMS: %s, server: %s).", connection_info$dbms, connection_info$server)
      )
    }
  })

  output$source_db_path <- renderText({
    connection_info <- active_connection_info()

    if (is.null(connection_info)) {
      return("Source: not available")
    }

    if (identical(connection_info$connection_mode, "demo")) {
      paste("Demo source path:", connection_info$source_path)
    } else {
      "Source: manual database connection"
    }
  })

  output$connection_details_text <- renderText({
    connection_info <- active_connection_info()

    if (is.null(connection_info)) {
      return("Connection details: not available")
    }

    if (identical(connection_info$connection_mode, "demo")) {
      paste("Connection mode:", connection_info$connection_mode)
    } else {
      paste(
        "Connection target:",
        paste0(
          connection_info$dbms,
          " @ ",
          connection_info$server,
          ifelse(is.na(connection_info$port), "", paste0(":", connection_info$port))
        )
      )
    }
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