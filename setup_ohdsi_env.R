# setup_ohdsi_env.R

message("=== Checking Java / rJava / SqlRender environment ===")

print(Sys.which("java"))
system("java -version")

ok <- TRUE

message("\n[1] Testing rJava...")
if (!requireNamespace("rJava", quietly = TRUE)) {
  message("  - rJava not installed, installing...")
  install.packages("rJava")
}
library(rJava)
tryCatch(
  {
    .jinit()
    jv <- .jcall("java/lang/System", "S", "getProperty", "java.version")
    message("  - rJava OK, Java version: ", jv)
  },
  error = function(e) {
    ok <<- FALSE
    message("  - rJava ERROR: ", conditionMessage(e))
  }
)

message("\n[2] Testing SqlRender / Java dependencies...")
if (!requireNamespace("SqlRender", quietly = TRUE)) {
  message("  - SqlRender not installed, installing from CRAN...")
  install.packages("SqlRender")
}
library(SqlRender)

test_sqlrender <- function() {
  sql <- "SELECT * FROM @cdm_schema.person WHERE person_id = @id;"
  rendered <- SqlRender::render(sql, cdm_schema = "cdm_schema", id = 1)
  SqlRender::translate(rendered, "duckdb")
}

tryCatch(
  {
    translated <- test_sqlrender()
    message("  - SqlRender OK, translate() executed.")
  },
  error = function(e) {
    ok <<- FALSE
    message("  - SqlRender ERROR: ", conditionMessage(e))
    message("    You may need to reinstall SqlRender / Java on this machine.")
  }
)

message("\n[3] Testing CirceR minimal JSON -> SQL...")
if (!requireNamespace("CirceR", quietly = TRUE)) {
  message("  - CirceR not installed, installing from CRAN...")
  install.packages("CirceR")
}
library(CirceR)

dummy_json <- '{
  "PrimaryCriteria": { "CriteriaList": [], "ObservationWindow": { "PriorDays": 0, "PostDays": 0 }, "PrimaryCriteriaLimit": { "Type": "First" } },
  "AdditionalCriteria": null,
  "ConceptSets": [],
  "ExpressionLimit": { "Type": "First" },
  "InclusionRules": [],
  "CensoringCriteria": [],
  "CollapseSettings": { "CollapseType": "ERA", "CollapseInsidePeriod": false, "CollapseWithinDays": 0 },
  "EraCalculation": { "EraPad": 0 },
  "EndStrategy": null
}'

tryCatch(
  {
    expr <- CirceR::cohortExpressionFromJson(dummy_json)
    sql_cohort <- CirceR::buildCohortQuery(expr)
    message("  - CirceR OK, cohort SQL generated.")
  },
  error = function(e) {
    ok <<- FALSE
    message("  - CirceR ERROR: ", conditionMessage(e))
  }
)

if (ok) {
  message("\nEnvironment looks OK for SqlRender / rJava / CirceR.")
} else {
  message("\nEnvironment has errors. Fix locally, then rerun this script.")
}