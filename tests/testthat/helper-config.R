local_panache_project <- function(
  config = character(),
  .local_envir = parent.frame()
) {
  path <- withr::local_tempdir(.local_envir = .local_envir)
  dir.create(file.path(path, ".git"))
  writeLines(config, file.path(path, "panache.toml"))
  withr::local_dir(path, .local_envir = .local_envir)
  path
}

formatter_definition <- function(
  name,
  script,
  stdin = TRUE,
  args = character()
) {
  path <- tempfile(fileext = ".R")
  writeLines(script, path)
  command <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  quote_toml <- function(x) encodeString(x, quote = '"')
  c(
    paste0("[formatters.", name, "]"),
    paste0("cmd = ", quote_toml(command)),
    paste0(
      "args = [",
      paste(quote_toml(c("--vanilla", path, args)), collapse = ", "),
      "]"
    ),
    paste0("stdin = ", tolower(as.character(stdin)))
  )
}
