test_that("the document addin formats R chunks in the active editor", {
  local_panache_project()
  skip_if_not_installed("rstudioapi")
  context <- list(
    id = "document-id",
    path = "document.qmd",
    contents = c("```{r}", "x<-1", "```")
  )
  local_mocked_bindings(active_document_context = function() context)
  replacement <- NULL
  local_mocked_bindings(
    setDocumentContents = function(text, id) {
      replacement <<- list(text = text, id = id)
    },
    .package = "rstudioapi"
  )

  result <- withVisible(format_document_addin())
  expect_false(result$visible)
  expect_null(result$value)
  expect_identical(replacement$id, context$id)
  expect_identical(replacement$text, "```{r}\nx <- 1\n```\n")
})

test_that("the selection addin formats only the selected R chunk", {
  local_panache_project()
  skip_if_not_installed("rstudioapi")
  context <- list(
    id = "document-id",
    path = "document.Rmd",
    contents = c("```{r}", "x<-1", "```", "", "```{r}", "y<-2", "```"),
    selection = list(list(
      range = list(start = list(row = 6L), end = list(row = 6L))
    ))
  )
  local_mocked_bindings(active_document_context = function() context)
  replacement <- NULL
  local_mocked_bindings(
    setDocumentContents = function(text, id) {
      replacement <<- list(text = text, id = id)
    },
    .package = "rstudioapi"
  )

  format_selection_addin()
  expect_identical(replacement$id, context$id)
  expect_identical(
    replacement$text,
    "```{r}\nx<-1\n```\n\n```{r}\ny <- 2\n```\n"
  )
})

test_that("both addins accept config paths, isolation, and named overrides", {
  project <- local_panache_project()
  config <- file.path(project, "addin.toml")
  writeLines(c("[formatters]", "r = []"), config)
  skip_if_not_installed("rstudioapi")
  context <- list(
    id = "document-id",
    path = "",
    contents = c("```r", "x<-1", "```"),
    selection = list(list(
      range = list(start = list(row = 2L), end = list(row = 2L))
    ))
  )
  local_mocked_bindings(active_document_context = function() context)
  replacement <- NULL
  local_mocked_bindings(
    setDocumentContents = function(text, id) replacement <<- text,
    .package = "rstudioapi"
  )
  withr::local_options(panache.config = config)
  for (addin in list(format_document_addin, format_selection_addin)) {
    addin()
    expect_identical(replacement, "```r\nx<-1\n```\n")
    addin(isolated = TRUE)
    expect_identical(replacement, "```r\nx <- 1\n```\n")
    addin(config = NULL, formatters = list(r = character()))
    expect_identical(replacement, "```r\nx<-1\n```\n")
  }
})
