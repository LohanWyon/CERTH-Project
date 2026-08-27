library(DatabaseConnector)
library(CDMConnector)

conn_details <- DatabaseConnector::createConnectionDetails(
  dbms = "duckdb",
  server = CDMConnector::eunomiaDir(datasetName = "synpuf-110k")
)

conn <- DatabaseConnector::connect(conn_details)

cohort_tables <- c(
  "main.cohort",
  "main.cohort_inclusion",
  "main.cohort_inclusion_result",
  "main.cohort_inclusion_stats",
  "main.cohort_summary_stats",
  "main.cohort_censor_stats",
  "main.cohort_subset_attrition",
  "main.cohort_checksum"
)

tryCatch(
  {
    for (table_name in cohort_tables) {
      message("Dropping: ", table_name)

      DatabaseConnector::executeSql(
        conn,
        paste("DROP TABLE IF EXISTS", table_name)
      )
    }

    message("Cohort tables deleted.")
  },
  finally = {
    DatabaseConnector::disconnect(conn)
    message("Connection closed.")
  }
)