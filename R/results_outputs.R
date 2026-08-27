# R/results_outputs.R


empty_plot <- function(title_text, body_text) {
  plotly::plot_ly() %>%
    plotly::layout(
      title = title_text,
      xaxis = list(visible = FALSE),
      yaxis = list(visible = FALSE),
      annotations = list(
        list(
          text = body_text,
          x = 0.5,
          y = 0.5,
          showarrow = FALSE
        )
      )
    )
}


safe_read_csv <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }

  readr::read_csv(path, show_col_types = FALSE)
}


get_existing_column <- function(df, candidates) {
  if (is.null(df)) {
    return(NULL)
  }

  cols <- intersect(candidates, names(df))
  if (length(cols) == 0) {
    return(NULL)
  }

  cols[1]
}


simplify_covariate_label <- function(label) {
  label <- as.character(label)
  label <- sub("^.*relative to index:\\s*", "", label)
  label <- trimws(label)

  if (!nzchar(label)) {
    return("Unnamed covariate")
  }

  label
}


build_ps_density_plot <- function(df, title_text) {
  ps_col <- get_existing_column(
    df,
    c("propensityScore", "propensity_score", "ps")
  )
  treatment_col <- get_existing_column(
    df,
    c("treatment", "treatmentGroup", "exposure")
  )

  if (is.null(ps_col) || is.null(treatment_col)) {
    return(empty_plot(
      title_text,
      "Required propensity score columns are not available."
    ))
  }

  df <- df[
    !is.na(df[[ps_col]]) &
      !is.na(df[[treatment_col]]),
    ,
    drop = FALSE
  ]

  treated_scores <- df[[ps_col]][df[[treatment_col]] == 1]
  comparator_scores <- df[[ps_col]][df[[treatment_col]] == 0]

  if (length(treated_scores) < 2 || length(comparator_scores) < 2) {
    return(empty_plot(
      title_text,
      "Both target and comparator groups need at least two propensity scores."
    ))
  }

  density_treated <- density(treated_scores, from = 0, to = 1, na.rm = TRUE)
  density_comparator <- density(comparator_scores, from = 0, to = 1, na.rm = TRUE)

  plotly::plot_ly() %>%
    plotly::add_lines(
      x = density_treated$x,
      y = density_treated$y,
      name = "Target",
      line = list(color = "#1f77b4", width = 2)
    ) %>%
    plotly::add_lines(
      x = density_comparator$x,
      y = density_comparator$y,
      name = "Comparator",
      line = list(color = "#d62728", width = 2)
    ) %>%
    plotly::layout(
      title = title_text,
      xaxis = list(title = "Propensity score", range = c(0, 1)),
      yaxis = list(title = "Density"),
      showlegend = TRUE,
      legend = list(x = 0.72, y = 1)
    )
}


build_smd_plot <- function(df, smd_col, title_text) {
  if (is.null(df) || is.null(smd_col) || !smd_col %in% names(df)) {
    return(empty_plot(
      title_text,
      "Covariate balance output is not available."
    ))
  }

  df <- df[is.finite(df[[smd_col]]), , drop = FALSE]

  if (nrow(df) == 0) {
    return(empty_plot(
      title_text,
      "No finite standardized mean differences available."
    ))
  }

  df$abs_smd <- abs(df[[smd_col]])
  df <- df[order(-df$abs_smd), , drop = FALSE]

  n_show <- min(30, nrow(df))
  df_plot <- df[seq_len(n_show), , drop = FALSE]

  full_labels <- if ("covariateName" %in% names(df_plot)) {
    as.character(df_plot$covariateName)
  } else {
    paste0("Covariate ", seq_len(nrow(df_plot)))
  }

  display_labels <- sub(
    "^.*relative to index:\\s*",
    "",
    full_labels
  )

  display_labels <- trimws(display_labels)

  duplicate_labels <- duplicated(display_labels) |
    duplicated(display_labels, fromLast = TRUE)

  display_labels[duplicate_labels] <- paste0(
    display_labels[duplicate_labels],
    " (",
    seq_along(display_labels[duplicate_labels]),
    ")"
  )

  max_smd <- max(c(0.1, abs(df_plot[[smd_col]]))) * 1.2

  plotly::plot_ly(
    x = df_plot[[smd_col]],
    y = display_labels,
    type = "bar",
    orientation = "h",
    marker = list(
      color = ifelse(df_plot$abs_smd > 0.1, "red", "steelblue"),
      opacity = 0.7
    ),
    text = paste0(
      "<b>", full_labels, "</b>",
      "<br>SMD: ", round(df_plot[[smd_col]], 3)
    ),
    hoverinfo = "text"
  ) %>%
    plotly::layout(
      title = paste0(title_text, " (top ", n_show, " by |SMD|)"),
      xaxis = list(
        title = "Standardized mean difference",
        range = c(-max_smd, max_smd)
      ),
      yaxis = list(
        title = "Covariate",
        automargin = TRUE
      ),
      showlegend = FALSE,
      shapes = list(
        list(
          type = "line",
          x0 = 0.1,
          x1 = 0.1,
          y0 = -0.5,
          y1 = n_show - 0.5,
          line = list(dash = "dash", color = "gray", width = 1)
        ),
        list(
          type = "line",
          x0 = -0.1,
          x1 = -0.1,
          y0 = -0.5,
          y1 = n_show - 0.5,
          line = list(dash = "dash", color = "gray", width = 1)
        )
      )
    )
}


get_final_result_files <- function(output_folder) {
  if (!dir.exists(output_folder)) {
    return(character(0))
  }

  files <- list.files(
    output_folder,
    full.names = FALSE,
    recursive = FALSE
  )

  files <- files[file.info(file.path(output_folder, files))$isdir == FALSE]
  sort(files)
}


