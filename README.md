# SynPUF 1k – OMOP + PLP-style Demo

This branch contains a small, step-by-step workflow to explore an OMOP CDM dataset (SynPUF 1k via Eunomia), create simple demo cohorts, and run a minimal prediction model in R using DuckDB. The goal is educational/prototyping, not a clinically meaningful study.

## Prerequisites

- R ≥ 4.5
- Internet access for installing packages
- Java is *not* required (DatabaseConnector is not used)

## Script overview

All scripts use the SynPUF 1k DuckDB database provided by `CDMConnector` (Eunomia).

### 00_setup_synpuf.R

Common setup script:

- Installs and loads: `CDMConnector`, `duckdb`, `DBI`, `dplyr`, `dbplyr`, `PatientLevelPrediction`, `glmnet`, `pROC`.
- Creates a local Eunomia data folder if needed.
- Downloads or reuses SynPUF 1k via `eunomiaDir("synpuf-1k")`.
- Exposes the DuckDB path as `synpuf_db_path`.

Other scripts start with:

```r
source("00_setup_synpuf.R")
```

### 01_explore_synpuf_cdm.R

Basic OMOP CDM exploration:

- Connects to SynPUF DuckDB.
- Lists available OMOP tables.
- Shows:
  - Number of patients (`person`).
  - Preview of `person`.
  - Visits by `visit_concept_id`.
  - Gender distribution.
- Example join between `person` and `visit_occurrence`.

### 02_build_demo_cohorts.R

Builds simple demo cohorts in the SynPUF database:

- Creates an OMOP-style `cohort` table with:
  - Target cohort (`cohort_definition_id = 1`): all persons with ≥1 visit.
  - Outcome cohort (`cohort_definition_id = 2`): persons with ≥1 inpatient visit (`visit_concept_id = 9201`).
- Writes the combined table to DuckDB.
- Reports counts per `cohort_definition_id` and overlap between target/outcome.
- This is a toy example, not a real study design.

### 03_demo_plp_like_model.R

Runs a small “PLP-like” logistic regression on the demo cohorts:

- Reads `cohort` and `person` from SynPUF DuckDB.
- Builds a labelled population:
  - targetId = 1 (everyone with ≥1 visit),
  - outcomeId = 2 (inpatient visit).
- Constructs simple covariates from `person`:
  - age (approx. `2020 - year_of_birth`),
  - gender_male (1 if `gender_concept_id == 8507`).
- Fits a regularized logistic regression using `glmnet` (75/25 train/test split).
- Computes an approximate AUC with `pROC`.

## How to run

From the project root in R/RStudio:

```r
source("00_setup_synpuf.R")
source("01_explore_synpuf_cdm.R")
source("02_build_demo_cohorts.R")
source("03_demo_plp_like_model.R")
```

Run scripts in order and inspect the console output for each step.

## Notes

- SynPUF 1k is a small synthetic dataset for testing/training.
- Cohort definitions and covariates here are simplified and artificial.
- This branch focuses on the mechanics: OMOP CDM → cohorts → basic prediction model.
- For a full OHDSI PatientLevelPrediction workflow, next steps would include:
  - configuring `DatabaseConnector` (Java, rJava),
  - using `getPlpData()` / `runPlp()` with proper CDM + cohort definitions (e.g. defined in ATLAS).Java is not required (we do not use DatabaseConnector in this demo)
