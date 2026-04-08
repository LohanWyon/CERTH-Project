# OMOP CDM Exploration and Patient-Level Prediction Prototypes

This repository contains R scripts and utilities for working with OMOP Common Data Model (CDM) data, focusing on:
- connecting to OMOP CDM stored in DuckDB,
- exploring and understanding the CDM structure,
- building simple cohorts,
- experimenting with patient-level prediction (PLP) workflows.

The main branch is intended for the **core project**, while a separate branch (`feature/synpuf-plp-demo`) hosts a self-contained demo based on SynPUF 1k.

## Project structure (main branch)

The exact structure may evolve, but the main branch typically contains:

- Core R scripts for:
  - connecting to your OMOP CDM instance,
  - running exploratory queries,
  - preparing data for analyses.
- Configuration / utility code (e.g. connection helpers, environment setup).
- Documentation for how to run analyses in your actual environment.

This branch is meant to stay focused on your **real project** (not the toy SynPUF example).

## SynPUF 1k demo branch (separate)

A dedicated branch `feature/synpuf-plp-demo` contains a small tutorial-style pipeline using the SynPUF 1k example dataset provided by `CDMConnector` (Eunomia):

1. **00_setup_synpuf.R**  
   Common setup:
   - installs/loads required packages (`CDMConnector`, `duckdb`, `DBI`, `dplyr`, `dbplyr`, `PatientLevelPrediction`, `glmnet`, `pROC`),
   - defines a local data folder,
   - creates or reuses a DuckDB copy of SynPUF 1k.

2. **01_explore_synpuf_cdm.R**  
   Explores the SynPUF OMOP CDM:
   - lists tables,
   - inspects `person` and `visit_occurrence`,
   - computes basic statistics (patient count, visits by type, gender distribution),
   - runs a simple join between person and visits.

3. **02_build_demo_cohorts.R**  
   Builds a toy `cohort` table inside the SynPUF DuckDB:
   - target cohort: all persons with at least one visit,
   - outcome cohort: persons with at least one inpatient visit,
   - writes the combined table back to DuckDB and reports counts/overlap.

4. **03_demo_plp_like_model.R**  
   Runs a minimal “PLP-like” logistic regression:
   - reads the `cohort` and `person` tables,
   - builds a labelled population (target vs outcome),
   - constructs simple covariates (age, gender),
   - trains a regularized logistic regression with `glmnet`,
   - computes an approximate AUC with `pROC`,
   - optionally removes the demo DuckDB instance at the end.

This branch is explicitly a **demo / proof-of-concept** and is not intended to be merged into `main`.

## Getting started (main project)

1. Clone the repository:
   ```bash
   git clone <your-repo-url>
   cd <your-repo-folder>
   ```

2. Check out the main branch:
   ```bash
   git checkout main
   ```

3. Open the project in RStudio or your preferred IDE and follow the instructions in the project-specific scripts/documentation (connection settings, CDM schema names, etc.).

## Running the SynPUF demo (optional)

If you want to try the SynPUF PLP-style demo:

1. Check out the demo branch:
   ```bash
   git checkout feature/synpuf-plp-demo
   ```

2. In R:
   ```r
   source("00_setup_synpuf.R")
   source("01_explore_synpuf_cdm.R")
   source("02_build_demo_cohorts.R")
   source("03_demo_plp_like_model.R")
   ```

This will:
- create a local DuckDB copy of SynPUF 1k (if needed),
- explore the OMOP CDM structure,
- build simple cohorts,
- fit a small logistic regression model on the demo data.

## Notes

- The SynPUF demo is based on a small, synthetic dataset and uses simplified cohort definitions and covariates. It is meant for **learning and testing**, not for real clinical modelling.
- The main branch should remain focused on your actual project data and workflows.
- If you extend the SynPUF demo, consider keeping those changes on the demo branch or another feature branch to avoid mixing experimental code into the main project.