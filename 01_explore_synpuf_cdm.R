# ============================================================
# 01_explore_synpuf_cdm.R — Basic OMOP CDM exploration on SynPUF
# ============================================================

source("00_setup_synpuf.R")

# 1) Open DuckDB connection
con <- DBI::dbConnect(duckdb::duckdb(), synpuf_db_path)

# 2) Access OMOP tables
person_tbl <- dplyr::tbl(con, "person")
visit_tbl  <- dplyr::tbl(con, "visit_occurrence")

# 3) Basic checks
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

# 4) Simple join example
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

# 5) Close connection
DBI::dbDisconnect(con, shutdown = TRUE)