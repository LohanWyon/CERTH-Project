# config/config_connection.R
# Connection and CDM settings

# Database management system
# Examples: "duckdb", "postgresql", "sql server", "oracle", "redshift", "sqlite"
dbms <- "duckdb"

# ------------------------------------------------
# Server / database location
# ------------------------------------------------
# The meaning of `server` depends on the DBMS:
#
# - For DuckDB:
#   `server` can be a local database file or an example OMOP CDM directory,
#   such as the Eunomia / SynPUF-like dataset used for development.
#
# - For other database systems:
#   `server` can be defined directly as the database host, URL,
#   or connection string required by DatabaseConnector.
#
# Examples:
#   DuckDB      -> server <- CDMConnector::eunomiaDir(datasetName = "synpuf-1k")
#   PostgreSQL  -> server <- "localhost/omop_cdm"
#   SQL Server  -> server <- "myserver"
#   Remote host -> server <- "jdbc:postgresql://hostname:5432/omop_cdm"
#
# Default example: local Eunomia/SynPUF-like OMOP CDM for development
databaseId <- "synpuf-1k"
server <- CDMConnector::eunomiaDir(datasetName = databaseId)

# Optional connection parameters for non-DuckDB databases
user <- NULL
password <- NULL
port <- NULL
pathToDriver <- NULL

# CDM metadata
cdmDatabaseSchema <- "main"
cdmDatabaseName <- "OMOP_CDM_instance"
cdmVersion <- "5.3"

# Temporary schema used by PLP
# This may need to be adapted depending on the target DBMS
tempEmulationSchema <- cdmDatabaseSchema

# Cohort / outcome schemas
cohortDatabaseSchema <- cdmDatabaseSchema
outcomeDatabaseSchema <- cdmDatabaseSchema