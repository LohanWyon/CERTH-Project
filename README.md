# PLP on SynPUF 1k (DuckDB)

This project runs an OHDSI PatientLevelPrediction (PLP) pipeline on the SynPUF 1k OMOP CDM example dataset using DuckDB and CDMConnector. The code is designed to be reusable so that SynPUF/DuckDB can later be replaced by any other OMOP CDM (for example PostgreSQL) by changing only the configuration file.

## Purpose

- Demonstrate a complete PLP workflow on a small OMOP CDM dataset (SynPUF 1k).
- Use a database-agnostic structure (via `DatabaseConnector` and `createDatabaseDetails`) so the same script can run against different OMOP CDM databases with minimal changes.
- Provide a clean example of cohort construction, covariate extraction, and model training using current versions of PLP and FeatureExtraction.

## Overview of the workflow

1. **Load the SynPUF 1k OMOP CDM**  
   `CDMConnector::eunomiaDir("synpuf-1k")` is used to download and create a DuckDB database containing the SynPUF 1k dataset in OMOP CDM format.

2. **Create simple target and outcome cohorts**  
   A `main.cohort` table is created in DuckDB with the standard OMOP cohort structure:
   - `cohort_definition_id`
   - `subject_id`
   - `cohort_start_date`
   - `cohort_end_date`

   Target cohort (ID = 1): all patients, index date = observation period start.  
   Outcome cohort (ID = 2): patients with at least one condition occurrence, index date = first condition date.

3. **Set up PLP database details**  
   `DatabaseConnector` and `PatientLevelPrediction::createDatabaseDetails()` are used so PLP can access:
   - the CDM schema,
   - the cohort table,
   - the selected target and outcome cohort IDs.

4. **Extract PLP data**  
   `FeatureExtraction::createCovariateSettings()` and `PatientLevelPrediction::getPlpData()` are used to:
   - construct covariates (demographics, conditions, drugs),
   - link covariates to the target cohort,
   - attach outcomes.

5. **Train a prediction model**  
   `PatientLevelPrediction::runPlp()` is used to fit a LASSO logistic regression model with:
   - a 25% test split,
   - a 1–365 day risk window after index date.

6. **Save and inspect results**  
   Results (performance metrics, predictions, covariate summary, etc.) are written to the output folder and returned as a `plpResult` object in R.

## File structure

- `config_plp_synpuf.R`  
  Configuration for the SynPUF 1k + DuckDB setup; defines:
  - `dbms`
  - CDM schema and database name
  - cohort and outcome table names
  - target and outcome cohort IDs
  - PLP sample size and output folder

- `plp_synpuf_hosp.R`  
  Main script that:
  - loads the required packages and configuration,  
  - connects to SynPUF 1k in DuckDB,  
  - creates the cohort table in the CDM schema,  
  - builds `databaseDetails` and `plpData`,  
  - trains the PLP model and prints the `plpResult` summary.

## Requirements

- R (>= 4.5.2)
- R packages:
  - `CDMConnector`
  - `DatabaseConnector`
  - `PatientLevelPrediction`
  - `FeatureExtraction`
  - `duckdb`
  - `DBI`
  - `dplyr`

An environment variable is required to indicate where Eunomia / SynPUF data should be stored. A typical `.Renviron` entry is:

```r
# Example (created once in R)
renv_path <- normalizePath("~/.Renviron", mustWork = FALSE)
writeLines(
  'EUNOMIA_DATA_FOLDER="<path/to/folder>"',
  con = renv_path
)
```

After creating or modifying `.Renviron`, R must be restarted so the environment variable is loaded.

The value can be checked with:

```r
Sys.getenv("EUNOMIA_DATA_FOLDER")
```

## How to run the pipeline

1. **Install required packages**

In an R session:

```r
install.packages(c(
  "CDMConnector",
  "DatabaseConnector",
  "PatientLevelPrediction",
  "FeatureExtraction",
  "duckdb",
  "DBI",
  "dplyr"
))
```

2. **Verify `EUNOMIA_DATA_FOLDER`**

Confirm that the SynPUF/Eunomia directory is configured:

```r
Sys.getenv("EUNOMIA_DATA_FOLDER")
```

The result should be a valid writable folder path.

3. **Set up the project folder**

```text
C:/Users/lohan/Documents/PLP-SynPUF/
  ├─ config_plp_synpuf.R
  ├─ plp_synpuf_hosp.R
  └─ README.md
```

4. **Set the working directory in R**

```r
setwd("C:/path/to/project_folder")
```

5. **Run the PLP script**

```r
source("plp_synpuf_hosp.R")
```

On the first run, the script will:
- download and create the SynPUF 1k DuckDB database,
- build `main.cohort` (target and outcome),
- extract PLP data (`plpData`),
- train the LASSO logistic regression model,
- write results into the folder defined by `outputFolder` in `config_plp_synpuf.R` (by default, `plp_synpuf_duckdb_output` under the working directory).

6. **Inspect results**

After successful execution, the `plpResult` object can be inspected in R, for example:

```r
plpResult$performanceEvaluation$evaluationStatistics
plpResult$performanceEvaluation$thresholdSummary
plpResult$performanceEvaluation$calibrationSummary
plpResult$covariateSummary
```

These components include model performance (e.g., AUROC), calibration metrics, prediction distributions, and covariate summaries.

## Adapting the script to another OMOP CDM

To run the same PLP workflow on a different OMOP CDM (e.g., PostgreSQL):

1. Create a new configuration file, for example `config_plp_postgres.R`, that sets:
   - `dbms = "postgresql"`,
   - appropriate `server`, `user`, `password`, and `port` for `DatabaseConnector::createConnectionDetails`,
   - `cdmDatabaseSchema`, `cohortDatabaseSchema`, `outcomeDatabaseSchema`, and `cohortTable` for the PostgreSQL CDM.

2. In `plp_synpuf_hosp.R`, switch the configuration line from:

```r
source("config_plp_synpuf.R")
```

to:

```r
source("config_plp_postgres.R")
```

3. Run:

```r
source("plp_synpuf_hosp.R")
```

The main pipeline logic (connectionDetails, databaseDetails, getPlpData, runPlp) remains the same; only the configuration file changes to point to a different OMOP CDM database.