# ============================================================
# SynPUF 1k — Script reproductible OMOP CDM (sans cdm_from_con)
# ============================================================

# 1) Installer les packages manquants
packages <- c("CDMConnector", "duckdb", "DBI", "dplyr")
to_install <- packages[!sapply(packages, requireNamespace, quietly = TRUE)]

if (length(to_install) > 0) {
  install.packages(to_install)
}

# 2) Charger les packages
library(CDMConnector)
library(duckdb)
library(DBI)
library(dplyr)

# 3) Définir automatiquement un dossier local pour Eunomia / SynPUF
data_folder <- file.path(Sys.getenv("USERPROFILE"), "Documents", "eunomia_data")
dir.create(data_folder, showWarnings = FALSE, recursive = TRUE)

Sys.setenv(EUNOMIA_DATA_FOLDER = data_folder)

cat("Dossier de données :", data_folder, "\n")
cat("Variable EUNOMIA_DATA_FOLDER =", Sys.getenv("EUNOMIA_DATA_FOLDER"), "\n")

# 4) Télécharger ou réutiliser SynPUF 1k
synpuf_dir <- eunomiaDir("synpuf-1k")
cat("Chemin du dataset :", synpuf_dir, "\n")

# 5) Ouvrir la base DuckDB
con <- DBI::dbConnect(duckdb::duckdb(), synpuf_dir)

# 6) Récupérer les tables OMOP comme tbl dplyr
person_tbl <- dplyr::tbl(con, "person")
visit_tbl  <- dplyr::tbl(con, "visit_occurrence")

# 7) Vérifications de base
cat("\n=== Tables disponibles ===\n")
print(DBI::dbListTables(con))

cat("\n=== Nombre de patients ===\n")
print(
  person_tbl %>%
    tally() %>%
    collect()
)

cat("\n=== Aperçu de person ===\n")
print(
  person_tbl %>%
    head(5) %>%
    collect()
)

cat("\n=== Nombre de visites par type ===\n")
print(
  visit_tbl %>%
    group_by(visit_concept_id) %>%
    tally() %>%
    arrange(desc(n)) %>%
    collect()
)

cat("\n=== Répartition par sexe ===\n")
print(
  person_tbl %>%
    group_by(gender_concept_id) %>%
    tally() %>%
    arrange(desc(n)) %>%
    collect()
)

# 8) Exemple de jointure simple PERSON + VISIT_OCCURRENCE
cat("\n=== Visites par sexe et type de visite ===\n")
person_visit <- visit_tbl %>%
  inner_join(person_tbl, by = "person_id")

print(
  person_visit %>%
    group_by(gender_concept_id, visit_concept_id) %>%
    tally() %>%
    arrange(desc(n)) %>%
    collect()
)

# 9) Fermer la connexion si besoin
DBI::dbDisconnect(con, shutdown = TRUE)