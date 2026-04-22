# OMOP CDM Exploration and Patient-Level Prediction Prototypes

This repository contains R scripts and utilities for working with data in the OMOP Common Data Model (CDM), focusing on:

- connecting to an OMOP CDM instance via the OHDSI `DatabaseConnector` ecosystem,
- exploring and understanding the CDM structure,
- building cohorts from ATLAS-exported definitions,
- experimenting with Patient-Level Prediction (PLP) workflows.

The `main` branch is intended for the **core project code and reusable patterns**, while dedicated branches (e.g. `feature/...`) can host self-contained demos or experiments (such as synthetic-data examples).

## Design principles

The code in this repository is being structured to be:

- **DBMS-agnostic**: connections are handled through `DatabaseConnector::createConnectionDetails()`, so the same scripts can in principle be reused with different OMOP CDM backends (e.g. DuckDB for local examples, PostgreSQL, SQL Server, …) by changing only the connection settings.
- **Configuration-driven**: study-specific details (connection parameters, cohort IDs, ATLAS JSON paths, covariate settings, model choices, runtime options) are intended to live in small configuration files rather than in the main execution scripts.
- **Composable and modular**: cohort generation, data extraction, and PLP model training are split into clearly defined steps that can be reused and adapted per project.

## Project structure (main branch)

The exact structure may evolve, but the main branch is expected to contain:

- Core R scripts for:
  - defining and using connection settings to an OMOP CDM instance,
  - running exploratory queries on CDM tables,
  - preparing and extracting data for analyses (e.g. PLP).
- Configuration and utility code:
  - environment setup scripts (package checks, Java checks, etc.),
  - external configuration files controlling connection details, cohorts, covariates, models, and runtime parameters.
- Documentation for how to adapt these components to a specific OMOP CDM and analysis.

As the project progresses, these elements will form the foundation for the concrete study code that will live on `main`.

## Getting started (main project)

1. Clone the repository:

   ```bash
   git clone https://github.com/LohanWyon/CERTH-Project.git
   cd CERTH-Project
   ```

2. Check out the main branch:

   ```bash
   git checkout main
   ```

3. In R, install and verify the required packages if needed, for example using the environment setup script (when present):

   ```r
   source("setup_plp_environment.R")
   ```

4. Open the project in RStudio or your preferred IDE and inspect the configuration files and scripts in the `config/` and root directories to adapt them to your OMOP CDM instance (connection details, schemas, cohort definitions, etc.).

## Feature branches

Beyond the `main` branch, this repository also uses dedicated `feature/...` branches to develop and demonstrate specific workflows.

These feature branches are typically:

- **self-contained**: they bundle the scripts, configuration files, and example data needed to run a particular demo or prototype (for example a PLP pipeline on synthetic SynPUF/Eunomia data),
- **focused**: each branch targets a specific aspect of the project (e.g. environment setup, PLP prototyping, cohort generation patterns),
- **documented locally**: each feature branch usually includes its own README describing the branch-specific usage, assumptions, and limitations.

This keeps the `main` branch focused on the core, reusable patterns, while allowing experiments and demos to evolve independently in their own branches.

## Contribution and Git workflow

- New work should be done on dedicated branches (for example `feature/...`, `fix/...`, or `experiment/...`).
- Changes to `main` should go through a **pull request**.
- The `main` branch is intended to remain stable and focused on the core project logic and patterns.

This workflow keeps `main` clean, while still allowing rapid iteration on feature and experiment branches.

## Notes

- Synthetic-data examples (e.g. based on SynPUF/Eunomia) are useful for learning and testing, but are not intended for real clinical modelling.
- The patterns used here (DBMS-agnostic connections, configuration-driven scripts, ATLAS JSON cohorts with `CirceR` + `CohortGenerator`, PLP workflows) are meant to be reusable when moving from synthetic examples to real OMOP CDM data.
- When applying these patterns to real data, it is important to define clinically meaningful cohorts, covariates, and prediction targets, and to have them reviewed appropriately.