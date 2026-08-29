args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) {
  stop(
    "Usage: Rscript run.R /path/to/january_2019_flights.csv\n",
    "The raw CSV is read locally and is not copied into this repository."
  )
}

project_dir <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
data_path <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
artifact_dir <- file.path(project_dir, "artifacts")

source(file.path(project_dir, "R", "flight_review.R"))
run_flight_review(data_path, artifact_dir)

if (!rmarkdown::pandoc_available()) {
  rstudio_pandoc <- if (identical(Sys.info()[["machine"]], "arm64")) {
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64"
  } else {
    "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/x86_64"
  }
  if (file.exists(file.path(rstudio_pandoc, "pandoc"))) {
    Sys.setenv(RSTUDIO_PANDOC = rstudio_pandoc)
  }
}
if (!rmarkdown::pandoc_available()) {
  stop("Pandoc was not found. Render analysis.Rmd from RStudio or install Pandoc.")
}

rmarkdown::render(
  input = file.path(project_dir, "report", "analysis.Rmd"),
  output_file = "analysis.html",
  output_dir = file.path(project_dir, "report"),
  params = list(artifact_dir = normalizePath(artifact_dir, winslash = "/")),
  envir = new.env(parent = globalenv()),
  quiet = TRUE
)

docs_dir <- file.path(project_dir, "docs")
dir.create(docs_dir, recursive = TRUE, showWarnings = FALSE)
copied <- file.copy(
  file.path(project_dir, "report", "analysis.html"),
  file.path(docs_dir, "index.html"),
  overwrite = TRUE
)
if (!isTRUE(copied)) stop("Could not copy the report into docs/.", call. = FALSE)

message("Analysis complete: ", file.path(project_dir, "report", "analysis.html"))
