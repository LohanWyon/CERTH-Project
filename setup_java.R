# setup_java.R

setup_java <- function() {
  # Charger rJava
  if (!requireNamespace("rJava", quietly = TRUE)) {
    stop("Package 'rJava' is required but not installed.")
  }

  library(rJava)

  # Ne réinitialise pas si la JVM tourne déjà
  jstat <- try(.jinit(), silent = TRUE)

  # Ajouter commons-io dans le classpath
  jar_path <- "C:/Users/lohan/java_libs/commons-io-2.22.0.jar"

  if (!file.exists(jar_path)) {
    warning("commons-io JAR not found at: ", jar_path,
            "\nCohortGenerator/CirceR may fail with IOUtils errors.")
  } else {
    .jaddClassPath(jar_path)
  }

  invisible(NULL)
}