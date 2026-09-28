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

external_formatter_peak <- function(limit) {
  records <- withr::local_tempdir()
  local_panache_project(c(
    paste0("external-max-parallel = ", limit),
    "[formatters]",
    'python = "worker"',
    formatter_definition(
      "worker",
      c(
        'input <- readLines(file("stdin"))',
        'start <- as.numeric(Sys.time())',
        'Sys.sleep(0.5)',
        'end <- as.numeric(Sys.time())',
        'path <- file.path(commandArgs(TRUE)[[1L]], paste0(Sys.getpid(), ".rds"))',
        'saveRDS(c(start, end), path)',
        'cat(input, "\\n", sep = "")'
      ),
      args = records
    )
  ))
  input <- paste0("```python\nx=", 1:4, "\n```\n", collapse = "\n")
  expect_identical(format_text(input), input)
  intervals <- lapply(list.files(records, full.names = TRUE), readRDS)
  expect_length(intervals, 4L)
  events <- do.call(rbind, lapply(intervals, function(interval) {
    data.frame(time = interval, change = c(1L, -1L))
  }))
  max(cumsum(events$change[order(events$time)]))
}
