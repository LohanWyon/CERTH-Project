PLE v1 starter (screening & stable)
This branch contains a stable v1 starter for a classical Population‑Level Estimation (PLE) study in R using the OHDSI/HADES ecosystem, primarily the CohortMethod package.

It is designed to run in VS Code and to stay as close as possible to the standard OHDSI workflow: retrieve CohortMethod data, define the study population, estimate the propensity score, apply PS‑based adjustment, fit the outcome model, and export a compact summary.

The goal of this branch is not to replace OHDSI internals, but to provide a safe, readable, configurable project skeleton that:

works with recent CohortMethod versions that use *Args helper objects (for example createCreatePsArgs()),

includes a simple two‑step PS screening on a subsample before fitting the final PS model,

uses a conservative PS stratification + Cox outcome model as the default.

1. What this code does
The pipeline implements a standard comparative cohort PLE workflow on OMOP‑CDM data:

creates database connection details,

optionally generates cohorts from ATLAS JSON definitions,

builds the CohortMethod study object from the OMOP‑CDM and cohort table,

creates the study population,

fits a large‑scale propensity score model with an optional screening step on a subsample,

applies a configurable PS‑based adjustment step (matching, stratification, or trimming),

fits the outcome model (Cox by default),

exports a compact result summary and optional intermediate RDS objects.

The default configuration in this branch is deliberately conservative and close to a single‑study OHDSI design:

active‑comparator cohort design,

high‑dimensional propensity score,

PS‑based adjustment (default: stratification),

Cox outcome model on the adjusted population.

2. Folder structure
text
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
config/ holds only parameters (no logic).

R/ contains the reusable functions and the main OHDSI wrappers.

run_ple_from_config.R is the main entry‑point script.

3. Required R packages
This branch depends on the OHDSI stack required for a standard CohortMethod analysis:

r
install.packages(c("remotes", "jsonlite", "readr"))

remotes::install_github("OHDSI/DatabaseConnector")
remotes::install_github("OHDSI/SqlRender")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CirceR")
remotes::install_github("OHDSI/FeatureExtraction")
remotes::install_github("OHDSI/CohortMethod")
The code uses the newer *Args objects introduced in recent CohortMethod versions (for example createCreatePsArgs(), createMatchOnPsArgs(), createFitOutcomeModelArgs()) to improve stability across package updates.

Depending on your database platform, you may also need to configure JDBC drivers via DatabaseConnector.

4. Configuration files
All configuration lives under config/ and is sourced by run_ple_from_config.R.

config/config_connection.R
Defines DBMS connection settings.

Typical fields:

dbms – "postgresql", "sql server", "oracle", "redshift", "duckdb", etc.

server – server name or connection string.

user, password, port – credentials.

pathToDriver – optional JDBC driver path.

oracleTempSchema – optional Oracle temp schema.

config/config_cohorts.R
Defines where the cohorts live and which IDs to use.

Fields:

cohortDatabaseSchema – schema containing the cohort table.

cohortTable – cohort table name.

targetId, comparatorId – exposure cohort IDs.

outcomeIds – vector of outcome cohort IDs.

primaryOutcomeId – outcome used in createStudyPopulation().

targetJsonFile, comparatorJsonFile, outcomeJsonFiles – optional ATLAS JSON paths if cohort generation is enabled.

config/config_cm_data.R
Defines getDbCohortMethodData() settings.

Fields:

cdmDatabaseSchema – OMOP‑CDM schema.

oracleTempSchema – optional Oracle temp schema.

studyStartDate, studyEndDate – optional date restriction.

covariateSettings – covariate settings (defaults to FeatureExtraction::createDefaultCovariateSettings() if not overridden).

config/config_study_population.R
Defines restrictions used by createStudyPopulation():

Key fields:

firstExposureOnly

washoutPeriod

removeSubjectsWithPriorOutcome

priorOutcomeLookback

riskWindowStart, riskWindowEnd

startAnchor, endAnchor

requireTimeAtRisk, minTimeAtRisk

config/config_analysis.R
Defines the analysis strategy for PS and outcome model.

In this branch, it includes:

psModel – PS model settings (for example maxCohortSizeForFitting, Laplace prior).

psScreening – 2‑step PS screening configuration:

enabled – enable/disable screening,

sampleSize – number of subjects in the screening subsample,

topCovariates – number of covariates to keep based on the screening model,

seed – reproducibility.

adjustment – PS‑based adjustment:

method – "matching", "stratification", or "trimming",

caliper, maxRatio, trimFraction – method‑specific parameters.

outcomeModel – outcome model settings:

modelType – "cox" by default,

stratified – whether to fit a stratified Cox by PS strata.

config/config_runtime.R
Defines runtime behaviour and output.

Typical fields:

outputFolder – where to write CSV and RDS outputs.

createCohorts – TRUE to generate cohorts from JSON, FALSE if cohorts already exist.

saveIntermediateRds – whether to save PS and population objects.

verbose – basic logging.

5. Code files
R/utils.R
Generic helpers:

