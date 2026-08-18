library(DatabaseConnector)
library(CDMConnector)

# Se connecter à la DB Eunomia 110k
conn_details <- DatabaseConnector::createConnectionDetails(
  dbms = "duckdb",
  server = CDMConnector::eunomiaDir(datasetName = "synpuf-110k")
)

conn <- DatabaseConnector::connect(conn_details)

# Supprimer la table cohort
DatabaseConnector::executeSql(conn, "DROP TABLE IF EXISTS main.cohort")
DatabaseConnector::executeSql(conn, "DROP TABLE IF EXISTS main.cohort_inclusion")
DatabaseConnector::executeSql(conn, "DROP TABLE IF EXISTS main.cohort_inclusion_result")
DatabaseConnector::executeSql(conn, "DROP TABLE IF EXISTS main.cohort_inclusion_stats")
DatabaseConnector::executeSql(conn, "DROP TABLE IF EXISTS main.cohort_summary_stats")
DatabaseConnector::executeSql(conn, "DROP TABLE IF EXISTS main.cohort_censor_stats")

DatabaseConnector::disconnect(conn)