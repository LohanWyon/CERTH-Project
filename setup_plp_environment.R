# setup_plp_environment.R
# Manual setup script for the PLP + CohortGenerator + CirceR environment

options(repos = c(
  OHDSI = "https://ohdsi.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))

cat("========================================\n")
cat("PLP environment setup and verification\n")
cat("========================================\n\n")

# ---------------------------
# Helper functions
# ---------------------------
is_installed <- function(pkg) {
  requireNamespace(pkg, quietly = TRUE)
}

install_if_missing <- function(pkg, repos = getOption("repos")) {
  if (!is_installed(pkg)) {
    cat(sprintf("Installing package: %s\n", pkg))
    install.packages(pkg, repos = repos)
  } else {
    cat(sprintf("Package already installed: %s\n", pkg))
  }
}

install_github_if_missing <- function(pkg, repo) {
  if (!is_installed(pkg)) {
    if (!is_installed("remotes")) {
      cat("Installing package: remotes\n")
      install.packages("remotes", repos = getOption("repos"))
    }
    cat(sprintf("Installing GitHub package: %s from %s\n", pkg, repo))
    remotes::install_github(repo, upgrade = "never")
  } else {
    cat(sprintf("Package already installed: %s\n", pkg))
  }
}

check_library <- function(pkg) {
  cat(sprintf("Loading %s ... ", pkg))
  ok <- suppressPackageStartupMessages(
    require(pkg, character.only = TRUE, quietly = TRUE)
  )
  if (ok) {
    cat("OK\n")
    return(TRUE)
  } else {
    cat("FAILED\n")
    return(FALSE)
  }
}

# ---------------------------
# R version check
# ---------------------------
cat("==> Checking R version\n")
cat(sprintf("R version detected: %s\n\n", R.version.string))

# ---------------------------
# Java check
# ---------------------------
cat("==> Checking Java\n")
java_path <- Sys.which("java")

if (nzchar(java_path)) {
  cat(sprintf("Java found at: %s\n", java_path))
  java_version <- tryCatch(
    system2("java", args = "-version", stdout = TRUE, stderr = TRUE),
    error = function(e) paste("Unable to run java -version:", e$message)
  )
  cat(paste(java_version, collapse = "\n"), "\n\n")
} else {
  cat("WARNING: Java was not found in PATH.\n")
  cat("CirceR and some OHDSI tools may require Java.\n\n")
}

# ---------------------------
# Core package lists
# ---------------------------
cran_packages <- c(
  "DBI",
  "duckdb",
  "dplyr",
  "remotes"
)

ohdsi_repo_packages <- c(
  "CDMConnector",
  "DatabaseConnector",
  "FeatureExtraction",
  "PatientLevelPrediction",
  "CohortGenerator"
)

github_fallback_packages <- list(
  CirceR = "OHDSI/CirceR"
)

# ---------------------------
# Install CRAN packages
# ---------------------------
cat("==> Installing/verifying CRAN packages\n")
for (pkg in cran_packages) {
  install_if_missing(pkg)
}
cat("\n")

# ---------------------------
# Install OHDSI repo packages
# ---------------------------
cat("==> Installing/verifying OHDSI packages from repositories\n")
for (pkg in ohdsi_repo_packages) {
  install_if_missing(pkg)
}
cat("\n")

# ---------------------------
# Install GitHub fallback packages
# ---------------------------
cat("==> Installing/verifying GitHub-based OHDSI packages\n")
for (pkg in names(github_fallback_packages)) {
  install_github_if_missing(pkg, github_fallback_packages[[pkg]])
}
cat("\n")

# ---------------------------
# Verify package loading
# ---------------------------
cat("==> Verifying package loading\n")
required_packages <- c(
  "CDMConnector",
  "DatabaseConnector",
  "PatientLevelPrediction",
  "CohortGenerator",
  "CirceR",
  "duckdb",
  "DBI",
  "dplyr",
  "FeatureExtraction"
)

load_results <- vapply(required_packages, check_library, logical(1))
cat("\n")

# ---------------------------
# Optional PLP install check
# ---------------------------
cat("==> Optional PatientLevelPrediction installation check\n")
if (is_installed("PatientLevelPrediction")) {
  cat("PatientLevelPrediction is installed.\n")
  cat("You can also run PatientLevelPrediction::checkPlpInstallation()\n")
  cat("later with real connection details if needed.\n\n")
} else {
  cat("PatientLevelPrediction is not installed correctly.\n\n")
}

# ---------------------------
# Summary
# ---------------------------
cat("==> Summary\n")

missing_packages <- required_packages[!vapply(required_packages, is_installed, logical(1))]

if (length(missing_packages) == 0 && all(load_results)) {
  cat("All required packages are installed and load correctly.\n")
} else {
  cat("Some packages are still missing or failed to load:\n")
  for (pkg in required_packages[!load_results]) {
    cat(sprintf("- %s\n", pkg))
  }
}

if (!nzchar(java_path)) {
  cat("\nWARNING: Java is missing from PATH.\n")
  cat("If CirceR fails later, install/configure Java first.\n")
}

cat("\nSetup script finished.\n")