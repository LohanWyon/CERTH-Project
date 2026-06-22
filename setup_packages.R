# setup_packages.R

cran_packages <- c(
  "shiny",
  "bslib",
  "DT",
  "readr",
  "plotly"
)

ohdsi_packages <- c(
  "DatabaseConnector",
  "SqlRender",
  "FeatureExtraction",
  "CohortMethod",
  "Cyclops",
  "CohortGenerator",
  "CirceR",
  "CDMConnector"
)

install_if_missing <- function(pkgs, repos = getOption("repos")) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

  if (length(missing) == 0) {
    message("All packages already installed: ", paste(pkgs, collapse = ", "))
    return(invisible(character(0)))
  }

  message("Installing missing packages: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = repos)

  still_missing <- missing[!vapply(missing, requireNamespace, logical(1), quietly = TRUE)]
  if (length(still_missing) > 0) {
    warning("Some packages are still missing after installation: ",
            paste(still_missing, collapse = ", "))
  } else {
    message("Installation successful for: ", paste(missing, collapse = ", "))
  }

  invisible(still_missing)
}

ensure_ohdsi_repo <- function() {
  if (!requireNamespace("drat", quietly = TRUE)) {
    install.packages("drat", repos = "https://cloud.r-project.org")
  }

  drat::addRepo("OHDSI")

  current_repos <- getOption("repos")
  if (!"OHDSI" %in% names(current_repos)) {
    current_repos["OHDSI"] <- "https://ohdsi.github.io/drat/"
    options(repos = current_repos)
  }

  invisible(getOption("repos"))
}

check_java <- function() {
  java_home <- Sys.getenv("JAVA_HOME", unset = "")
  message("JAVA_HOME: ", ifelse(nzchar(java_home), java_home, "(not set)"))

  java_available <- nzchar(Sys.which("java"))
  message("java executable available: ", java_available)

  invisible(java_available)
}

check_rtools_if_windows <- function() {
  if (.Platform$OS.type == "windows") {
    has_rtools <- nzchar(Sys.which("make"))
    message("Rtools / make available: ", has_rtools)
    invisible(has_rtools)
  } else {
    invisible(TRUE)
  }
}

message("=== Checking base environment ===")
message("R version: ", R.version.string)
check_java()
check_rtools_if_windows()

message("=== Installing CRAN packages ===")
install_if_missing(
  pkgs = cran_packages,
  repos = "https://cloud.r-project.org"
)

message("=== Configuring OHDSI repository ===")
ensure_ohdsi_repo()

message("=== Installing OHDSI packages ===")
install_if_missing(
  pkgs = ohdsi_packages,
  repos = getOption("repos")
)

all_required <- c(cran_packages, ohdsi_packages)
still_missing <- all_required[!vapply(all_required, requireNamespace, logical(1), quietly = TRUE)]

message("=== Final status ===")
if (length(still_missing) == 0) {
  message("All required packages are available.")
} else {
  message("Missing packages remain: ", paste(still_missing, collapse = ", "))
}