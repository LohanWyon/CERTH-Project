PLE v1 starter (safe version)
This repository contains a safe v1 starter for a classical Population-Level Estimation (PLE) study in R using the OHDSI/HADES ecosystem, mainly the CohortMethod package. It is intended for use in VS Code and keeps the implementation as close as possible to the standard OHDSI workflow: retrieve CohortMethod data, define the study population, estimate the propensity score, apply PS-based adjustment, fit the outcome model, and export the results.

The goal of this version is not to replace OHDSI internals, but to provide a stable, readable, configurable project skeleton that can be used as a first working implementation and later extended with additional diagnostics, alternative adjustment strategies, or multiple analyses. It has been updated to work with recent versions of the OHDSI packages (notably CohortMethod) that use argument objects such as createCreatePsArgs() and similar helpers.

1. What this code does
The pipeline implements a standard comparative cohort PLE workflow on OMOP-CDM data:

creates database connection details,

optionally generates cohorts from ATLAS JSON,

builds the CohortMethod study object from the OMOP-CDM and cohort table,

creates the study population,

fits a large-scale propensity score model,

applies a configurable PS-based adjustment step,

fits the final outcome model,

exports a compact result summary and optional intermediate RDS objects.

The default configuration is intentionally conservative and follows a typical OHDSI single-study setup:

active-comparator comparative cohort design,

large-scale propensity score,

PS-based adjustment (matching or stratification, configurable),

Cox outcome model.

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
Each file has a single role: configuration files hold parameters only, while the R/ scripts contain helper functions and the main analysis logic.

3. Required R packages
Install the OHDSI packages needed for a standard CohortMethod analysis:

r
install.packages(c("remotes", "jsonlite", "readr"))
remotes::install_github("OHDSI/DatabaseConnector")
remotes::install_github("OHDSI/SqlRender")
remotes::install_github("OHDSI/CohortGenerator")
remotes::install_github("OHDSI/CirceR")
remotes::install_github("OHDSI/FeatureExtraction")
remotes::install_github("OHDSI/CohortMethod")
Some functions in this starter (PS, matching, outcome model) use the newer “Args” objects (createCreatePsArgs(), createMatchOnPsArgs(), createFitOutcomeModelArgs()) recommended in recent CohortMethod documentation.

Depending on the database platform, you may also need JDBC/driver configuration through DatabaseConnector.

4. Configuration files
config/config_connection.R
Defines the DBMS connection settings. Edit this first.

Fields:

dbms: DBMS type, for example "postgresql", "sql server", "oracle", "redshift".

server: server name or connection string.

user, password, port: credentials.

pathToDriver: optional JDBC driver path.

oracleTempSchema: optional Oracle temp schema.

config/config_cohorts.R
Defines where the cohorts are stored and which cohort IDs to use.

Fields:

cohortDatabaseSchema: schema containing the cohort table.

cohortTable: cohort table name.

targetId: target exposure cohort ID.

comparatorId: comparator cohort ID.

outcomeIds: vector of outcome cohort IDs.

primaryOutcomeId: outcome used in createStudyPopulation().

targetJsonFile, comparatorJsonFile, outcomeJsonFiles: optional paths to ATLAS JSON definitions if cohort generation is enabled.

config/config_cm_data.R
Defines the settings used by getDbCohortMethodData().

Fields:

cdmDatabaseSchema: OMOP-CDM schema.

oracleTempSchema: optional Oracle temp schema.

studyStartDate, studyEndDate: optional date restriction.

covariateSettings: OHDSI covariate settings; defaults to FeatureExtraction::createDefaultCovariateSettings().

config/config_study_population.R
Defines the study population restrictions used by createStudyPopulation().

Important fields:

firstExposureOnly

washoutPeriod

removeSubjectsWithPriorOutcome

priorOutcomeLookback

riskWindowStart, riskWindowEnd

startAnchor, endAnchor

requireTimeAtRisk, minTimeAtRisk

config/config_analysis.R
Defines the analysis strategy.

This v1 uses:

CohortMethod::createPrior("laplace", ...) for regularized PS fitting,

a PS model configured through createCreatePsArgs() under the hood,

a PS-based adjustment step (matching, stratification, or trimming),

a Cox outcome model, configured through createFitOutcomeModelArgs().

