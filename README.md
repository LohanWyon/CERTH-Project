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


## Getting started (main project)

1. Clone the repository:
   ```bash
   git clone https://github.com/LohanWyon/CERTH-Project.git
   cd <your-repo-folder>
   ```

2. Check out the main branch:
   ```bash
   git checkout main
   ```

3. Open the project in RStudio or your preferred IDE and follow the instructions in the project-specific scripts/documentation (connection settings, CDM schema names, etc.).


## Contribution and Git workflow

- New work should be done on dedicated branches (for example `feature/...`, `fix/...`, or `experiment/...`).
- Changes to `main` should go through a **pull request**.
- The `main` branch is protected: merging into `main` requires a PR and at least one review/approval.


## Notes

- The SynPUF demo is based on a small, synthetic dataset and uses simplified cohort definitions and covariates. It is meant for **learning and testing**, not for real clinical modelling.
- The main branch should remain focused on the actual project data and workflows.