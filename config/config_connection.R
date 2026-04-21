# config/config_connection.R
# Connection and CDM settings

dbms <- "duckdb"

# Example dataset name for Eunomia / SynPUF-like example data
synpufName <- "synpuf-1k"

# Path to local DuckDB database
server <- CDMConnector::eunomiaDir(synpufName)

# CDM settings
cdmDatabaseSchema <- "main"
cdmDatabaseName <- "SynPUF_1k_DuckDB"
cdmVersion <- "5.3"

# Temp schema used by PLP
tempEmulationSchema <- "main"

# Cohort / outcome schemas
cohortDatabaseSchema <- "main"
outcomeDatabaseSchema <- "main"