connectionConfig <- list(
  dbms = "duckdb",
  server = CDMConnector::eunomiaDir(datasetName = "synpuf-1k", cdmVersion = "5.3"),
  user = NULL,
  password = NULL,
  port = NULL,
  pathToDriver = NULL,
  oracleTempSchema = NULL
)