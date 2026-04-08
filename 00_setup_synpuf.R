# ============================================================
# 00_setup_synpuf.R — Common setup for SynPUF OMOP + PLP demos
# ============================================================

# 1) Install missing packages (run once if needed)
base_packages <- c("CDMConnector", "duckdb", "DBI", "dplyr", "dbplyr")
ml_packages   <- c("PatientLevelPrediction", "glmnet", "pROC")

all_packages <- c(base_packages, ml_packages)
to_install <- all_packages[!sapply(all_packages, requireNamespace, quietly = TRUE)]

if (length(to_install) > 0) {
  install.packages(to_install)
}

# 2) Load core packages
library(CDMConnector)
library(duckdb)
library(DBI)
library(dplyr)
library(dbplyr)
library(PatientLevelPrediction)
library(glmnet)
library(pROC)

# 3) Define SynPUF/Eunomia data folder
data_folder <- file.path(Sys.getenv("USERPROFILE"), "Documents", "eunomia_data")
dir.create(data_folder, showWarnings = FALSE, recursive = TRUE)
Sys.setenv(EUNOMIA_DATA_FOLDER = data_folder)

cat("Data folder:", data_folder, "\n")
cat("EUNOMIA_DATA_FOLDER =", Sys.getenv("EUNOMIA_DATA_FOLDER"), "\n")

# 4) Get or download SynPUF 1k and store DuckDB path in a variable
synpuf_db_path <- eunomiaDir("synpuf-1k")
cat("SynPUF DuckDB path:", synpuf_db_path, "\n")