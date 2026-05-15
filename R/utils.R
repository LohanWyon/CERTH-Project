# utils.R

required_packages <- c(
  "DatabaseConnector",
  "SqlRender",
  "CohortGenerator",
  "CirceR",
  "FeatureExtraction",
  "CohortMethod",
  "CDMConnector",
  "jsonlite",
  "readr"
)

check_required_packages <- function(pkgs = required_packages) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop("Missing required packages: ", paste(missing, collapse = ", "))
  }
}

create_connection_details <- function(connectionConfig) {
  args <- list(
    dbms = connectionConfig$dbms,
    server = connectionConfig$server,
    user = connectionConfig$user,
    password = connectionConfig$password,
    port = connectionConfig$port,
    pathToDriver = connectionConfig$pathToDriver
  )
  args <- args[!vapply(args, is.null, logical(1))]
  do.call(DatabaseConnector::createConnectionDetails, args)
}

ensure_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
}

assert_non_empty_scalar <- function(x, name) {
  if (is.null(x) || length(x) != 1 || is.na(x) || !nzchar(as.character(x))) {
    stop(sprintf("Invalid value for %s", name))
  }
}