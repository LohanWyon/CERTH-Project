# plp_config_synpuf.R
# Configuration PLP pour SynPUF 1k sur DuckDB via CDMConnector

# Type de base
dbms <- "duckdb"

# Chemin du dataset exemple SynPUF 1k (CDMConnector)
synpuf_name <- "synpuf-1k"

# Schémas CDM/cohortes/outcomes dans DuckDB
cdmDatabaseSchema     <- "main"
cdmDatabaseName       <- "SynPUF_1k_DuckDB"
cohortDatabaseSchema  <- "main"
cohortTable           <- "cohort"
outcomeDatabaseSchema <- "main"
outcomeTable          <- "cohort"

# IDs de cohortes (définis dans le code principal quand on crée main.cohort)
targetCohortId  <- 1L
outcomeCohortId <- 2L

# Réglages PLP
sampleSizePlp <- 10000

# Répertoire de sortie pour les résultats PLP
outputFolder <- file.path(getwd(), "plp_synpuf_duckdb_output")