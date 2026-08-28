# Comparative Cohort Analysis Pipeline (Shiny + Script)

This branch hosts an end-to-end analysis pipeline for comparative cohort studies on OMOP CDM data.

The core idea is to provide:

- a **single, coherent pipeline** (covariate screening, propensity score, matching, balance, outcome model) that remains logically stable across databases and cohort choices,
- **configuration hooks** to align the pipeline with a specific OMOP CDM instance and cohort set, without rewriting the analysis logic,
- both a **demo mode** (synthetic data, Shiny app) and a **non-demo mode** (manual database connection) using the same underlying code.

## Branch goals

This branch is intended to:

- implement a **production-ready pipeline** for comparative cohort analyses using CohortMethod and related OHDSI tools,
- keep the analysis logic **configuration-driven but not rewritten per database** (CDM connection settings and cohort IDs change, the core pipeline does not),
- include a **Shiny interface** for:
  - demonstrating the workflow on synthetic OMOP CDM datasets (e.g. Eunomia / SynPUF via DuckDB),
  - checking that the logic runs end-to-end,
  - exploring diagnostics and outputs interactively,
  - configuring covariate selection (forced/excluded) and analysis parameters,
- provide a **script-based entry point** for batch execution, where execution is driven by configuration rather than UI.

## Structure

The main elements in this branch are:

- `app.R`  
  Shiny application entry point. Handles UI, connection setup, covariate selection, and configuration collection, then calls the shared pipeline.

- `www/`  
  Optional static assets for the Shiny app.

- `R/`  
  Shared R code used by both Shiny and script-based execution:
  - `app_helpers.R`: configuration building, covariate catalog management, path management, utilities, and support functions.
  - `run_pipeline_shiny.R`: core pipeline implementation (cohort generation, data extraction, covariate screening, propensity score fitting, auto-caliper matching, balance diagnostics, outcome model).
  - `ui_tabs.R`: Shiny UI layouts for configuration, advanced tuning, execution, and results.
  - `results_outputs.R`: result rendering (tables, plots, file listings) for the Shiny interface.

- `debug_n_shiny.R`  
  Script entry point that constructs a configuration object and runs the same pipeline **without** Shiny. This is intended for batch execution and debugging.

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
   - Connect to an OMOP CDM source (demo DuckDB via `CDMConnector::eunomiaDir()`, or manual DBMS via `DatabaseConnector`).
   - Generate target, comparator, and primary outcome cohorts from ATLAS JSON in `cohorts_json/`.
   - Optionally register additional outcome cohorts.

2. **Data extraction and feature construction**
   - Build the study population from the generated cohort tables.
   - Extract baseline covariates and outcomes using `FeatureExtraction` and CohortMethod data objects.

3. **Covariate catalog and selection**
   - Load the full covariate catalog from the database.
   - Allow interactive selection of **forced covariates** (always included in the PS model) and **excluded covariates** (always excluded).
   - Support covariate expansion by concept ID or ancestor hierarchy (family-level selection).

4. **Covariate pre-screening (stability selection)**
   - Optionally run multiple covariate screening passes on subsamples to reduce dimensionality.
   - Retain top covariates per run based on model coefficients.
   - Keep only covariates selected in at least *K* prescreening runs (configurable, e.g. 3 out of 10).
   - Log selection frequency for each covariate (how many runs it was selected in).

5. **High-correlation covariate exclusion**
   - Automatically detect and exclude covariates with near-perfect correlation with treatment (e.g., cohort definition covariates with analysisId 410, 412, 413).
   - Log excluded covariate IDs for transparency.

6. **Propensity score model fitting**
   - Fit a high-dimensional propensity score model using Cyclops via CohortMethod.
   - Use forced and excluded covariate lists from previous steps.
   - Record model coefficients and screening results.

7. **Auto-caliper matching**
   - Automatically search for an optimal caliper value to achieve a target match rate (default: 65% ± 15%).
   - Test multiple caliper values (0.15, 0.25, then 0.10, 0.05, 0.02 if needed).
   - Use interpolation to find the best caliper, or fall back to the strictest tested if target is unreachable.
   - Apply 1:1 matching on propensity score with the selected caliper.

8. **Balance diagnostics**
   - Compute covariate balance before and after matching.
   - Report maximum absolute SMD and percentage of covariates with SMD > 0.1.
   - Save balance tables and propensity score distributions.

9. **Outcome modelling**
   - Fit the chosen outcome model (stratified Cox by default) with configurable prior and stability options.
   - Save model outputs and treatment effect estimates (HR, 95% CI, p-value).

