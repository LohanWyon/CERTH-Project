# ============================================================
# SynPUF 1k — Reproducible OMOP CDM Access Script
# ============================================================


# 1) Install missing packages
packages <- c("CDMConnector", "duckdb", "DBI", "dplyr")
to_install <- packages[!sapply(packages, requireNamespace, quietly = TRUE)]


if (length(to_install) > 0) {
  install.packages(to_install)
}


# 2) Load required packages
library(CDMConnector)
library(duckdb)
library(DBI)
library(dplyr)


# 3) Automatically define a local folder for Eunomia / SynPUF data
data_folder <- file.path(Sys.getenv("USERPROFILE"), "Documents", "eunomia_data")
dir.create(data_folder, showWarnings = FALSE, recursive = TRUE)


Sys.setenv(EUNOMIA_DATA_FOLDER = data_folder)


cat("Data folder:", data_folder, "\n")
cat("EUNOMIA_DATA_FOLDER variable =", Sys.getenv("EUNOMIA_DATA_FOLDER"), "\n")


# 4) Download or reuse SynPUF 1k dataset
synpuf_dir <- eunomiaDir("synpuf-1k")
cat("Dataset path:", synpuf_dir, "\n")


# 5) Open the DuckDB database
con <- DBI::dbConnect(duckdb::duckdb(), synpuf_dir)


# 6) Access OMOP tables as dplyr tbl objects
person_tbl <- dplyr::tbl(con, "person")
visit_tbl  <- dplyr::tbl(con, "visit_occurrence")


# 7) Basic checks
cat("\n=== Available tables ===\n")
print(DBI::dbListTables(con))


cat("\n=== Number of patients ===\n")
print(
  person_tbl %>%
    tally() %>%
    collect()
)


cat("\n=== Preview of person table ===\n")
print(
  person_tbl %>%
    head(5) %>%
    collect()
)


cat("\n=== Number of visits by type ===\n")
print(
  visit_tbl %>%
    group_by(visit_concept_id) %>%
    tally() %>%
    arrange(desc(n)) %>%
    collect()
)


cat("\n=== Gender distribution ===\n")
print(
  person_tbl %>%
    group_by(gender_concept_id) %>%
    tally() %>%
    arrange(desc(n)) %>%
    collect()
)


# 8) Example: simple join between PERSON and VISIT_OCCURRENCE
cat("\n=== Visits by gender and visit type ===\n")
person_visit <- visit_tbl %>%
  inner_join(person_tbl, by = "person_id")


print(
  person_visit %>%
    group_by(gender_concept_id, visit_concept_id) %>%
    tally() %>%
    arrange(desc(n)) %>%
    collect()
)


# 9) Close the connection if needed
DBI::dbDisconnect(con, shutdown = TRUE)