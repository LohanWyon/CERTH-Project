# PLE Shiny App

This repository contains a Shiny-based interface for running a classical Population-Level Estimation (PLE) study in R with the OHDSI/HADES ecosystem, primarily using the CohortMethod package. The app provides an interactive workflow to configure a study, load a built-in preset, run the analysis, and inspect exported results from a browser-based interface instead of editing configuration files manually. [web:756][web:764]

The current version is designed as a safe and readable starter app for local use and prototyping. It keeps the standard OHDSI comparative cohort workflow, while replacing most direct configuration-file editing with a multi-tab Shiny UI.

## What the app does

The app implements a standard comparative cohort PLE workflow on OMOP CDM data through an interactive interface. The underlying pipeline still follows the usual CohortMethod sequence: create database connection details, optionally create cohorts, build CohortMethod input data, define the study population, fit a propensity score model, apply PS-based adjustment, fit the outcome model, and export a compact summary. 

In practice, the app allows the user to:
- configure the analysis from the **Configuration** tab,
- load a built-in preset with predefined values,
- initialize a session-specific DuckDB copy of the Eunomia example database,
- save configuration files used by the pipeline,
- run the analysis from the **Execution** tab,
- inspect plots, summary tables, and generated files from the **Results** tab.

## Main differences from the original starter

This project is no longer a pure file-based batch starter where the user edits `config/*.R` manually and then runs `source("run_ple_from_config.R")`. It is now a Shiny application with a UI/server architecture, preset loading, session-specific database initialization, and interactive execution controls.

The app still writes configuration objects and uses the same analytical logic underneath, but the primary entry point is the Shiny application rather than direct manual editing of configuration scripts. This makes the workflow more accessible for testing, demonstration, and iterative parameter tuning.

## App structure

A typical project structure is now organized around the Shiny app entry point, helper files under `R/`, configuration scripts, and optional exploration utilities:

```text
ple_shiny_app/
├─ app.R
├─ README.md
├─ run_ple_from_config.R
├─ explore_eunomia.R
├─ setup_java.R
├─ errorReportSql.txt
├─ .lintr
├─ config/
│  ├─ config_connection.R
│  ├─ config_cohorts.R
│  ├─ config_cm_data.R
│  ├─ config_study_population.R
│  ├─ config_analysis.R
│  ├─ config_runtime.R
│  └─ preset_local.R
├─ R/
│  ├─ app_helpers.R
│  ├─ cohort_generation.R
│  ├─ default_preset.R
│  ├─ export_results.R
│  ├─ results_outputs.R
│  ├─ run_pipeline_shiny.R
│  ├─ run_single_cm_analysis.R
│  ├─ ui_tabs.R
│  └─ utils.R
├─ inst/
│  └─ cohorts/
├─ results/
├─ www/
└─ explore/
```

The exact contents may evolve, but the main roles are:

- `app.R` defines the Shiny app, top-level navigation, server logic, preset loading, session database initialization, configuration saving, and pipeline execution.
- `R/ui_tabs.R` defines the main UI tabs and input layout.
- `R/default_preset.R` stores the built-in preset loaded by the **Load preset** button.
- `R/run_pipeline_shiny.R` contains the main analysis runner used by the app.
- `R/run_single_cm_analysis.R` contains the core CohortMethod analysis steps.
- `R/results_outputs.R` defines outputs rendered in the **Results** tab.
- `R/export_results.R` handles compact result export.
- `R/app_helpers.R` and `R/utils.R` contain helper functions used to build, validate, and save configuration objects.
- `R/cohort_generation.R` handles optional cohort creation from ATLAS JSON.
- `config/` contains the generated or editable configuration scripts used by the underlying pipeline, plus local preset definitions.
- `inst/cohorts/` contains cohort JSON definitions.
- `results/` stores exported outputs.
- `www/` is the standard Shiny static assets folder for CSS, JavaScript, or images.
- `explore/` and `explore_eunomia.R` are reserved for exploratory work and are not part of the main Shiny execution flow.

## Main tabs

### Configuration

The **Configuration** tab is the main place where study settings are defined. It contains sub-tabs for connection settings, cohorts, CM data, study population, analysis settings, and runtime options.