10. **Output and reporting**
    - Write final analysis summaries, matching summaries, PS model coefficients, and diagnostics to the `output/` folder.
    - In Shiny mode, render tables and plots in the Results tab.

## Demo mode (Shiny app)

The demo mode is intended to run the pipeline on **synthetic OMOP CDM data** with an interactive UI.

Typical usage:

```r
source("setup_packages.R")      # optional, for dependencies
source("setup_ohdsi_env.R")     # optional, for OHDSI environment checks

shiny::runApp()
```

Within the app:

### Configuration tab

- Configure the **database connection** (demo DuckDB or manual DBMS).
- Select or import **target / comparator / primary outcome cohorts** from ATLAS JSON files.
- Load the covariate catalog and interactively select **forced** and **excluded covariates**.
- Expand covariates by concept ID or ancestor hierarchy.

### Advanced tuning tab

- **Cohort and output settings**: JSON folder, output folder, additional outcome IDs, study period.
- **Pre-screening**: number of runs, covariates retained per run, minimum subjects per group, minimum selection frequency.
- **Auto-caliper search**: enable/disable, target match rate, tolerance.
- **Manual matching options** (if auto-caliper disabled): fixed caliper.
- **Trimming**: propensity score trimming percentiles.
- **Outcome model**: prior variance, cross-validation.
- **Technical settings**: CDM schema, cohort table.
- **Saved files**: development and debug file options.

### Execution tab

- Launch the primary analysis.
- View real-time execution logs.
- Download summary reports.

### Results tab

- **Summary**: analysis summary (HR, CI, p-value) and matching summary (match rate, balance metrics).
- **Propensity score**: distribution plots before and after matching.
- **Covariate balance**: SMD plots before and after matching.
- **Outcome diagnostics**: Kaplan–Meier curves, proportional hazards checks.
- **Files**: list and download all output files.

This mode is explicitly aimed at demonstrating the pipeline and validating its behaviour on synthetic data.

## Configuration and adaptivity

The pipeline is designed to be **configuration-driven but logic-stable**:

- Connection mode (demo vs manual), DBMS, and schemas are adjusted via configuration.
- Cohort JSON paths and IDs are controlled by configuration.
- Covariate selection (forced/excluded) is interactive in Shiny mode or scripted in batch mode.
- Screening, auto-caliper, trimming, and outcome model options are adjusted via configuration (UI inputs or script values).
- The **analysis logic** (how cohorts are generated, how PS and outcome models are fitted, how diagnostics are computed) remains the same across databases/cohorts.

Configuration is assembled by helper functions (e.g. `build_config_from_input()`), which consume either Shiny inputs or scripted values, and is then passed to the core pipeline.

## Key features

### Auto-caliper search

The pipeline includes an automatic caliper search that:

- Tests initial caliper values (0.15 and 0.25).
- If match rates are too high (> target), tests stricter calipers (0.10, 0.05, 0.02).
- If match rates are too low (< target), tests wider calipers (0.35, 0.50, 0.75).
- Uses interpolation to find the caliper that achieves the target match rate (default: 65% ± 15%).
- Falls back to the best tested caliper if the target is unreachable.
- Logs all tested calipers and match rates for transparency.

### Covariate selection

- **Forced covariates**: Always included in the PS model (e.g., known confounders).
- **Excluded covariates**: Always excluded from the PS model (e.g., artefacts, cohort definition covariates).
- **Auto-excluded covariates**: Covariates with near-perfect correlation with treatment are automatically detected and excluded.
- **Covariate expansion**: Add all covariates sharing the same concept ID or ancestor hierarchy.

### Stability selection for covariates

- Uses repeated prescreening to assess how often each covariate is selected.
- Retains only covariates that appear in at least *K* runs, improving robustness to sampling variability.
- Provides a `covariate_selection_frequency.csv` file to inspect which covariates are stable vs borderline.

## Status and limitations

This branch is a research-oriented, production-ready pipeline with the following characteristics:

- All core features are implemented and tested on synthetic data (Eunomia).
- Performance and numerical behaviour can vary substantially depending on the dataset, cohort definitions, and covariate space.
- The non-Shiny script (`debug_n_shiny.R`) must be kept aligned with Shiny configuration options to ensure consistent behaviour.

The pipeline is suitable for:

- demonstration on synthetic OMOP CDM data,
- adaptation to other OMOP CDM environments via configuration,
- production use with appropriate validation and sensitivity analyses.