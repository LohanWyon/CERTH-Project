# explore_eunomia.R

library(CDMConnector)
library(DBI)
library(dplyr)
library(readr)

# 1) Ouvrir Eunomia (synpuf-1k, cdm v5.3) en DuckDB
db_path <- CDMConnector::eunomiaDir(datasetName = "synpuf-1k", cdmVersion = "5.3")
message("Eunomia DuckDB path: ", db_path)

con <- DBI::dbConnect(duckdb::duckdb(), db_path)

# 2) Références vers les tables OMOP
drug_exposure_tbl <- dplyr::tbl(con, DBI::Id(schema = "main", table = "drug_exposure"))
condition_occurrence_tbl <- dplyr::tbl(con, DBI::Id(schema = "main", table = "condition_occurrence"))
concept_tbl <- dplyr::tbl(con, DBI::Id(schema = "main", table = "concept"))

# 3) Top drugs (on collecte puis on prend head(20))
top_drugs <- drug_exposure_tbl %>%
  group_by(drug_concept_id) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n)) %>%
  left_join(
    concept_tbl %>%
      select(concept_id, concept_name, concept_class_id, vocabulary_id),
    by = c("drug_concept_id" = "concept_id")
  ) %>%
  collect() %>%
  head(20)

message("Top drugs:")
print(top_drugs)

# 4) Top conditions
top_conditions <- condition_occurrence_tbl %>%
  group_by(condition_concept_id) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n)) %>%
  left_join(
    concept_tbl %>%
      select(concept_id, concept_name, concept_class_id, vocabulary_id),
    by = c("condition_concept_id" = "concept_id")
  ) %>%
  collect() %>%
  head(20)

message("Top conditions:")
print(top_conditions)

# 5) Sauvegarder dans des CSV pour référence
if (!dir.exists("explore")) dir.create("explore")

write_csv(top_drugs, "explore/top_drugs.csv")
write_csv(top_conditions, "explore/top_conditions.csv")

DBI::dbDisconnect(con, shutdown = TRUE)
message("Exploration done. CSVs written to explore/ directory.")