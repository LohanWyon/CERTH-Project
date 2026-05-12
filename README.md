# PLE v1 starter (screening & stable)

This branch contains a stable v1 starter for a classical Population-Level Estimation (PLE) study in R using the OHDSI/HADES ecosystem, primarily the CohortMethod package. It is designed to run in VS Code and follows the standard OHDSI workflow: retrieve CohortMethod data, define the study population, estimate the propensity score, apply PS-based adjustment, fit the outcome model, and export a compact summary.

The goal is to provide a safe, readable, configurable project skeleton that:
- works with recent CohortMethod versions using *Args helper objects,
- includes a simple two-step PS screening on a subsample,
- uses a conservative PS stratification + Cox outcome model as the default.

## 1. What this code does

The pipeline implements a standard comparative cohort PLE workflow on OMOP-CDM data:

1. Creates database connection details.
2. Optionally generates cohorts from ATLAS JSON.
3. Builds the CohortMethod study object from the OMOP-CDM and cohort table.
4. Creates the study population.
5. Fits a large-scale propensity score model, with optional screening on a subsample.
6. Applies a configurable PS-based adjustment (matching, stratification, or trimming).
7. Fits the outcome model (Cox by default).
8. Exports a compact result summary and intermediate RDS objects.

By default, this branch assumes an active-comparator design, high-dimensional PS, PS-based adjustment (stratification by default), and a Cox model fitted on the adjusted population.

## 2. Folder structure

```text
ple_v1_safe/
├─ config/
│  ├─ config_connection.R
│  ├─ config_cohorts.R
│  ├─ config_cm_data.R
│  ├─ config_study_population.R
│  ├─ config_analysis.R
│  └─ config_runtime.R
├─ R/
│  ├─ utils.R
│  ├─ cohort_generation.R
│  ├─ run_single_cm_analysis.R
│  └─ export_results.R
├─ run_ple_from_config.R
└─ results/
```

## 3. Required R packages

Install the OHDSI packages needed for a standard CohortMethod analysis:

```r
install.packages(c("remotes", "jsonlite", "readr"))

remotes::install_github("OHDSI/DatabaseConnector")
remotes::install_github("OHDSI/SqlRender")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CirceR")
remotes::install_github("OHDSI/FeatureExtraction")
remotes::install_github("OHDSI/CohortMethod")
```

The code uses the newer *Args objects (for example `createCreatePsArgs()`, `createMatchOnPsArgs()`, `createFitOutcomeModelArgs()`) to stay compatible with recent CohortMethod interfaces.

## 4. Configuration files

All configuration lives under `config/` and is sourced by `run_ple_from_config.R`.

`config_connection.R` – DBMS connection settings (dbms, server, user, password, port, pathToDriver, oracleTempSchema).

`config_cohorts.R` – cohort locations and IDs: cohortDatabaseSchema, cohortTable, targetId, comparatorId, outcomeIds, primaryOutcomeId, and optional ATLAS JSON paths.

`config_cm_data.R` – settings for `getDbCohortMethodData()`: cdmDatabaseSchema, optional oracleTempSchema, studyStartDate/studyEndDate, covariateSettings.

`config_study_population.R` – restrictions for `createStudyPopulation()`: firstExposureOnly, washoutPeriod, removeSubjectsWithPriorOutcome, priorOutcomeLookback, riskWindowStart/riskWindowEnd, startAnchor/endAnchor, requireTimeAtRisk, minTimeAtRisk.

`config_analysis.R` – analysis strategy:

- `psModel`: large-scale PS configuration.
- `psScreening`: two-step PS screening (`enabled`, `sampleSize`, `topCovariates`, `seed`).
- `adjustment`: PS-based adjustment (`method` = "matching", "stratification", or "trimming" plus caliper/maxRatio/trimFraction).
- `outcomeModel`: outcome model type (`modelType = "cox"`, `stratified = TRUE/FALSE`).

`config_runtime.R` – runtime behaviour: outputFolder, createCohorts, saveIntermediateRds, verbose.

## 5. Code files

`R/utils.R` – helper utilities: package checks, creation of connectionDetails, directory creation, simple logging and validation helpers.

`R/cohort_generation.R` – optional cohort generation from ATLAS JSON via CirceR + SqlRender. If `createCohorts = FALSE`, the pipeline assumes cohorts are already present.

`R/run_single_cm_analysis.R` – core OHDSI steps:
- `build_cm_data()` → `getDbCohortMethodData()`
- `build_study_population()` → `createStudyPopulation()`
- `fit_ps_model()` → PS with optional screening (subsample + top covariates + final PS)
- `apply_adjustment()` → matching, stratification, or trimming
- `fit_outcome()` → `fitOutcomeModel()` configured via `createFitOutcomeModelArgs()` (Cox by default)

`R/export_results.R` – exports a compact `ple_summary.csv` (status, RR/HR, CI, p-value, counts) and optionally `ps.rds`, `population.rds`, `outcome_model.rds`. Export is defensive and handles empty adjusted populations.

`run_ple_from_config.R` – main runner: load packages, source R and config files, create connectionDetails, optionally generate cohorts, build cmData, build study population, fit PS (with optional screening), apply adjustment, fit outcome model, and export results to `outputFolder`.

## 6. Running the pipeline

1. Clone this branch and ensure the folder structure matches the tree above.
2. Install required OHDSI packages.
3. Edit configuration files (connection, cohorts, cm data, study population, analysis).
4. Set `createCohorts` in `config_runtime.R` depending on whether cohorts should be generated from ATLAS JSON or are already present.
5. Run:

```r
source("run_ple_from_config.R")
```

or:

```bash
Rscript run_ple_from_config.R
```

## 7. Output

The `results/` folder typically contains:
- `ple_summary.csv`
- `outcome_model.rds`
- `ps.rds`
- `population.rds`

## 8. Limitations and next steps

This is a v1 starter, not a full study package. Diagnostics (PS overlap, covariate balance, negative controls, empirical calibration, multi-analysis support) are minimal and should be added before any production use.