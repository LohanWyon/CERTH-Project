# Generic PLP pipeline with external configuration and ATLAS JSON cohorts

This branch contains a modular Patient-Level Prediction (PLP) example built on top of the OHDSI tool stack.

The goal is to keep the main execution script unchanged while moving database connection settings, cohort definitions, covariate settings, model settings, and runtime parameters into small external configuration files.

The pipeline uses ATLAS-exported cohort definition JSON files as input.
These JSON cohort definitions are converted to SQL with `CirceR`, generated into a cohort table with `CohortGenerator`, and then used by `PatientLevelPrediction` to extract data and train a prediction model.

## Overview

The workflow is:

1. Load connection settings from config files.
2. Read ATLAS cohort definition JSON files.
3. Convert JSON to SQL using `CirceR::cohortExpressionFromJson()` and `CirceR::buildCohortQuery()`.
4. Create cohort tables and generate cohorts with `CohortGenerator`.
5. Build PLP extraction settings with `PatientLevelPrediction::createDatabaseDetails()`.
6. Extract analysis data with `getPlpData()`.
7. Train a model with `runPlp()`.

## Project structure

```text
plp_synpuf_project/
├── run_plp_from_config.R
├── setup_plp_environment.R
├── config/
│   ├── config_connection.R
│   ├── config_cohorts.R
│   ├── config_covariates.R
│   ├── config_model.R
│   └── config_runtime.R
└── cohorts/
    ├── target.json
    └── outcome.json
```

## File roles

### `run_plp_from_config.R`

This is the main execution script.

It is designed to remain unchanged across runs. All study-specific changes should be done in the configuration files or the cohort JSON files.

The script is DBMS-agnostic at the workflow level: it uses `DatabaseConnector` connection details and does not hard-code a specific backend in the run logic.

### `setup_plp_environment.R`

This is a manual setup and verification script for the R environment used by this project.

It is intended to be run before the main PLP script if package installation or dependency issues are suspected. It checks the local R setup, verifies that required packages are installed, attempts to install missing packages, and reports whether the environment is ready.

This helper script is especially useful because OHDSI packages such as `CohortGenerator`, `CirceR`, `SqlRender`, and `PatientLevelPrediction` may require additional setup beyond standard CRAN packages, and Java may also be required depending on the package and platform.

### `config/config_connection.R`

Contains database and CDM connection settings, such as:

- `dbms`
- `server`
- `user`
- `password`
- `port`
- `pathToDriver`
- `cdmDatabaseSchema`
- `cdmDatabaseName`
- `cdmVersion`
- `tempEmulationSchema`
- `cohortDatabaseSchema`
- `outcomeDatabaseSchema`

The meaning of `server` depends on the DBMS:

- for local DuckDB examples, it can be a local file or an OMOP example directory;
- for other systems, it can be a host, URL, or connection string depending on the backend expected by `DatabaseConnector`.

### `config/config_cohorts.R`

Contains cohort-related settings, such as:

- cohort table name
- target cohort ID
- outcome cohort ID
- target cohort name
- outcome cohort name
- path to `target.json`
- path to `outcome.json`
- `CohortGenerator` options like `incremental` and `generateStats`

### `config/config_covariates.R`

Contains the `FeatureExtraction::createCovariateSettings()` object used during data extraction.

This file controls which covariates are included in the PLP analysis.

### `config/config_model.R`

Contains:

- `modelSettings`
- `populationSettings`
- `splitSettings`

This is where the algorithm choice and prediction design are defined. For example, the current setup uses LASSO logistic regression.

### `config/config_runtime.R`

Contains runtime settings such as:

- `sampleSizePlp`
- `analysisId`
- `analysisName`
- `outputFolder`

### `cohorts/target.json` and `cohorts/outcome.json`

These files must contain real ATLAS-exported cohort definition JSON.

They are read by the main script and converted into SQL using `CirceR`.

## Environment setup

Before running the main script, it is recommended to manually run:

```r
source("setup_plp_environment.R")
```

This setup script helps verify that all required packages and dependencies are available before starting the PLP workflow.

This is particularly helpful for OHDSI packages such as `CohortGenerator`, `CirceR`, `SqlRender`, and `PatientLevelPrediction`, since installation issues can arise from missing repositories, missing system dependencies, or Java configuration problems.

