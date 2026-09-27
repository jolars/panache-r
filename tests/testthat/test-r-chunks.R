test_that("R chunks and display blocks are formatted with arity", {
  local_panache_project()
  for (flavor in c("quarto", "rmarkdown", "pandoc", "gfm")) {
    fence <- if (flavor %in% c("quarto", "rmarkdown")) "```{r}" else "```r"
    input <- paste0(fence, "\nx<-c(1,2)\n```\n")
    output <- panache_format(input, flavor = flavor)

    expect_match(output, "x <- c(1, 2)\n", fixed = TRUE)
    expect_identical(panache_format(output, flavor = flavor), output)
  }
})

test_that("chunk options are preserved alongside formatted R code", {
  local_panache_project()
  input <- "```{r setup, echo=FALSE}\n#| fig-cap: A caption\nx<-1\n```\n"
  for (flavor in c("quarto", "rmarkdown")) {
    output <- panache_format(input, flavor = flavor)
    expect_match(output, "setup", fixed = TRUE)
    expect_match(output, "echo", fixed = TRUE)
    expect_match(output, "#| fig-cap: A caption", fixed = TRUE)
    expect_match(output, "x <- 1\n", fixed = TRUE)
    expect_identical(panache_format(output, flavor = flavor), output)
  }
})

test_that("R fence variants and empty chunks are supported", {
  local_panache_project()
  for (fence in c("~~~r", "````{r}", "```{.r}", "```R")) {
    closing <- sub("[rR{].*$", "", fence)
    input <- paste0(fence, "\nx<-1\n", closing, "\n")
    expect_match(
      panache_format(input, flavor = "quarto"),
      "x <- 1\n",
      fixed = TRUE
    )
  }
  for (input in c("```{r}\n```\n", "```{r}\n#| echo: false\n```\n")) {
    expect_no_warning(output <- panache_format(input, flavor = "quarto"))
    expect_identical(output, input)
  }
})

test_that("nested R chunks retain their container prefixes", {
  local_panache_project()
  inputs <- c(
    "> ```{r}\n> x<-1\n> ```\n",
    "- Item\n\n  ```{r}\n  x<-1\n  ```\n"
  )
  for (input in inputs) {
    output <- panache_format(input, flavor = "quarto")
    expect_match(output, "x <- 1", fixed = TRUE)
    expect_identical(panache_format(output, flavor = "quarto"), output)
  }
  expect_match(panache_format(inputs[[1]], flavor = "quarto"), "> x <- 1")
})

test_that("other languages and inline code are preserved", {
  local_panache_project()
  input <- "```python\nx=1\n```\n\n`r x+1`\n"
  expect_no_warning(output <- panache_format(input, flavor = "quarto"))
  expect_match(output, "x=1", fixed = TRUE)
  expect_match(output, "`r x+1`", fixed = TRUE)
})

test_that("unclosed GFM code blocks are not passed to arity", {
  local_panache_project()
  input <- "```r\nx<-\n"
  expect_no_warning(output <- panache_format(input, flavor = "gfm"))
  expect_identical(output, input)
})

test_that("only R chunks in the selected block range are formatted", {
  local_panache_project()
  input <- "```{r}\nx<-1\n```\n\n```{r}\nx<-1\n```\n\n```{r}\nx<-\n```\n"
  expect_no_warning(
    output <- panache_format(input, flavor = "quarto", range = c(6L, 6L))
  )
  expect_identical(
    output,
    "```{r}\nx<-1\n```\n\n```{r}\nx <- 1\n```\n\n```{r}\nx<-\n```\n"
  )
})

test_that("ignored R chunks are not passed to arity", {
  local_panache_project()
  input <- paste0(
    "<!-- panache-ignore-format-start -->\n\n",
    "```{r}\nx<-\n```\n\n",
    "<!-- panache-ignore-format-end -->\n\n",
    "```{r}\nx<-1\n```\n"
  )
  expect_no_warning(output <- panache_format(input, flavor = "quarto"))
  expect_match(output, "x<-\n", fixed = TRUE)
  expect_match(output, "x <- 1\n", fixed = TRUE)
})

test_that("invalid R code warns and is preserved while other chunks format", {
  local_panache_project()
  input <- "```{r}\nx<-\n```\n\n```{r}\ny<-2\n```\n"
  expect_warning(
    output <- panache_format(input, flavor = "quarto"),
    "Could not format R code chunk"
  )
  expect_match(output, "x<-\n", fixed = TRUE)
  expect_match(output, "y <- 2\n", fixed = TRUE)
})

test_that("R chunks use the requested line width within arity's limits", {
  local_panache_project()
  code <- "result<-some_function(first_argument,second_argument,third_argument)\n"
  input <- paste0("```{r}\n", code, "```\n")
  output <- panache_format(input, flavor = "quarto", line_width = 30L)
  expect_match(output, arity::format_text(code, line_width = 30L), fixed = TRUE)
  expect_no_warning(panache_format(input, line_width = 2000L))
})

test_that("R chunk formatting preserves Unicode and CRLF line endings", {
  local_panache_project()
  input <- "A caf\u00e9.\r\n\r\n```{r}\r\nx<-\"caf\u00e9\"\r\n```\r\n"
  output <- panache_format(input, flavor = "quarto")
  expect_identical(
    output,
    "A caf\u00e9.\r\n\r\n```{r}\r\nx <- \"caf\u00e9\"\r\n```\r\n"
  )
  expect_identical(panache_format(output, flavor = "quarto"), output)
})

test_that("file formatting supports R chunks", {
  local_panache_project()
  path <- tempfile(fileext = ".Rmd")
  on.exit(unlink(path))
  input <- "```{r}\nx<-1\n```\n"
  writeBin(charToRaw(input), path)

  expect_true(panache_format_file(path))
  expect_identical(readLines(path), c("```{r}", "x <- 1", "```"))
  expect_false(panache_format_file(path))
})

test_that("treating formatting warnings as errors leaves files intact", {
  local_panache_project()
  path <- tempfile(fileext = ".qmd")
  on.exit(unlink(path))
  input <- "```{r}\nx<-\n```\n"
  writeBin(charToRaw(input), path)
  old_options <- options(warn = 2L)
  on.exit(options(old_options), add = TRUE)

  expect_error(panache_format_file(path), "Could not format R code chunk")
  expect_identical(
    rawToChar(readBin(path, "raw", n = file.info(path)$size)),
    input
  )
})