checks for required packages,

helper to create connectionDetails,

safe directory creation,

simple logging and validation helpers.

This file is meant to be reusable across future PLE/PLP projects.

R/cohort_generation.R
Optional cohort generation step.

If runtimeConfig$createCohorts = TRUE, the code:

reads ATLAS JSON,

converts them to OHDSI cohort expressions via CirceR,

builds SQL via SqlRender,

creates and populates the cohort tables in cohortDatabaseSchema.

If createCohorts = FALSE, the pipeline assumes the cohort table already exists and contains the target, comparator and outcome cohorts.

R/run_single_cm_analysis.R
Core OHDSI analysis steps, as thin wrappers around CohortMethod:

build_cm_data() – calls getDbCohortMethodData().

build_study_population() – calls createStudyPopulation().

fit_ps_model() –

if psScreening$enabled = TRUE:

fits a screening PS model on a subsample of the population,

ranks covariates by absolute coefficient, keeps the top topCovariates,

refits a final PS model on the full population restricted to those covariates;

otherwise: fits a single PS model as in the standard OHDSI examples.

apply_adjustment() – applies the chosen PS‑based adjustment using createMatchOnPsArgs(), createStratifyByPsArgs(), or createTrimByPsToEquipoiseArgs().

fit_outcome() – fits the outcome model via fitOutcomeModel() using createFitOutcomeModelArgs() (Cox by default).

The intention is to reuse OHDSI logic rather than reimplement it; the wrappers just centralize configuration and provide a place for light customisation (like the screening step).

R/export_results.R
Handles export and basic robustness:

writes a small ple_summary.csv with the main effect estimate (status, RR/HR, CI, p‑value, sample sizes),

optionally saves ps.rds, population.rds, outcome_model.rds for debugging and diagnostics,

avoids hard failures when the adjusted population is empty or when no outcomes are observed (it logs the situation instead of throwing).

run_ple_from_config.R
Main runner script.

It:

loads required packages,

sources all R function files,

sources all configuration files,

creates the DB connection details,

optionally generates cohorts,

builds cmData,

builds the study population,

fits the PS (with optional screening),

applies the PS‑based adjustment,

fits the outcome model,

exports the results to runtimeConfig$outputFolder.

In VS Code, this is the script to run for a full end‑to‑end execution.

6. How to run the pipeline
Step 1 – Create the project structure
Clone this branch and ensure your local folder matches the structure above.

Step 2 – Install OHDSI packages
Install the required packages as described in section 3.

Step 3 – Edit configuration
At minimum, update:

config_connection.R – DB connection.

config_cohorts.R – where your target/comparator/outcome cohorts come from.

config_cm_data.R – CDM schema and covariate settings.

config_study_population.R – inclusion/exclusion and risk window.

config_analysis.R – PS model, PS screening, and outcome model settings.

Step 4 – Decide whether to generate cohorts
Set runtimeConfig$createCohorts = FALSE if cohorts already exist.

Set runtimeConfig$createCohorts = TRUE and provide JSON paths if you want this project to create them from ATLAS exports.

Step 5 – Run
In R / VS Code:

r
source("run_ple_from_config.R")
or from a terminal:

bash
Rscript run_ple_from_config.R
7. Output files
The results/ folder typically contains:

ple_summary.csv – compact summary of the effect estimate (status, RR/HR, CI, p, counts).

outcome_model.rds – fitted outcome model object (if the model could be fitted).

ps.rds – propensity score object.

population.rds – adjusted population used for the outcome model.

The exact content depends on the package versions and on whether the design yields a non‑empty adjusted population with observed outcomes.

8. Why this branch is “safe”
Compared to a quick prototype, this branch adds several safeguards:

explicit use of createPrior() and *Args helper objects to stay compatible with newer CohortMethod interfaces,

optional two‑step PS screening to keep PS fitting feasible on larger covariate spaces,

basic runtime validation and logging,

export code that does not crash when there are no matched/adjusted subjects or no outcomes,

a default configuration based on PS stratification + Cox, which is less brittle than strict 1:1 caliper matching in small examples.

The objective is to have something that runs reliably, is easy to read, and can be extended with more diagnostics or multiple analyses later.

9. Known limitations
This is a v1 starter, not a full study package:

The code assumes one analysis at a time (single target/comparator/outcome configuration).

Diagnostics (PS overlap, covariate balance, etc.) are minimal and should be added for real studies.

Negative controls and empirical calibration are not implemented yet.

Multi‑outcome / multi‑exposure grids are not supported out of the box.

On small or synthetic datasets, some designs may legitimately produce neutral or inconclusive results (for example RR ≈ 1 with wide CIs).

10. Suggested next steps
Once the basic run works on your environment, natural evolutions include:

adding PS and covariate balance diagnostics (plots, tables),

supporting multiple adjustment branches in a single run (matching + stratification + trimming),

exporting cohort counts and attrition tables,

adding negative controls and empirical calibration,

moving towards a more generic, multi‑analysis OHDSI study package structure.