If the setup script completes successfully, you can then run:

```r
source("run_plp_from_config.R")
```

## Example configuration in this branch

This branch currently includes a default example configuration based on a local Eunomia / SynPUF-like OMOP CDM in DuckDB.

This example is meant for development and validation only. The same pipeline structure can be reused with other OMOP CDM databases by editing `config/config_connection.R` and the cohort configuration files, without modifying the main execution script.

## Example study design in this branch

For a simple technical example, this branch uses:

- **Target cohort:** all persons entering observation
- **Outcome cohort:** any recorded condition occurrence

This setup is mainly intended to validate the end-to-end workflow rather than to represent a final clinical prediction question. A more realistic PLP study would usually define a more specific target population and a clinically meaningful outcome.

## Requirements

The script uses the following R packages:

- `CDMConnector`
- `DatabaseConnector`
- `SqlRender`
- `PatientLevelPrediction`
- `CohortGenerator`
- `CirceR`
- `DBI`
- `dplyr`
- `FeatureExtraction`

Additional DBMS-specific packages may be required depending on the target platform.

For example:

- `duckdb` for local DuckDB-based testing
- other drivers or JDBC dependencies for PostgreSQL, SQL Server, Oracle, etc.

Some OHDSI packages may require Java to be installed and correctly configured in the R environment. This is especially relevant for packages such as `CirceR`. The setup script checks for Java and reports its availability.

## How cohort generation works

`CohortGenerator` expects a cohort definition set that typically includes columns such as `cohortId`, `cohortName`, `json`, and `sql`.

In this project, the SQL is generated dynamically from the ATLAS JSON at runtime using `CirceR`, instead of being stored manually.

The script then:

- creates cohort tables with `getCohortTableNames()` and `createCohortTables()`
- generates the cohorts with `generateCohortSet()`
- stores the resulting cohorts in the configured cohort table

## How PLP uses the generated cohorts

After the cohorts are generated, `PatientLevelPrediction::createDatabaseDetails()` is used to point PLP to:

- the CDM schema
- the cohort table
- the target cohort ID
- the outcome cohort ID

Then `getPlpData()` extracts the analysis dataset and `runPlp()` fits the selected model.

## How to run

From the project root in R:

```r
source("setup_plp_environment.R")
source("run_plp_from_config.R")
```

## How to change the study without editing the main script

To adapt this branch to another use case:

- update the database settings in `config/config_connection.R`
- replace `cohorts/target.json` with a new ATLAS target cohort export
- replace `cohorts/outcome.json` with a new ATLAS outcome cohort export
- update covariate settings in `config/config_covariates.R`
- update model or population settings in `config/config_model.R`
- update runtime settings in `config/config_runtime.R`

The main script should not need any modification as long as the expected config object names are preserved.

## Notes

- This branch is designed as a simple and modular example.
- The current default example uses a DuckDB-based Eunomia / SynPUF-like OMOP CDM.
- The run script itself is intended to remain generic and reusable across DBMS backends.
- Reuse on another OMOP CDM should mainly require config changes rather than script changes.

## References

- CohortGenerator README and examples: <https://cran.r-project.org/web/packages/CohortGenerator/readme/README.html>
- Cohort generation vignette: <https://ohdsi.github.io/CohortGenerator/articles/GeneratingCohorts.html>
- CohortGenerator function reference: <https://ohdsi.github.io/CohortGenerator/reference/generateCohortSet.html>
- CohortGenerator package page: <https://CRAN.R-project.org/package=CohortGenerator>
- CirceR README: <https://cran.r-project.org/web/packages/CirceR/readme/README.html>
- CirceR GitHub README: <https://github.com/OHDSI/CirceR>
- SqlRender documentation: <https://ohdsi.github.io/SqlRender/>
- DatabaseConnector querying vignette: <https://ohdsi.github.io/DatabaseConnector/articles/Querying.html>
- PatientLevelPrediction quick install guide: <https://ohdsi.github.io/PatientLevelPrediction/articles/PatientLevelPrediction.html>
- PatientLevelPrediction installation guide: <https://ohdsi.github.io/PatientLevelPrediction/articles/InstallationGuide.html>
- PatientLevelPrediction package docs: <https://ohdsi.r-universe.dev/PatientLevelPrediction>