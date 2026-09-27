test_that("list configuration controls document formatting", {
  local_panache_project()
  input <- "one two three four five six seven eight nine ten\n"
  config <- list(format = list(line_width = 20, wrap = "reflow"))
  expect_identical(
    panache_format(input, config = config),
    panache_format(input, line_width = 20L, config = FALSE)
  )
  expect_identical(
    panache_format(input, config = config, line_width = 80L, wrap = "preserve"),
    input
  )
})

test_that("list and TOML configurations have the same effect", {
  local_panache_project(c(
    '[format]',
    'line-width = 20',
    'wrap = "sentence"',
    'line-ending = "crlf"',
    '[formatters]',
    'r = []'
  ))
  config <- list(
    format = list(line_width = 20, wrap = "sentence", line_ending = "crlf"),
    formatters = list(r = character())
  )
  input <- "First sentence. Second sentence.\n\n```r\nx<-1\n```\n"
  from_file <- panache_format(input, config = "panache.toml")
  expect_identical(panache_format(input, config = config), from_file)
  expect_match(
    from_file,
    "First sentence.\r\nSecond sentence.\r\n",
    fixed = TRUE
  )
  expect_match(from_file, "x<-1\r\n", fixed = TRUE)
})

test_that("an empty list uses defaults without discovering configuration", {
  local_panache_project(c('[formatters]', 'r = []'))
  input <- "```r\nx<-1\n```\n"
  expect_identical(
    panache_format(input, config = list()),
    "```r\nx <- 1\n```\n"
  )
})

test_that("list configuration supports presets and custom formatter chains", {
  local_panache_project()
  first <- withr::local_tempfile(fileext = ".R")
  second <- withr::local_tempfile(fileext = ".R")
  writeLines('cat("x=2\\n")', first)
  writeLines(
    'cat(sub("2", "3", readLines(file("stdin"))), "\\n", sep = "")',
    second
  )
  command <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  config <- list(
    formatters = list(
      r = c("arity", "my_formatter"),
      arity = list(cmd = command, args = c("--vanilla", first)),
      my_formatter = list(cmd = command, args = second, stdin = TRUE)
    )
  )
  expect_identical(
    panache_format("```r\nx<-1\n```\n", config = config),
    "```r\nx=3\n```\n"
  )
})

test_that("the arity CLI can be selected from an R list", {
  skip_if(!nzchar(Sys.which("arity")), "arity CLI is not installed")
  local_panache_project()
  expect_identical(
    panache_format(
      "```r\nx<-1\n```\n",
      config = list(formatters = list(r = "arity"))
    ),
    "```r\nx <- 1\n```\n"
  )
})

test_that("built-in arity uses the configured document width", {
  local_panache_project()
  code <- "result<-some_function(first_argument,second_argument,third_argument)\n"
  input <- paste0("```r\n", code, "```\n")
  output <- panache_format(input, config = list(format = list(line_width = 30)))
  expect_match(output, arity::format_text(code, line_width = 30), fixed = TRUE)
})

test_that("file formatting preserves option precedence", {
  local_panache_project(c('[format]', 'line-width = 20'))
  path <- withr::local_tempfile(fileext = ".qmd")
  input <- "one two three four five six seven eight nine ten\n"
  writeBin(charToRaw(input), path)
  config <- list(format = list(line_width = 20))
  expect_false(panache_format_file(path, line_width = 80, config = config))
  expect_true(panache_format_file(path, config = config))
  expect_identical(
    paste0(paste(readLines(path), collapse = "\n"), "\n"),
    panache_format(input, config = config)
  )
})

test_that("malformed configuration lists fail before changing a file", {
  local_panache_project()
  path <- withr::local_tempfile(fileext = ".md")
  writeLines("text", path)
  invalid <- list(
    list(20),
    list(format = list(line_width = NA)),
    list(format = list(line_width = 0)),
    list(format = list(line_width = 1.5)),
    list(format = list(line_width = Inf)),
    list(format = list(typo = TRUE)),
    list(format = list(line_width = NULL)),
    list(typo = TRUE),
    list(format = list(line_width = matrix(20))),
    list(formatters = list(r = TRUE)),
    list(format = list(line_width = 20, `line-width` = 30))
  )
  for (config in invalid) {
    expect_error(
      panache_format_file(path, config = config),
      "config|line.width"
    )
    expect_identical(readLines(path), "text")
  }
})

test_that("list configuration accepts Panache and R option spellings", {
  local_panache_project()
  input <- "one two three four five six seven eight nine ten\n"
  config <- list(format = list(`line-width` = 20, wrap = "preserve"))
  expect_identical(panache_format(input, config = config), input)
  expect_identical(
    panache_format(input, config = list(line_width = 20, wrap = "preserve")),
    input
  )
})

test_that("flat format options do not partially match the formatters section", {
  config <- list(line_width = 20, formatters = list(r = character()))
  expect_identical(
    normalize_config(config),
    list(formatters = list(r = character()), format = list(`line-width` = 20))
  )
  input <- "```r\nx<-1\n```\n"
  expect_identical(panache_format(input, config = config), input)
})

test_that(
  "list configuration preserves single-element arrays and math signatures",
  {
    local_panache_project(c(
      '[flavors]',
      'gfm = ["*.custom"]',
      '[format]',
      'wrap = "sentence"',
      'no-break-abbreviations = ["abbr."]',
      '[format.math-signatures]',
      'custom = [{ kind = "brace", domain = "text" }]'
    ))
    config <- list(
      flavors = list(gfm = "*.custom"),
      format = list(
        wrap = "sentence",
        no_break_abbreviations = "abbr.",
        math_signatures = list(
          custom = list(list(kind = "brace", domain = "text"))
        )
      )
    )
    input <- "Use abbr. here. Next sentence.\n\n$\\custom{some text}$\n"
    expect_identical(
      panache_format(input, config = config, path = "document.custom"),
      panache_format(input, config = "panache.toml", path = "document.custom")
    )
    config$format$no_break_abbreviations <- list(default = "abbr.")
    expect_identical(
      panache_format(input, config = config),
      panache_format(input, config = "panache.toml")
    )
  }
)

test_that("configured flavors can be overridden explicitly", {
  local_panache_project()
  input <- "::: note\nSome text.\n:::\n"
  config <- list(flavor = "commonmark")
  expect_identical(
    panache_format(input, config = config, path = "document.qmd"),
    panache_format(input, config = FALSE, flavor = "commonmark")
  )
  expect_identical(
    panache_format(input, config = config, flavor = "quarto"),
    panache_format(input, config = FALSE, flavor = "quarto")
  )
})
