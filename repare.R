remove.packages("CirceR")

install.packages("remotes")
remotes::install_github("ohdsi/CirceR")

# ou, autre option recommandée par OHDSI :
install.packages("CirceR",
                 repos = c("https://ohdsi.r-universe.dev",
                           "https://cloud.r-project.org"))