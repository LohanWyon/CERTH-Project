# ============================================================
# 03_demo_plp_like_model.R — Simple logistic model on SynPUF cohorts
# ============================================================

source("00_setup_synpuf.R")

# 1) Open DuckDB connection
con <- DBI::dbConnect(duckdb::duckdb(), synpuf_db_path)

cat("\n=== Available tables ===\n")
print(DBI::dbListTables(con))

if (!"cohort" %in% DBI::dbListTables(con)) {
  DBI::dbDisconnect(con, shutdown = TRUE)
  stop("Table 'cohort' not found. Run 02_build_demo_cohorts.R first.")
}

# 2) Get cohort and person tables
cohort_tbl <- tbl(con, "cohort")
person_tbl <- tbl(con, "person")

cat("\n=== Cohort preview ===\n")
print(cohort_tbl %>% head() %>% collect())

cat("\n=== Person preview ===\n")
print(person_tbl %>% head() %>% collect())

# 3) Cohort IDs
targetId  <- 1L
outcomeId <- 2L

# 4) Target population
target_pop <- cohort_tbl %>%
  filter(cohort_definition_id == targetId) %>%
  select(subject_id, cohort_start_date, cohort_end_date) %>%
  collect()

# 5) Outcome population
outcome_pop <- cohort_tbl %>%
  filter(cohort_definition_id == outcomeId) %>%
  select(subject_id, cohort_start_date) %>%
  collect()

# 6) Build labelled population
population <- target_pop %>%
  left_join(
    outcome_pop %>%
      mutate(hadOutcome = 1L),
    by = "subject_id",
    suffix = c("", "_outcome")
  ) %>%
  mutate(
    outcomeCount = ifelse(is.na(hadOutcome), 0L, 1L),
    outcomeId = outcomeId
  )

cat("\n=== Population outcome counts ===\n")
print(table(population$outcomeCount))

# 7) Simple demographic covariates from person
person_df <- person_tbl %>% collect()

covariates_df <- person_df %>%
  select(
    subject_id = person_id,
    year_of_birth,
    gender_concept_id
  ) %>%
  inner_join(select(population, subject_id, outcomeCount), by = "subject_id") %>%
  mutate(
    age = 2020L - year_of_birth,                     # rough approximation
    gender_male = ifelse(gender_concept_id == 8507, 1L, 0L)  # 8507 = Male
  ) %>%
  select(subject_id, age, gender_male, outcomeCount)

cat("\n=== Head covariates_df ===\n")
print(head(covariates_df))

# 8) Train/test split and glmnet model
set.seed(123)
n <- nrow(covariates_df)
train_idx <- sample(seq_len(n), size = floor(0.75 * n))
test_idx  <- setdiff(seq_len(n), train_idx)

train_x <- as.matrix(covariates_df[train_idx, c("age", "gender_male")])
train_y <- covariates_df$outcomeCount[train_idx]

test_x  <- as.matrix(covariates_df[test_idx, c("age", "gender_male")])
test_y  <- covariates_df$outcomeCount[test_idx]

fit <- glmnet(
  x = train_x,
  y = train_y,
  family = "binomial",
  alpha = 1
)

pred_prob <- predict(fit, newx = test_x, type = "response")[, 1]

# 9) Quick AUC
auc_val <- pROC::auc(test_y, pred_prob)
cat("\nApproximate AUC (age + gender):", as.numeric(auc_val), "\n")

# 10) Clean up
DBI::dbDisconnect(con, shutdown = TRUE)

# Optional: remove the demo DuckDB instance after the full pipeline
if (file.exists(synpuf_db_path)) {
  file.remove(synpuf_db_path)
  cat("\nSynPUF demo DuckDB instance removed:", synpuf_db_path, "\n")
}