# app.R

library(shiny)
library(bslib)
library(DT)
library(readr)
library(plotly)
library(dplyr)
library(DatabaseConnector)
library(CDMConnector)
library(FeatureExtraction)
library(CirceR)

source(file.path("R", "app_helpers.R"))
source(file.path("R", "run_pipeline_shiny.R"))
source(file.path("R", "ui_tabs.R"))
source(file.path("R", "results_outputs.R"))

ui <- navbarPage(
  title = "PLE Shiny App",
  id = "main_nav",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  configuration_tab(),
  advanced_tuning_tab(),
  execution_tab(),
  results_tab()
)

server <- function(input, output, session) {
  log_store <- reactiveVal("Ready.\n")
  run_state <- reactiveVal(FALSE)
  active_connection_info <- reactiveVal(NULL)

  covariate_catalog <- reactiveVal(
    data.frame(
      covariateId = numeric(0),
      covariateName = character(0),
      analysisId = numeric(0),
      conceptId = numeric(0),
      stringsAsFactors = FALSE
    )
  )

  forced_covariate_ids <- reactiveVal(integer(0))
  excluded_covariate_ids <- reactiveVal(integer(0))

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
    demo_source_path = CDMConnector::eunomiaDir(datasetName = "synpuf-110k"),
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

      if (identical(dbms, "")) stop("Database platform is required.")
      if (identical(server, "")) stop("Server is required for a manual connection.")
      if (identical(user, "")) stop("Username is required for a manual connection.")

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

  create_db_connection <- function(connection_info) {
    if (identical(connection_info$connection_mode, "demo")) {
      details <- DatabaseConnector::createConnectionDetails(
        dbms = connection_info$dbms,
        server = connection_info$source_path
      )
    } else {
      details <- DatabaseConnector::createConnectionDetails(
        dbms = connection_info$dbms,
        server = connection_info$server,
        user = connection_info$user,
        password = connection_info$password,
        port = connection_info$port
      )
    }

    DatabaseConnector::connect(details)
  }

  cohort_table_exists <- function(connection, cohort_database_schema, cohort_table) {
    cohort_check_sql <- sprintf(
      paste(
        "SELECT COUNT(*) AS n",
        "FROM information_schema.tables",
        "WHERE lower(table_schema) = lower('%s')",
        "AND lower(table_name) = lower('%s')"
      ),
      cohort_database_schema,
      cohort_table
    )

    cohort_check <- DatabaseConnector::querySql(connection, cohort_check_sql)
    nrow(cohort_check) > 0 && as.numeric(cohort_check[1, 1]) > 0
  }

  ensure_cohort_table_ready <- function(cfg, connection_info) {
    conn <- create_db_connection(connection_info)
    on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

    drop_sql <- sprintf(
      "DROP TABLE IF EXISTS %s.%s",
      cfg$cohorts$cohort_database_schema,
      cfg$cohorts$cohort_table
    )

    append_log("Dropping existing cohort table...")
    DatabaseConnector::executeSql(conn, drop_sql)

    if (!isTRUE(cfg$cohorts$generate_cohorts_from_json)) {
      stop("Cohort generation from JSON is required but is disabled.")
    }

    append_log(
      "Generating cohorts into ",
      cfg$cohorts$cohort_database_schema, ".", cfg$cohorts$cohort_table, " ..."
    )

    connection_details <- create_connection_details(cfg$connection)

    generate_cohorts_if_requested(
      connection_details = connection_details,
      cohorts_config = cfg$cohorts,
      cm_data_config = cfg$cm_data
    )

    append_log(
      "Cohort table generated successfully: ",
      cfg$cohorts$cohort_database_schema, ".", cfg$cohorts$cohort_table
    )

    invisible(TRUE)
  }

  update_covariate_picker_choices <- function() {
    catalog <- covariate_catalog()

    if (is.null(catalog) || nrow(catalog) == 0) {
      return(invisible(NULL))
    }

    choices <- build_covariate_choice_labels(catalog)

    updateSelectizeInput(
      session,
      inputId = "forced_covariates_search",
      choices = choices,
      server = TRUE,
      selected = NULL,
      options = list(
        placeholder = "Search covariates by name or ID",
        create = FALSE,
        maxItems = 1
      )
    )

    updateSelectizeInput(
      session,
      inputId = "excluded_covariates_search",
      choices = choices,
      server = TRUE,
      selected = NULL,
      options = list(
        placeholder = "Search covariates by name or ID",
        create = FALSE,
        maxItems = 1
      )
    )
  }

  add_covariates <- function(target_rv, new_ids) {
    new_ids <- unique(as.numeric(new_ids))
    new_ids <- new_ids[!is.na(new_ids)]
    target_rv(sort(unique(c(target_rv(), new_ids))))
  }

  remove_selected_rows <- function(target_rv, table_input_id) {
    selected_rows <- input[[table_input_id]]
    if (is.null(selected_rows) || length(selected_rows) == 0) {
      return(invisible(NULL))
    }

    current_ids <- target_rv()
    current_table <- build_selected_covariates_table(current_ids, covariate_catalog())

    rows_to_remove <- current_table$covariateId[selected_rows]
    target_rv(setdiff(current_ids, rows_to_remove))
    invisible(rows_to_remove)
  }

  observe({
    refresh_cohort_json_choices()
  })

  observeEvent(covariate_catalog(),
    {
      update_covariate_picker_choices()
    },
    ignoreInit = TRUE,
    ignoreNULL = TRUE
  )

  observeEvent(TRUE,
    {
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
    },
    once = TRUE
  )

  observeEvent(input$initialize_connection, ignoreInit = TRUE, {
    tryCatch(
      {
        connection_info <- initialize_connection()
        append_log("Connection re-initialized.")
        append_log("Connection mode: ", connection_info$connection_mode)
        append_log("DBMS: ", connection_info$dbms)
      },
      error = function(e) {
        append_log("Connection initialization failed: ", conditionMessage(e))
      }
    )
  })

  observeEvent(input$load_covariate_catalog, ignoreInit = TRUE, {
    req(active_connection_info())

    tryCatch(
      {
        append_log("Loading covariate catalog...")

        cfg <- build_config_from_input(
          input = input,
          connection_info = active_connection_info(),
          forced_covariate_ids = forced_covariate_ids(),
          excluded_covariate_ids = excluded_covariate_ids()
        )

        ensure_cohort_table_ready(
          cfg = cfg,
          connection_info = active_connection_info()
        )

        conn <- create_db_connection(active_connection_info())
        on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

        all_cohort_ids <- unique(c(
          cfg$cohorts$target_cohort_id,
          cfg$cohorts$comparator_cohort_id,
          cfg$cohorts$primary_outcome_cohort_id
        ))
        all_cohort_ids <- all_cohort_ids[!is.na(all_cohort_ids)]

        covariate_data <- FeatureExtraction::getDbCovariateData(
          connection = conn,
          cdmDatabaseSchema = cfg$cm_data$cdm_database_schema,
          cohortDatabaseSchema = cfg$cohorts$cohort_database_schema,
          cohortTable = cfg$cohorts$cohort_table,
          cohortIds = all_cohort_ids,
          covariateSettings = cfg$cm_data$covariate_settings
        )

        covariate_ref <- covariate_data$covariateRef

        if (is.null(covariate_ref)) {
          stop("covariateRef is NULL")
        }

        if (!is.data.frame(covariate_ref)) {
          covariate_ref <- as.data.frame(covariate_ref)
        }

        if (!is.data.frame(covariate_ref) || nrow(covariate_ref) == 0) {
          stop("No covariate reference data returned for the selected cohort.")
        }

        catalog <- deduplicate_covariate_catalog(covariate_ref)
        covariate_catalog(catalog)

        append_log("Covariate catalog loaded: ", nrow(catalog), " covariates.")
      },
      error = function(e) {
        append_log("Failed to load covariate catalog: ", conditionMessage(e))
      }
    )
  })

  observeEvent(input$forced_covariates_add, ignoreInit = TRUE, {
    add_covariates(forced_covariate_ids, input$forced_covariates_search)
  })

  observeEvent(input$excluded_covariates_add, ignoreInit = TRUE, {
    add_covariates(excluded_covariate_ids, input$excluded_covariates_search)
  })

  observeEvent(input$forced_covariates_add_same_concept, ignoreInit = TRUE, {
    ids <- expand_covariates_from_concept_id(covariate_catalog(), input$forced_covariates_search)
    add_covariates(forced_covariate_ids, ids)
  })

  observeEvent(input$excluded_covariates_add_same_concept, ignoreInit = TRUE, {
    ids <- expand_covariates_from_concept_id(covariate_catalog(), input$excluded_covariates_search)
    add_covariates(excluded_covariate_ids, ids)
  })

  observeEvent(input$forced_covariates_add_family, ignoreInit = TRUE, {
    req(!is.null(input$forced_covariates_search))
    req(active_connection_info())

    selected_row <- find_covariate_catalog_row(covariate_catalog(), input$forced_covariates_search)
    if (is.null(selected_row)) {
      showNotification("Please select a covariate first.", type = "warning")
      return()
    }

    concept_id <- selected_row$conceptId[[1]]
    if (is.na(concept_id) || is.null(concept_id) || concept_id == 0) {
      showNotification("This covariate has no associated concept ID.", type = "warning")
      return()
    }

    connection_info <- active_connection_info()
    cfg <- build_config_from_input(
      input = input,
      connection_info = connection_info,
      forced_covariate_ids = forced_covariate_ids(),
      excluded_covariate_ids = excluded_covariate_ids()
    )

    conn <- create_db_connection(connection_info)
    on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

    ancestors_raw <- get_concept_ancestors(
      connection = conn,
      concept_id = concept_id,
      cdm_schema = cfg$cm_data$cdm_database_schema
    )

    if (nrow(ancestors_raw) == 0) {
      showNotification("No ancestors found for this concept.", type = "warning")
      return()
    }

    ancestors <- get_ancestor_names_from_catalog(
      catalog_df = covariate_catalog(),
      ancestor_ids = ancestors_raw$ancestor_concept_id
    )
    ancestors$min_levels_of_separation <- ancestors_raw$min_levels_of_separation

    output$forced_covariates_ancestor_selector <- renderUI({
      tagList(
        selectInput(
          "forced_covariates_selected_ancestor",
          "Select ancestor level:",
          choices = setNames(
            ancestors$ancestor_concept_id,
            paste0(
              ifelse(is.na(ancestors$ancestor_concept_name) | ancestors$ancestor_concept_name == "",
                as.character(ancestors$ancestor_concept_id),
                ancestors$ancestor_concept_name
              ),
              " [", ancestors$ancestor_concept_id, "] (",
              ancestors$min_levels_of_separation, " level",
              ifelse(ancestors$min_levels_of_separation > 1, "s", ""), ")"
            )
          ),
          selected = NULL,
          width = "100%"
        ),
        actionButton(
          "forced_covariates_confirm_family",
          "Add this family",
          class = "btn-primary btn-sm",
          style = "margin-top: 10px;"
        )
      )
    })
  })

  observeEvent(input$forced_covariates_confirm_family, {
    req(!is.null(input$forced_covariates_selected_ancestor))

    ancestor_id <- as.numeric(input$forced_covariates_selected_ancestor)

    connection_info <- active_connection_info()
    cfg <- build_config_from_input(
      input = input,
      connection_info = connection_info,
      forced_covariate_ids = forced_covariate_ids(),
      excluded_covariate_ids = excluded_covariate_ids()
    )

    conn <- create_db_connection(connection_info)
    on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

    descendants <- get_all_descendants_of_ancestor(
      connection = conn,
      ancestor_concept_id = ancestor_id,
      cdm_schema = cfg$cm_data$cdm_database_schema
    )

    ids <- expand_covariates_from_descendant_concepts(
      catalog_df = covariate_catalog(),
      selected_covariate_id = input$forced_covariates_search,
      descendant_concept_ids = descendants
    )

    add_covariates(forced_covariate_ids, ids)
    append_log("Forced covariates: added ", length(ids), " covariates from family.")
    showNotification(sprintf("Added %d covariates from family", length(ids)), type = "message")

    output$forced_covariates_ancestor_selector <- renderUI({
      NULL
    })
  })

  observeEvent(input$excluded_covariates_add_family, ignoreInit = TRUE, {
    req(!is.null(input$excluded_covariates_search))
    req(active_connection_info())

    selected_row <- find_covariate_catalog_row(covariate_catalog(), input$excluded_covariates_search)
    if (is.null(selected_row)) {
      showNotification("Please select a covariate first.", type = "warning")
      return()
    }

    concept_id <- selected_row$conceptId[[1]]
    if (is.na(concept_id) || is.null(concept_id) || concept_id == 0) {
      showNotification("This covariate has no associated concept ID.", type = "warning")
      return()
    }

    connection_info <- active_connection_info()
    cfg <- build_config_from_input(
      input = input,
      connection_info = connection_info,
      forced_covariate_ids = forced_covariate_ids(),
      excluded_covariate_ids = excluded_covariate_ids()
    )

    conn <- create_db_connection(connection_info)
    on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

    ancestors_raw <- get_concept_ancestors(
      connection = conn,
      concept_id = concept_id,
      cdm_schema = cfg$cm_data$cdm_database_schema
    )

    if (nrow(ancestors_raw) == 0) {
      showNotification("No ancestors found for this concept.", type = "warning")
      return()
    }

    ancestors <- get_ancestor_names_from_catalog(
      catalog_df = covariate_catalog(),
      ancestor_ids = ancestors_raw$ancestor_concept_id
    )
    ancestors$min_levels_of_separation <- ancestors_raw$min_levels_of_separation

    output$excluded_covariates_ancestor_selector <- renderUI({
      tagList(
        selectInput(
          "excluded_covariates_selected_ancestor",
          "Select ancestor level:",
          choices = setNames(
            ancestors$ancestor_concept_id,
            paste0(
              ifelse(is.na(ancestors$ancestor_concept_name) | ancestors$ancestor_concept_name == "",
                as.character(ancestors$ancestor_concept_id),
                ancestors$ancestor_concept_name
              ),
              " [", ancestors$ancestor_concept_id, "] (",
              ancestors$min_levels_of_separation, " level",
              ifelse(ancestors$min_levels_of_separation > 1, "s", ""), ")"
            )
          ),
          selected = NULL,
          width = "100%"
        ),
        actionButton(
          "excluded_covariates_confirm_family",
          "Add this family",
          class = "btn-primary btn-sm",
          style = "margin-top: 10px;"
        )
      )
    })
  })

  observeEvent(input$excluded_covariates_confirm_family, {
    req(!is.null(input$excluded_covariates_selected_ancestor))

    ancestor_id <- as.numeric(input$excluded_covariates_selected_ancestor)

    connection_info <- active_connection_info()
    cfg <- build_config_from_input(
      input = input,
      connection_info = connection_info,
      forced_covariate_ids = forced_covariate_ids(),
      excluded_covariate_ids = excluded_covariate_ids()
    )

    conn <- create_db_connection(connection_info)
    on.exit(DatabaseConnector::disconnect(conn), add = TRUE)

    descendants <- get_all_descendants_of_ancestor(
      connection = conn,
      ancestor_concept_id = ancestor_id,
      cdm_schema = cfg$cm_data$cdm_database_schema
    )

    ids <- expand_covariates_from_descendant_concepts(
      catalog_df = covariate_catalog(),
      selected_covariate_id = input$excluded_covariates_search,
      descendant_concept_ids = descendants
    )

    add_covariates(excluded_covariate_ids, ids)
    append_log("Excluded covariates: added ", length(ids), " covariates from family.")
    showNotification(sprintf("Added %d covariates from family", length(ids)), type = "message")

    output$excluded_covariates_ancestor_selector <- renderUI({
      NULL
    })
  })

  observeEvent(input$forced_covariates_remove_selected, ignoreInit = TRUE, {
    remove_selected_rows(forced_covariate_ids, "forced_covariates_selected_table_rows_selected")
  })

  observeEvent(input$excluded_covariates_remove_selected, ignoreInit = TRUE, {
    remove_selected_rows(excluded_covariate_ids, "excluded_covariates_selected_table_rows_selected")
  })

  observeEvent(input$forced_covariates_clear, ignoreInit = TRUE, {
    forced_covariate_ids(integer(0))
  })

  observeEvent(input$excluded_covariates_clear, ignoreInit = TRUE, {
    excluded_covariate_ids(integer(0))
  })

  output$forced_covariates_selected_table <- DT::renderDataTable({
    DT::datatable(
      build_selected_covariates_table(forced_covariate_ids(), covariate_catalog()),
      rownames = FALSE,
      selection = "multiple",
      options = list(
        scrollY = "260px",
        scrollX = TRUE,
        paging = FALSE,
        searching = FALSE,
        info = FALSE
      )
    )
  })

  output$excluded_covariates_selected_table <- DT::renderDataTable({
    DT::datatable(
      build_selected_covariates_table(excluded_covariate_ids(), covariate_catalog()),
      rownames = FALSE,
      selection = "multiple",
      options = list(
        scrollY = "260px",
        scrollX = TRUE,
        paging = FALSE,
        searching = FALSE,
        info = FALSE
      )
    )
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

  observeEvent(input$clear_log, ignoreInit = TRUE, {
    log_store("")
  })

  current_config <- reactive({
    req(active_connection_info())

    build_config_from_input(
      input = input,
      connection_info = active_connection_info(),
      forced_covariate_ids = forced_covariate_ids(),
      excluded_covariate_ids = excluded_covariate_ids()
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
        append_log("Forced covariates count: ", length(cfg$covariate_screening$forced_covariate_ids))
        append_log("Excluded covariates count: ", length(cfg$covariate_screening$excluded_covariate_ids))

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

  output$covariate_catalog_status <- renderText({
    n <- nrow(covariate_catalog())
    if (n == 0) {
      "No covariate catalog loaded."
    } else {
      paste("Loaded", n, "covariates.")
    }
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
