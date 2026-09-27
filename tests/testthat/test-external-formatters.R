test_that("a Panache preset override replaces the built-in R formatter", {
  local_panache_project(c(
    '[formatters]',
    'r = "arity"',
    formatter_definition("arity", 'cat("x=2\\n")')
  ))
  input <- "```{r}\nx<-1\n```\n"
  expect_identical(
    panache_format(input, flavor = "quarto"),
    "```{r}\nx=2\n```\n"
  )
})

test_that("the arity preset runs the installed CLI", {
  skip_if(!nzchar(Sys.which("arity")), "arity CLI is not installed")
  local_panache_project(c("[formatters]", 'r = "arity"'))
  expect_identical(panache_format("```r\nx<-1\n```\n"), "```r\nx <- 1\n```\n")
})

test_that("external formatter chains support other languages and aliases", {
  local_panache_project(c(
    '[formatters]',
    'py = ["first", "second"]',
    formatter_definition(
      "first",
      'cat(sub("1", "2", readLines(file("stdin"))), "\\n", sep = "")'
    ),
    formatter_definition(
      "second",
      'cat(sub("2", "3", readLines(file("stdin"))), "\\n", sep = "")'
    )
  ))
  input <- "```python\nx=1\n```\n\n```r\nx<-1\n```\n"
  output <- panache_format(input)
  expect_match(output, "x=3\n", fixed = TRUE)
  expect_match(output, "x <- 1\n", fixed = TRUE)
})

test_that("file-based formatters receive a temporary file", {
  local_panache_project(c(
    '[formatters]',
    'r = "custom"',
    formatter_definition(
      "custom",
      c(
        'path <- commandArgs(TRUE)[[1L]]',
        'stopifnot(file.exists(path))',
        'writeLines(sub("1", "2", readLines(path)), path)'
      ),
      stdin = FALSE,
      args = "{}"
    )
  ))
  expect_identical(panache_format("```r\nx<-1\n```\n"), "```r\nx<-2\n```\n")
})

test_that("an empty R formatter chain disables the built-in default", {
  local_panache_project(c('[formatters]', 'r = []'))
  input <- "```{r}\nx<-1\n```\n"
  expect_identical(panache_format(input, flavor = "quarto"), input)
})

test_that("file formatting discovers configuration relative to the document", {
  project <- local_panache_project(c('[formatters]', 'r = []'))
  dir.create("documents")
  path <- file.path(project, "documents", "test.Rmd")
  writeLines(c("```{r}", "x<-1", "```"), path)
  withr::local_dir(tempdir())
  expect_false(panache_format_file(path))
})

test_that("explicit configuration and isolated formatting override discovery", {
  project <- local_panache_project(c('[formatters]', 'r = []'))
  explicit <- file.path(project, "explicit.toml")
  writeLines(character(), explicit)
  input <- "```r\nx<-1\n```\n"
  expected <- "```r\nx <- 1\n```\n"
  expect_identical(panache_format(input, config = explicit), expected)
  expect_identical(panache_format(input, config = FALSE), expected)
  expect_error(panache_format(input, config = "missing.toml"), "missing.toml")
  for (value in list(TRUE, NA, 1, character())) {
    expect_error(panache_format(input, config = value), "config")
  }
})

test_that("extended formatter configurations preserve an explicit R opt-out", {
  local_panache_project(c('extend = "base.toml"', '[formatters]', 'r = []'))
  writeLines(c('[formatters]', 'r = "arity"'), "base.toml")
  input <- "```r\nx<-1\n```\n"
  expect_identical(panache_format(input), input)
})

test_that("external formatting honors selections and ignore directives", {
  local_panache_project(c(
    '[formatters]',
    'r = "custom"',
    formatter_definition("custom", 'cat("x=2\\n")')
  ))
  input <- "```r\nx<-1\n```\n\n```r\nx<-1\n```\n"
  expect_identical(
    panache_format(input, range = c(6L, 6L)),
    "```r\nx<-1\n```\n\n```r\nx=2\n```\n"
  )
  ignored <- paste0(
    "<!-- panache-ignore-start -->\n\n",
    input,
    "\n<!-- panache-ignore-end -->\n"
  )
  expect_identical(panache_format(ignored), ignored)
})

test_that("a missing external command does not fall back to built-in arity", {
  local_panache_project(c(
    '[formatters]',
    'r = "missing"',
    '[formatters.missing]',
    'cmd = "panache-test-formatter-does-not-exist"'
  ))
  input <- "```r\nx<-1\n```\n"
  expect_identical(panache_format(input), input)
})

test_that("a failing formatter chain leaves the original code intact", {
  local_panache_project(c(
    "[formatters]",
    'r = ["first", "fail"]',
    formatter_definition("first", 'cat("x=2\\n")'),
    formatter_definition("fail", 'quit(status = 1L)')
  ))
  input <- "```r\nx<-1\n```\n"
  expect_identical(panache_format(input), input)
})

test_that("the document addin discovers the active document's configuration", {
  skip_if_not_installed("rstudioapi")
  project <- local_panache_project(c(
    '[formatters]',
    'r = "custom"',
    formatter_definition("custom", 'cat("x=2\\n")')
  ))
  context <- list(
    id = "document-id",
    path = file.path(project, "test.qmd"),
    contents = c("```{r}", "x<-1", "```")
  )
  local_mocked_bindings(active_document_context = function() context)
  output <- NULL
  local_mocked_bindings(
    setDocumentContents = function(text, id) output <<- text,
    .package = "rstudioapi"
  )
  withr::local_dir(tempdir())
  format_document_addin()
  expect_identical(output, "```{r}\nx=2\n```\n")
})
