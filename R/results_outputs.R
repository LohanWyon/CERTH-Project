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

safe_read_rds <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  readRDS(path)
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

build_ps_histogram <- function(df, title_text) {
  ps_col <- get_existing_column(df, c("propensityScore", "propensity_score", "ps"))
  treatment_col <- get_existing_column(df, c("treatment", "treatmentGroup", "exposure"))

  if (is.null(ps_col) || is.null(treatment_col)) {
    return(empty_plot(
      title_text,
      "Required propensity score columns are not available in the saved results."
    ))
  }

  plotly::plot_ly(
    data = df,
    x = as.formula(paste0("~`", ps_col, "`")),
    color = as.formula(paste0("~as.factor(`", treatment_col, "`)")),
    type = "histogram",
    opacity = 0.6
  ) %>%
    plotly::layout(
      title = title_text,
      barmode = "overlay",
      xaxis = list(title = "Propensity score"),
      yaxis = list(title = "Count"),
      legend = list(title = list(text = "Treatment"))
    )
}

build_smd_plot <- function(df, smd_col, title_text) {
  if (is.null(df) || is.null(smd_col) || !smd_col %in% names(df)) {
    return(empty_plot(
      title_text,
      "Covariate balance output is not available for this analysis."
    ))
  }

  plot_df <- df
  plot_df <- plot_df[is.finite(plot_df[[smd_col]]), , drop = FALSE]

  if (nrow(plot_df) == 0) {
    return(empty_plot(
      title_text,
      "No finite standardized mean differences are available."
    ))
  }

  plot_df$covariate_index <- seq_len(nrow(plot_df))
  plot_df$abs_smd <- abs(plot_df[[smd_col]])

  plotly::plot_ly(
    data = plot_df,
    x = ~covariate_index,
    y = as.formula(paste0("~`", smd_col, "`")),
    type = "scatter",
    mode = "markers",
    text = ~paste("Abs SMD:", round(abs_smd, 4)),
    hoverinfo = "text+y"
  ) %>%
    plotly::layout(
      title = title_text,
      xaxis = list(title = "Covariates (index)"),
      yaxis = list(title = "Standardized mean difference"),
      shapes = list(
        list(
          type = "line",
          x0 = 0,
          x1 = nrow(plot_df),
          y0 = 0.1,
          y1 = 0.1,
          line = list(dash = "dash", color = "red")
        ),
        list(
          type = "line",
          x0 = 0,
          x1 = nrow(plot_df),
          y0 = -0.1,
          y1 = -0.1,
          line = list(dash = "dash", color = "red")
        )
      )
    )
}

register_results_outputs <- function(output, input, session, current_config) {
  get_output_folder <- function() {
    current_config()$output$output_folder
  }

  get_pipeline_artifacts <- function() {
    safe_read_rds(file.path(get_output_folder(), "pipeline_artifacts.rds"))
  }

  get_covariate_balance <- function() {
    artifacts <- get_pipeline_artifacts()
    if (!is.null(artifacts) && !is.null(artifacts$covariate_balance)) {
      return(artifacts$covariate_balance)
    }
    safe_read_rds(file.path(get_output_folder(), "covariate_balance.rds"))
  }

  output$analysis_summary_table <- renderTable({
    safe_read_csv(file.path(get_output_folder(), "analysis_summary.csv"))
  })

  output$matching_summary_table <- renderTable({
    safe_read_csv(file.path(get_output_folder(), "matching_summary.csv"))
  })

  output$ps_distribution_plot_before <- renderPlotly({
    artifacts <- get_pipeline_artifacts()
    study_population <- NULL

    if (!is.null(artifacts) && !is.null(artifacts$study_population)) {
      study_population <- artifacts$study_population
    } else {
      study_population <- safe_read_rds(file.path(get_output_folder(), "study_population.rds"))
    }

    if (is.null(study_population)) {
      return(empty_plot(
        "PS distribution before matching",
        "Run the analysis to generate the study population and propensity scores."
      ))
    }

    build_ps_histogram(
      df = study_population,
      title_text = "Propensity score distribution before matching"
    )
  })

  output$ps_distribution_plot_after <- renderPlotly({
    artifacts <- get_pipeline_artifacts()
    adjusted_population <- NULL

    if (!is.null(artifacts) && !is.null(artifacts$adjusted_population)) {
      adjusted_population <- artifacts$adjusted_population
    } else {
      adjusted_population <- safe_read_rds(file.path(get_output_folder(), "adjusted_population.rds"))
    }

    if (is.null(adjusted_population)) {
      return(empty_plot(
        "PS distribution after matching",
        "Run the analysis to generate the matched population."
      ))
    }

    build_ps_histogram(
      df = adjusted_population,
      title_text = "Propensity score distribution after matching"
    )
  })

  output$smd_plot_before <- renderPlotly({
    covariate_balance <- get_covariate_balance()

    smd_before_col <- get_existing_column(
      covariate_balance,
      c("beforeMatchingStdDiff", "beforeMatchingSmd", "unadjustedStdDiff", "stdDiffBefore")
    )

    build_smd_plot(
      df = covariate_balance,
      smd_col = smd_before_col,
      title_text = "Standardized mean differences before matching"
    )
  })

  output$smd_plot_after <- renderPlotly({
    covariate_balance <- get_covariate_balance()

    smd_after_col <- get_existing_column(
      covariate_balance,
      c("afterMatchingStdDiff", "afterMatchingSmd", "adjustedStdDiff", "stdDiffAfter", "asd", "asmd")
    )

    build_smd_plot(
      df = covariate_balance,
      smd_col = smd_after_col,
      title_text = "Standardized mean differences after matching"
    )
  })

  output$kaplan_meier_plot <- renderPlotly({
    empty_plot(
      "Kaplan-Meier plot",
      "Future feature: Kaplan-Meier visualization is planned but not yet connected in this Shiny version."
    )
  })

  output$ph_diagnostics_table <- renderTable({
    data.frame(
      diagnostic = "Proportional hazards check",
      status = "Future feature - not yet implemented in current Shiny version",
      stringsAsFactors = FALSE
    )
  })

  output$results_files_ui <- renderUI({
    out_dir <- get_output_folder()

    if (!dir.exists(out_dir)) {
      return(tags$p("No results folder available yet."))
    }

    files <- list.files(out_dir, full.names = FALSE)

    if (length(files) == 0) {
      return(tags$p("Results folder is empty."))
    }

    tagList(
      tags$p("Available result files:"),
      tags$ul(
        lapply(files, function(f) tags$li(f))
      )
    )
  })

  output$download_summary <- downloadHandler(
    filename = function() {
      "analysis_summary.csv"
    },
    content = function(file) {
      src <- file.path(get_output_folder(), "analysis_summary.csv")
      if (!file.exists(src)) {
        stop("Summary file not found. Run the analysis first.")
      }
      file.copy(src, file, overwrite = TRUE)
    }
  )
}