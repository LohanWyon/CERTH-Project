# ============================================================
# 02_build_demo_cohorts.R — Build simple OMOP cohorts in SynPUF
# ============================================================

source("00_setup_synpuf.R")

# 1) Open DuckDB connection
con <- DBI::dbConnect(duckdb::duckdb(), synpuf_db_path)

# 2) Load OMOP tables
person_tbl <- tbl(con, "person")
visit_tbl  <- tbl(con, "visit_occurrence")

# ------------------------------------------------------------
# Demo cohort strategy
# ------------------------------------------------------------
# cohort_definition_id = 1 --> target cohort
#   Example: all persons with at least one visit
#
# cohort_definition_id = 2 --> outcome cohort
#   Example: persons with at least one inpatient visit
#
# This is NOT a scientific study design.
# It is only a simple setup to test the PLP-style pipeline.

# 3) Target cohort: all persons with at least one visit
target_cohort <- visit_tbl %>%
  group_by(person_id) %>%
  summarise(
    cohort_start_date = min(visit_start_date, na.rm = TRUE),
    cohort_end_date   = max(visit_end_date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  transmute(
    cohort_definition_id = 1L,
    subject_id = person_id,
    cohort_start_date = as.Date(cohort_start_date),
    cohort_end_date   = as.Date(cohort_end_date)
  ) %>%
  collect()

# 4) Outcome cohort: persons with at least one inpatient visit (9201)
outcome_cohort <- visit_tbl %>%
  filter(visit_concept_id == 9201) %>%
  group_by(person_id) %>%
  summarise(
    cohort_start_date = min(visit_start_date, na.rm = TRUE),
    cohort_end_date   = max(visit_end_date, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  transmute(
    cohort_definition_id = 2L,
    subject_id = person_id,
    cohort_start_date = as.Date(cohort_start_date),
    cohort_end_date   = as.Date(cohort_end_date)
  ) %>%
  collect()

# 5) Combine into a single OMOP-style cohort table
cohort_df <- bind_rows(target_cohort, outcome_cohort)

cat("\n=== Cohort counts in R ===\n")
print(cohort_df %>% count(cohort_definition_id))

# 6) Write cohort table into DuckDB
if ("cohort" %in% DBI::dbListTables(con)) {
  DBI::dbRemoveTable(con, "cohort")
}

DBI::dbWriteTable(con, "cohort", cohort_df, overwrite = TRUE)

cat("\n=== Cohort table created in DuckDB ===\n")
print(DBI::dbReadTable(con, "cohort") %>% head())

# 7) Verify counts directly from DuckDB
cohort_tbl <- tbl(con, "cohort")

cat("\n=== Cohort counts from DuckDB ===\n")
print(
  cohort_tbl %>%
    group_by(cohort_definition_id) %>%
    tally() %>%
    collect()
)

# 8) Overlap between target and outcome
cat("\n=== Persons in target and outcome cohorts ===\n")
target_n <- cohort_df %>% filter(cohort_definition_id == 1) %>% pull(subject_id) %>% unique()
outcome_n <- cohort_df %>% filter(cohort_definition_id == 2) %>% pull(subject_id) %>% unique()

cat("Target cohort persons:", length(target_n), "\n")
cat("Outcome cohort persons:", length(outcome_n), "\n")
cat("Overlap:", length(intersect(target_n, outcome_n)), "\n")

# 9) Close connection
DBI::dbDisconnect(con, shutdown = TRUE)