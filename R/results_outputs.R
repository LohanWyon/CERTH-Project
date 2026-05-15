# results_outputs.R

register_results_outputs <- function(output, input, session, current_config) {
  output$population_plot <- renderPlotly({
    path <- file.path(current_config()$runtimeConfig$outputFolder, "population_summary.csv")

    if (!file.exists(path)) {
      return(plotly::plot_ly() %>%
        plotly::layout(
          title = "Population summary not available yet",
          xaxis = list(visible = FALSE),
          yaxis = list(visible = FALSE),
          annotations = list(
            list(
              text = "Run the analysis to generate population_summary.csv",
              x = 0.5, y = 0.5, showarrow = FALSE
            )
          )
        ))
    }

    df <- readr::read_csv(path, show_col_types = FALSE)

    if (nrow(df) < 1 || !all(c("nTreated", "nComparator") %in% names(df))) {
      return(plotly::plot_ly() %>%
        plotly::layout(
          title = "Population summary file is empty or malformed",
          xaxis = list(visible = FALSE),
          yaxis = list(visible = FALSE),
          annotations = list(
            list(
              text = "Expected columns: nTreated, nComparator",
              x = 0.5, y = 0.5, showarrow = FALSE
            )
          )
        ))
    }

    plotly::plot_ly(
      x = c("Treated", "Comparator"),
      y = c(df$nTreated[1], df$nComparator[1]),
      type = "bar"
    ) %>%
      plotly::layout(
        title = "Study population sizes",
        xaxis = list(title = ""),
        yaxis = list(title = "Patients")
      )
  })

  output$effect_plot <- renderPlotly({
    path <- file.path(current_config()$runtimeConfig$outputFolder, "ple_summary.csv")

    if (!file.exists(path)) {
      return(plotly::plot_ly() %>%
        plotly::layout(
          title = "PLE summary not available yet",
          xaxis = list(visible = FALSE),
          yaxis = list(visible = FALSE),
          annotations = list(
            list(
              text = "Run the analysis to generate ple_summary.csv",
              x = 0.5, y = 0.5, showarrow = FALSE
            )
          )
        ))
    }

    df <- readr::read_csv(path, show_col_types = FALSE)

    needed <- c("rr", "ci95Lower", "ci95Upper")
    if (nrow(df) < 1 || !all(needed %in% names(df))) {
      return(plotly::plot_ly() %>%
        plotly::layout(
          title = "PLE summary file is empty or malformed",
          xaxis = list(visible = FALSE),
          yaxis = list(visible = FALSE),
          annotations = list(
            list(
              text = "Expected columns: rr, ci95Lower, ci95Upper",
              x = 0.5, y = 0.5, showarrow = FALSE
            )
          )
        ))
    }

    plotly::plot_ly(
      x = df$rr,
      y = rep("Effect", nrow(df)),
      type = "scatter",
      mode = "markers",
      error_x = list(
        type = "data",
        symmetric = FALSE,
        array = df$ci95Upper - df$rr,
        arrayminus = df$rr - df$ci95Lower
      )
    ) %>%
      plotly::layout(
        title = "Relative risk with 95% CI",
        xaxis = list(title = "RR"),
        yaxis = list(title = "")
      )
  })

  output$summary_table <- renderTable({
    path <- file.path(current_config()$runtimeConfig$outputFolder, "ple_summary.csv")
    if (file.exists(path)) {
      readr::read_csv(path, show_col_types = FALSE)
    }
  })

  output$population_table <- renderTable({
    path <- file.path(current_config()$runtimeConfig$outputFolder, "population_summary.csv")
    if (file.exists(path)) {
      readr::read_csv(path, show_col_types = FALSE)
    }
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