You can later change:

matching -> stratification or trimming,

the PS prior,

the outcome model type.

config/config_runtime.R
Defines runtime behaviour.

Fields:

outputFolder

createCohorts

saveIntermediateRds

verbose

5. Code files
R/utils.R
Contains general helper functions:

package checks,

creation of connectionDetails,

directory creation,

simple logging,

small validation helpers.

This file is intentionally generic and reusable across future PLE or PLP projects.

R/cohort_generation.R
Contains the optional cohort generation step.

If runtimeConfig$createCohorts = TRUE, the code:

reads ATLAS JSON files,

converts them into OHDSI cohort expressions using CirceR,

builds SQL,

creates cohort tables,

generates cohorts into the cohort table.

If createCohorts = FALSE, the code assumes the cohort table already exists and already contains the requested target, comparator, and outcome cohorts.

R/run_single_cm_analysis.R
Contains the main OHDSI analysis steps:

build_cm_data() -> calls getDbCohortMethodData().

build_study_population() -> calls createStudyPopulation().

fit_ps_model() -> calls createPs() using createCreatePsArgs().

apply_adjustment() -> applies matching, stratification, or trimming using the corresponding *Args functions (for example createMatchOnPsArgs()).

fit_outcome() -> calls fitOutcomeModel() using createFitOutcomeModelArgs().

These are thin wrappers around OHDSI functions. This is intentional: the aim is to reuse existing OHDSI logic rather than reimplementing it.

R/export_results.R
Writes a compact CSV summary and saves intermediate RDS files.

This is useful for:

debugging,

comparing runs,

checking whether the model completed,

later building richer diagnostics or reporting layers.

run_ple_from_config.R
This is the main runner.

It :

loads required packages,

sources all code files,

sources all config files,

validates a few key settings,

runs the pipeline end to end,

writes results to the output folder.

In VS Code, this is the main file to run.

6. How to use the code
Step 1 — Create the folder structure
Create the project folder and copy each file into the matching location.

Step 2 — Install packages
Install the required OHDSI packages listed above.

Step 3 — Edit the configuration files
At minimum, update:

config_connection.R

config_cohorts.R

config_cm_data.R

config_study_population.R

config_analysis.R

Step 4 — Decide whether to generate cohorts
If cohorts already exist in the cohort table: set createCohorts = FALSE.

If you want the pipeline to generate them from ATLAS JSON: set createCohorts = TRUE and provide JSON file paths in config_cohorts.R.

Step 5 — Run the pipeline
In VS Code:

r
source("run_ple_from_config.R")
or in a terminal:

bash
Rscript run_ple_from_config.R
7. Output files
The results/ folder will typically contain:

ple_summary.csv: compact effect estimate summary (when an outcome model can be fitted),

outcome_model.rds: fitted outcome model object (may be absent or empty if no outcomes or no adjusted subjects),

ps.rds: propensity score object,

population.rds: adjusted population object.

The exact content of the model objects and whether a summary file is produced depends on the installed OHDSI package versions and on whether the design actually yields any outcomes in the adjusted population.

8. Why this is called a “safe” version
This version includes a few safeguards compared with a rough prototype:

explicit CohortMethod::createPrior(...) usage,

explicit passing of cmDataConfig into the cohort-generation function,

basic validation of key settings,

simple logging,

safer export code that does not fail if the adjusted population is empty or if no outcomes are observed (for example it logs a message instead of throwing an error).

These changes make the project easier to run, debug, and adapt without changing the underlying OHDSI logic.

9. Known limitations
This is still a v1 starter, not a production-ready study package.

In particular:

some function arguments may differ slightly across package versions, so the wrappers rely on *Args objects to improve robustness,

diagnostics are still minimal,

negative controls and empirical calibration are not yet implemented,

large-scale multi-analysis support is not yet included,

on small example datasets (for example Eunomia), some combinations of target/comparator/outcome may yield very few subjects or no outcomes, in which case the pipeline will run but no effect estimate can be computed.

10. Recommended next steps
Once the first run works, the next sensible improvements are:

add richer diagnostics,

support multiple adjustment branches in one run,

save cohort counts and attrition summaries,

add negative-control analyses,

move toward a more structured multi-analysis OHDSI pipeline.

