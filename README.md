# Comparative Cohort Analysis Pipeline (Shiny + Script)

This branch hosts a candidate end-to-end analysis pipeline for comparative cohort studies on OMOP CDM data.

The core idea is to provide:

- a **single, coherent pipeline** (propensity score, matching, balance, outcome model) that remains logically stable across databases and cohort choices,
- **configuration hooks** to align the pipeline with a specific OMOP CDM instance and cohort set, without rewriting the analysis logic,
- both a **demo mode** (synthetic data, Shiny app) and a **non-demo mode** (connection infos given for rwd usage) using the same underlying code.

The code is still under active development: some components are fully implemented, others are placeholders for planned features. The goal is to progressively converge towards a reusable, research-grade pipeline.

## Branch goals

This branch is intended to:

- implement a **final-style pipeline skeleton** for comparative cohort analyses using CohortMethod and related OHDSI tools,
- keep the analysis logic **configuration-driven but not rewritten per database** (CDM connection settings and cohort IDs change, the core pipeline does not),
- include a **Shiny interface** for:
  - demonstrating the workflow on synthetic OMOP CDM datasets (e.g. Eunomia / SynPUF via DuckDB / CDMConnector),
  - checking that the logic runs end-to-end,
  - exploring diagnostics and outputs interactively,
- provide a **script-based entry point** for debug, where execution is driven by configuration rather than UI.

In other words, the branch is a prototype of what a “final” analysis pipeline could look like once applied to different OMOP CDM environments.

## Structure

The main elements in this branch are:

- `app.R`  
  Shiny application entry point. Handles UI, connection setup, and configuration collection, then calls the shared pipeline.

- `www/`  
  Optional static assets for the Shiny app.

- `R/`  
  Shared R code used by both Shiny and script-based execution:
  - `app_helpers.R`: configuration building, path management, utilities, and support functions.
  - `run_pipeline_shiny.R`: core pipeline implementation (cohort generation, data extraction, propensity score fitting, matching, diagnostics, outcome model).
  - `ui_tabs.R`: Shiny UI layouts for configuration, advanced tuning, execution, and results.
  - `results_outputs.R`: result rendering (tables, plots, file listings) for the Shiny interface.

- `debug_n_shiny.R`  
  Script entry point that constructs a configuration object and runs the same pipeline **without** Shiny. This is intended for debugging scenarios.

- `cohorts_json/`  
  ATLAS-exported JSON definitions for target, comparator, and outcome cohorts, used to generate cohort tables in the CDM.

- `output/`  
  Destination for analysis outputs: final results, diagnostics, and optional development/debug files.

- `setup_ohdsi_env.R`  
  Helper for OHDSI-related environment setup.

- `setup_packages.R`  
  Helper for installing and checking required R packages.

- `README.md`  
  This branch-specific documentation.

## Pipeline overview

The pipeline implemented in `run_pipeline_shiny.R` (and reused by `app.R` and `debug_n_shiny.R`) follows these main steps:

1. **Connection and cohort setup**
   - Connect to an OMOP CDM source (e.g. DuckDB via `CDMConnector::eunomiaDir()`, or other DBMS via `DatabaseConnector`).
   - Generate target, comparator, and primary outcome cohorts from ATLAS JSON in `cohorts_json/`.
   - Optionally register additional outcome cohorts.

2. **Data extraction and feature construction**
   - Build the study population from the generated cohort tables.
   - Extract baseline covariates and outcomes using `FeatureExtraction` and CohortMethod data objects.

3. **Propensity score and covariate pre-screening**
   - Optionally run multiple covariate screening passes to reduce dimensionality.
   - Fit a high-dimensional propensity score model using Cyclops via CohortMethod.
   - Record model coefficients and screening results.

4. **Matching, trimming, and balance diagnostics**
   - Apply trimming and/or matching based on configuration.
   - Compute covariate balance before and after matching.
   - Save balance diagnostics and propensity score distributions.

5. **Outcome modelling and diagnostics**
   - Fit the chosen outcome model (e.g. stratified Cox) with configurable prior and stability options.
   - Save model outputs and basic diagnostics (e.g. Kaplan–Meier plots, proportional hazards checks).

6. **Output and reporting**
   - Write final analysis summaries and diagnostics to the `output/` folder.
   - In Shiny mode, render tables and plots in the Results tab.

Some of these steps are fully realized; others are in progress or implemented with conservative defaults, to be refined as the branch evolves.

## Demo mode (Shiny app)

The demo mode is intended to run the pipeline on **synthetic OMOP CDM data** with an interactive UI.

Typical usage:

```r
source("setup_packages.R")      # optional, for dependencies
source("setup_ohdsi_env.R")     # optional, for OHDSI environment checks

shiny::runApp()
```

Within the app:

- Configure the **database connection** (by default, a demo DuckDB-backed OMOP dataset via `CDMConnector::eunomiaDir(...)`).
- Select or import **target / comparator / outcome cohorts** from ATLAS JSON files.
- Optionally adjust **Advanced tuning** settings (screening, matching, trimming, outcome prior / cross-validation, debug/dev file saving).
- Launch the primary analysis from the **Execution** tab and inspect logs and diagnostics.
- Explore summaries, propensity scores, covariate balance, and outcome diagnostics in the **Results** tab.

This mode is explicitly aimed at demonstrating the pipeline and validating its behaviour on synthetic data.


## Configuration and adaptivity

The pipeline is designed to be **configuration-driven but logic-stable**:

- Connection mode (demo vs manual), DBMS, and schemas are adjusted via configuration.
- Cohort JSON paths and IDs are controlled by configuration.
- Screening, matching, trimming, and outcome model options are adjusted via configuration (UI inputs or script values).
- The **analysis logic** (how cohorts are generated, how PS and outcome models are fitted, how diagnostics are computed) is intended to remain the same across databases/cohorts.

Configuration is assembled by helper functions (e.g. `build_config_from_input()`), which consume either Shiny inputs or scripted values, and is then passed to the core pipeline.

## Status and limitations

This branch is a research-oriented prototype and has known limitations:

- some features are not yet implemented or are implemented with conservative defaults,
- performance and numerical behaviour can vary substantially depending on the dataset, cohort definitions, and covariate space,
- the non-Shiny script must be kept aligned with Shiny configuration options to ensure consistent behaviour.

Despite these limitations, the branch provides a concrete, runnable pipeline that may be able to be:
- demonstrated on synthetic OMOP CDM data,
- adapted to other OMOP CDM environments via configuration,
- used as a foundation for further research and refinement.