The app is intentionally designed so that many fields can remain empty at startup. The built-in preset can then populate the form only when the user explicitly clicks **Load preset**.

### Execution

The **Execution** tab contains the operational controls:
- initialize the session database,
- save the current configuration files,
- run the analysis,
- inspect execution logs,
- download the compact summary output.

Each session uses its own temporary DuckDB copy of the source Eunomia database, which helps keep runs isolated during local testing.

### Results

The **Results** tab displays generated outputs such as:
- population plots,
- effect plots,
- summary tables,
- exported result files.

This tab is intended as a lightweight viewer for the main outputs of a single run, not as a full diagnostics dashboard.

## Preset behavior

The app includes a built-in preset defined in `R/default_preset.R`. This preset is applied only when the user clicks the **Load preset** button. It is not automatically injected into the UI at startup. This design keeps the initial interface mostly empty while still allowing fast loading of a recommended configuration.

In other words:
- **UI defaults** control what is visible when the app starts,
- **preset values** control what is loaded after the user explicitly requests the default configuration. 

## Analysis workflow

The analytical workflow remains close to the original PLE starter:

1. Create database connection details.
2. Optionally generate cohorts from ATLAS JSON.
3. Build CohortMethod data from the OMOP CDM and cohort table.
4. Create the study population.
5. Fit a large-scale propensity score model, with optional PS screening.
6. Apply PS-based adjustment using matching, stratification, or trimming.
7. Fit the outcome model, with Cox as the default model.
8. Export a compact result summary and optional intermediate objects.

The app currently exposes the key analysis settings through the UI, including PS prior settings, optional PS screening, adjustment method, matching parameters, and outcome model settings.

## Required R packages

At minimum, the app requires Shiny and the OHDSI/HADES packages used by the pipeline. A typical installation includes:

```r
install.packages(c("shiny", "bslib", "DT", "readr", "plotly", "remotes"))

remotes::install_github("OHDSI/DatabaseConnector")
remotes::install_github("OHDSI/SqlRender")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CirceR")
remotes::install_github("OHDSI/FeatureExtraction")
remotes::install_github("OHDSI/CohortMethod")
remotes::install_github("OHDSI/CDMConnector")
```

Depending on the local setup, additional dependencies may also be needed. Keeping package versions aligned with the local R version helps avoid bootstrap/theme or binary mismatch warnings during app startup.

## Running the app

To launch the app locally from the project root:

```r
library(shiny)
runApp()
```

or, if preferred:

```r
shiny::runApp()
```

The app is intended for local interactive use in RStudio, VS Code, or another R environment capable of launching Shiny applications.

## Typical user flow

A typical session looks like this:

1. Launch the app with `runApp()`.
2. Open the **Configuration** tab.
3. Optionally click **Load preset** to populate recommended defaults.
4. Adjust study and analysis settings as needed.
5. Open the **Execution** tab.
6. Initialize the session database.
7. Save the generated configuration.
8. Run the analysis.
9. Open the **Results** tab to inspect plots, tables, and exported files.

## Output

The `results/` folder typically contains a compact summary and optional intermediate files produced by the pipeline. Common outputs include:
- `ple_summary.csv`
- `outcome_model.rds`
- `ps.rds`
- `population.rds`

The exact set of files may depend on runtime settings such as whether intermediate RDS files are saved.

## Notes on session database handling

For local testing, the app initializes a session-specific DuckDB file from the Eunomia example database. This avoids modifying the source example database directly and makes runs more isolated across sessions. The temporary session database is cleaned up when the Shiny session ends.

## Current limitations

This app is still a starter application, not a production-ready study package. It focuses on a single-study interactive workflow and does not yet provide the full set of diagnostics usually expected for production OHDSI analyses, such as detailed balance diagnostics, overlap diagnostics, negative controls, empirical calibration, or multi-analysis orchestration.

The current UI is optimized for readability and safe local experimentation rather than full study automation.

## Next steps

Potential next improvements include:
- richer diagnostics in the **Results** tab,
- better validation of incomplete or incompatible user input,
- support for multiple named presets,
- clearer export management,
- modularization of the app into larger reusable Shiny modules,
- broader support beyond local Eunomia-based testing.