register_results_outputs <- function(output, input, session, current_config) {
  get_output_folder <- function() {
    current_config()$output$output_folder
  }

  get_final_csv <- function(name) {
    safe_read_csv(file.path(get_output_folder(), name))
  }

  get_final_result_files <- function() {
    output_folder <- get_output_folder()

    if (!dir.exists(output_folder)) {
      return(character(0))
    }

    files <- list.files(
      output_folder,
      full.names = FALSE,
      recursive = FALSE
    )

    files <- files[
      !file.info(file.path(output_folder, files))$isdir
    ]

    sort(files)
  }

  update_result_file_choices <- function() {
    files <- get_final_result_files()

    updateSelectInput(
      session,
      "result_file_choice",
      choices = stats::setNames(files, files),
      selected = if (length(files) > 0) files[1] else character(0)
    )
  }

  observe({
    get_output_folder()
    update_result_file_choices()
  })

  output$analysis_summary_table <- DT::renderDataTable({
    df <- get_final_csv("analysis_summary.csv")

    if (is.null(df) || nrow(df) == 0) {
      return(data.frame())
    }

    DT::datatable(
      df,
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        dom = "tp"
      ),
      rownames = FALSE,
      class = "table table-striped table-hover"
    )
  })

  output$matching_summary_table <- DT::renderDataTable({
    df <- get_final_csv("matching_summary.csv")

    if (is.null(df) || nrow(df) == 0) {
      return(data.frame())
    }

    DT::datatable(
      df,
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        dom = "tp"
      ),
      rownames = FALSE,
      class = "table table-striped table-hover"
    )
  })

  output$ps_distribution_plot_before <- renderPlotly({
    ps_before_matching <- get_final_csv("ps_before_matching.csv")

    if (is.null(ps_before_matching)) {
      return(empty_plot(
        "Propensity score distribution before matching",
        "Run the analysis to generate propensity score results."
      ))
    }

    build_ps_density_plot(
      ps_before_matching,
      "Propensity score distribution before matching"
    )
  })

  output$ps_distribution_plot_after <- renderPlotly({
    ps_after_matching <- get_final_csv("ps_after_matching.csv")

    if (is.null(ps_after_matching)) {
      return(empty_plot(
        "Propensity score distribution after matching",
        "Run the analysis to generate matched propensity score results."
      ))
    }

    build_ps_density_plot(
      ps_after_matching,
      "Propensity score distribution after matching"
    )
  })

  output$smd_plot_before <- renderPlotly({
    covariate_balance <- get_final_csv("covariate_balance.csv")

    smd_col <- get_existing_column(
      covariate_balance,
      c(
        "beforeMatchingStdDiff",
        "beforeMatchingSmd",
        "unadjustedStdDiff",
        "stdDiffBefore"
      )
    )

    build_smd_plot(
      covariate_balance,
      smd_col,
      "Standardized mean differences before matching"
    )
  })

  output$smd_plot_after <- renderPlotly({
    covariate_balance <- get_final_csv("covariate_balance.csv")

    smd_col <- get_existing_column(
      covariate_balance,
      c(
        "afterMatchingStdDiff",
        "afterMatchingSmd",
        "adjustedStdDiff",
        "stdDiffAfter",
        "asd",
        "asmd"
      )
    )

    build_smd_plot(
      covariate_balance,
      smd_col,
      "Standardized mean differences after matching"
    )
  })

  output$kaplan_meier_ui <- renderUI({
    image_path <- file.path(
      get_output_folder(),
      "kaplan_meier.png"
    )

    if (!file.exists(image_path)) {
      return(tags$p(
        "Kaplan-Meier output is not available. Run the analysis to generate it."
      ))
    }

    tags$img(
      src = paste0(
        "data:image/png;base64,",
        base64enc::base64encode(image_path)
      ),
      style = "width: 100%; height: auto;"
    )
  })

  output$results_files_ui <- renderUI({
    files <- get_final_result_files()

    if (length(files) == 0) {
      return(tags$p("No final result files are available yet."))
    }

    tags$ul(lapply(files, function(file_name) {
      tags$li(tags$code(file_name))
    }))
  })

  output$download_selected_result_file <- downloadHandler(
    filename = function() {
      selected_file <- input$result_file_choice

      if (is.null(selected_file) || !nzchar(selected_file)) {
        return("result_file")
      }

      selected_file
    },
    content = function(file) {
      selected_file <- input$result_file_choice
      source_file <- file.path(get_output_folder(), selected_file)

      if (is.null(selected_file) ||
          !nzchar(selected_file) ||
          !file.exists(source_file)) {
        stop("Selected result file is not available.")
      }

      file.copy(source_file, file, overwrite = TRUE)
    }
  )

  output$download_all_result_files <- downloadHandler(
    filename = function() {
      "ple_analysis_results.zip"
    },
    content = function(file) {
      output_folder <- get_output_folder()
      files <- get_final_result_files()

      if (length(files) == 0) {
        stop("No final result files are available.")
      }

      old_working_directory <- getwd()
      on.exit(setwd(old_working_directory), add = TRUE)

      setwd(output_folder)

      utils::zip(
        zipfile = file,
        files = files
      )
    }
  )

  output$download_summary <- downloadHandler(
    filename = function() {
      "analysis_summary.csv"
    },
    content = function(file) {
      source_file <- file.path(
        get_output_folder(),
        "analysis_summary.csv"
      )

      if (!file.exists(source_file)) {
        stop("Summary file not found. Run the analysis first.")
      }

      file.copy(source_file, file, overwrite = TRUE)
    }
  )
}