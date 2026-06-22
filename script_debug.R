library(DBI)
library(duckdb)
library(CDMConnector)

db_path <- CDMConnector::eunomiaDir()

con <- dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = TRUE)

cat("DuckDB path:\n", db_path, "\n\n")

cat("Tables in schema main:\n")
print(dbGetQuery(con, "
  SELECT table_schema, table_name
  FROM information_schema.tables
  WHERE table_schema = 'main'
  ORDER BY table_name
"))

cat("\nCounts for cohort_definition_id 101, 102, 201:\n")
print(dbGetQuery(con, "
  SELECT
    cohort_definition_id,
    COUNT(*) AS n_rows,
    COUNT(DISTINCT subject_id) AS n_subjects,
    MIN(cohort_start_date) AS min_start_date,
    MAX(cohort_start_date) AS max_start_date
  FROM main.cohort
  WHERE cohort_definition_id IN (101, 102, 201)
  GROUP BY cohort_definition_id
  ORDER BY cohort_definition_id
"))

cat("\nA few example rows:\n")
print(dbGetQuery(con, "
  SELECT
    cohort_definition_id,
    subject_id,
    cohort_start_date,
    cohort_end_date
  FROM main.cohort
  WHERE cohort_definition_id IN (101, 102, 201)
  ORDER BY cohort_definition_id, subject_id
  LIMIT 20
"))

dbDisconnect(con, shutdown = TRUE)