test_that("named formatting options override discovered settings", {
  input <- "one two three four five six seven eight nine ten\n"
  local_panache_project(c("[format]", "line-width = 20"))
  expect_identical(
    format_text(input),
    format_text(input, line_width = 20L, isolated = TRUE)
  )
  expect_identical(
    format_text(input, line_width = 80L, wrap = "preserve"),
    input
  )
})

test_that("existing wrapping abbreviations remain supported", {
  expect_identical(
    format_text(
      "First sentence. Second sentence.\n",
      wrap = "sent",
      isolated = TRUE
    ),
    "First sentence.\nSecond sentence.\n"
  )
})

test_that("named options and TOML configurations have the same effect", {
  local_panache_project(c(
    '[format]',
    'line-width = 20',
    'wrap = "sentence"',
    'line-ending = "crlf"',
    '[formatters]',
    'r = []'
  ))
  config <- list(
    line_width = 20,
    wrap = "sentence",
    line_ending = "crlf",
    formatters = list(r = character())
  )
  input <- "First sentence. Second sentence.\n\n```r\nx<-1\n```\n"
  from_file <- format_text(input, config = "panache.toml")
  expect_identical(
    do.call(format_text, c(list(text = input, isolated = TRUE), config)),
    from_file
  )
  expect_match(
    from_file,
    "First sentence.\r\nSecond sentence.\r\n",
    fixed = TRUE
  )
  expect_match(from_file, "x<-1\r\n", fixed = TRUE)
})

test_that("empty grouped overrides preserve discovered configuration", {
  local_panache_project(c('[formatters]', 'r = []'))
  input <- "```r\nx<-1\n```\n"
  expect_identical(
    format_text(input, formatters = list(), extensions = list()),
    input
  )
})

test_that("formatter arguments support presets and custom chains", {
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
    format_text("```r\nx<-1\n```\n", formatters = config$formatters),
    "```r\nx=3\n```\n"
  )
})

test_that("the arity CLI can be selected from an R list", {
  skip_if(!nzchar(Sys.which("arity")), "arity CLI is not installed")
  local_panache_project()
  expect_identical(
    format_text("```r\nx<-1\n```\n", formatters = list(r = "arity")),
    "```r\nx <- 1\n```\n"
  )
})

test_that("built-in arity uses the configured document width", {
  local_panache_project()
  code <- "result<-some_function(first_argument,second_argument,third_argument)\n"
  input <- paste0("```r\n", code, "```\n")
  output <- format_text(input, line_width = 30)
  expect_match(output, arity::format_text(code, line_width = 30), fixed = TRUE)
})

test_that("file formatting preserves option precedence", {
  local_panache_project(c('[format]', 'line-width = 20'))
  path <- withr::local_tempfile(fileext = ".qmd")
  input <- "one two three four five six seven eight nine ten\n"
  writeBin(charToRaw(input), path)
  expect_false(format_file(
    path,
    config = "panache.toml",
    line_width = 80
  ))
  expect_true(format_file(path, config = "panache.toml"))
  expect_identical(
    paste0(paste(readLines(path), collapse = "\n"), "\n"),
    format_text(input)
  )
})

test_that("named options preserve single-element arrays and math signatures", {
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
    wrap = "sentence",
    no_break_abbreviations = "abbr.",
    math_signatures = list(custom = list(list(kind = "brace", domain = "text")))
  )
  input <- "Use abbr. here. Next sentence.\n\n$\\custom{some text}$\n"
  expect_identical(
    do.call(
      format_text,
      c(list(text = input, isolated = TRUE, path = "document.custom"), config)
    ),
    format_text(input, config = "panache.toml", path = "document.custom")
  )
  config$no_break_abbreviations <- list(default = "abbr.")
  expect_identical(
    do.call(format_text, c(list(text = input, isolated = TRUE), config)),
    format_text(input, config = "panache.toml")
  )
})

test_that("explicit flavor overrides configuration and the document path", {
  local_panache_project('flavor = "commonmark"')
  input <- "::: note\nSome text.\n:::\n"
  expect_identical(
    format_text(input, flavor = "commonmark", path = "document.qmd"),
    format_text(input, isolated = TRUE, flavor = "commonmark")
  )
  expect_identical(
    format_text(input, flavor = "quarto"),
    format_text(input, isolated = TRUE, flavor = "quarto")
  )
})

test_that("overrides preserve extended settings and formatter definitions", {
  local_panache_project(c(
    'extend = "base.toml"',
    '[format]',
    'line-width = 20'
  ))
  writeLines(
    c(
      '[format]',
      'wrap = "sentence"',
      'line-ending = "crlf"',
      '[formatters]',
      'r = []',
      formatter_definition("custom", 'cat("x=2\\n")')
    ),
    "base.toml"
  )
  input <- "First sentence. Second sentence.\n\n```r\nx<-1\n```\n"
  output <- format_text(input, line_width = 100)
  expect_match(output, "First sentence.\r\nSecond sentence.\r\n", fixed = TRUE)
  expect_match(output, "x<-1\r\n", fixed = TRUE)
  output <- format_text(input, formatters = list(r = "custom"))
  expect_match(output, "x=2\r\n", fixed = TRUE)
})

test_that(
  "formatter overrides preserve unrelated mappings and replace chains",
  {
    local_panache_project(c(
      '[formatters]',
      'r = ["first", "second"]',
      'python = "first"',
      formatter_definition("first", 'cat("x=2\\n")'),
      formatter_definition("second", 'cat("x=3\\n")')
    ))
    input <- "```r\nx<-1\n```\n\n```python\nx=1\n```\n"
    expect_identical(
      format_text(input, formatters = list(r = character())),
      "```r\nx<-1\n```\n\n```python\nx=2\n```\n"
    )
    expect_match(
      format_text(input, formatters = list(r = "first")),
      "```r\nx=2\n```",
      fixed = TRUE
    )
  }
)

test_that(
  "extension overrides retain flavor defaults and override file settings",
  {
    local_panache_project(c('[extensions.quarto]', 'smart = true'))
    input <- '"Hello" -- world.\n'
    expected <- format_text(
      input,
      flavor = "quarto",
      isolated = TRUE,
      extensions = list(smart = FALSE)
    )
    expect_identical(expected, input)
    expect_identical(
      format_text(
        input,
        path = "document.qmd",
        extensions = list(smart = FALSE)
      ),
      expected
    )
    expect_identical(
      format_text(
        input,
        path = "document.qmd",
        extensions = list(quarto = list(smart = FALSE))
      ),
      expected
    )
  }
)

test_that(
  "isolation skips files while retaining explicit overrides and path detection",
  {
    local_panache_project(c('[formatters]', 'r = []'))
    input <- "```{r}\nx<-1\n```\n"
    expect_identical(
      format_text(
        input,
        isolated = TRUE,
        config = "missing.toml",
        path = "document.qmd"
      ),
      "```{r}\nx <- 1\n```\n"
    )
    expect_identical(
      format_text(
        input,
        isolated = TRUE,
        path = "document.qmd",
        formatters = list(r = character())
      ),
      input
    )
  }
)

test_that("invalid arguments fail before changing a file", {
  local_panache_project()
  path <- withr::local_tempfile(fileext = ".md")
  writeLines("text", path)
  invalid <- list(
    list(config = list()),
    list(config = FALSE),
    list(config = ""),
    list(isolated = NA),
    list(isolated = 1),
    list(line_width = NA),
    list(line_width = 1.5),
    list(line_ending = "windows"),
    list(table_indent = 4),
    list(math_indent = -1),
    list(tab_width = 0),
    list(formatters = "air"),
    list(formatters = list(r = TRUE)),
    list(formatters = list(custom = list(typo = TRUE))),
    list(extensions = list(typo = TRUE)),
    list(extensions = list(smart = "false")),
    list(extensions = list(quarto = list(typo = TRUE))),
    list(extensions = list(smart_quotes = TRUE, `smart-quotes` = FALSE)),
    list(compat = list(typo = TRUE)),
    list(flavors = list(unknown = "*.md")),
    list(math_signatures = list(custom = list(list(kind = "invalid"))))
  )
  for (args in invalid) {
    expect_error(do.call(format_file, c(list(path = path), args)))
    expect_identical(readLines(path), "text")
  }
})

test_that(
  "flavor overrides preserve project patterns and resolve relative to the config",
  {
    project <- local_panache_project(c(
      '[flavors]',
      'gfm = ["docs/*.md", "README.md"]'
    ))
    dir.create("docs")
    dir.create("other")
    input <- "::: note\nSome text.\n:::\n"
    overrides <- list(commonmark = "README.md", quarto = "other/*.md")
    expect_identical(
      format_text(
        input,
        path = file.path(project, "docs/test.md"),
        config = "panache.toml",
        flavors = overrides
      ),
      format_text(input, flavor = "gfm", isolated = TRUE)
    )
    withr::local_dir(tempdir())
    for (entry in list(
      c("docs/test.md", "gfm"),
      c("README.md", "commonmark"),
      c("other/test.md", "quarto")
    )) {
      expect_identical(
        format_text(
          input,
          path = file.path(project, entry[[1L]]),
          flavors = overrides
        ),
        format_text(input, flavor = entry[[2L]], isolated = TRUE)
      )
    }
  }
)

test_that("flavor patterns resolve symlinked projects for unsaved documents", {
  root <- withr::local_tempdir()
  project <- file.path(root, "project")
  alias <- file.path(root, "alias")
  dir.create(project)
  dir.create(file.path(project, ".git"))
  dir.create(file.path(project, "docs"))
  skip_if_not(
    suppressWarnings(file.symlink(project, alias)),
    "Directory symlinks are unavailable"
  )
  writeLines(
    c("[flavors]", 'gfm = ["docs/*.md", "drafts/**/*.md"]'),
    file.path(project, "panache.toml")
  )
  input <- "::: note\nSome text.\n:::\n"
  writeLines(input, file.path(project, "docs/existing.md"))
  withr::local_dir(alias)
  expected <- format_text(input, flavor = "gfm", isolated = TRUE)
  for (document in c("docs/existing.md", "docs/new.md", "drafts/nested/new.md")) {
    for (config in list("panache.toml", file.path(project, "panache.toml"), NULL)) {
      expect_identical(
        format_text(
          input,
          path = file.path(alias, document),
          config = config,
          flavors = list(commonmark = "README.md")
        ),
        expected
      )
    }
  }
  path <- file.path(alias, "docs/new.md")
  expect_identical(
    format_text(
      input,
      path = path,
      config = "panache.toml",
      flavors = list(commonmark = gsub("\\", "/", path, fixed = TRUE))
    ),
    format_text(input, flavor = "commonmark", isolated = TRUE)
  )
  expect_identical(
    format_text(
      input,
      path = file.path(project, "docs/new.md"),
      config = file.path(alias, "panache.toml"),
      flavors = list(commonmark = "README.md")
    ),
    expected
  )
})

test_that("adding flavor patterns preserves absolute inherited patterns", {
  project <- local_panache_project()
  path <- file.path(project, "document.md")
  pattern <- gsub("\\", "/", path, fixed = TRUE)
  writeLines(
    c(
      "[flavors]",
      paste0("commonmark = [", encodeString(pattern, quote = '"'), "]")
    ),
    "panache.toml"
  )
  input <- "::: note\nSome text.\n:::\n"
  expect_identical(
    format_text(input, path = path, flavors = list(gfm = "other.md")),
    format_text(input, isolated = TRUE, flavor = "commonmark")
  )
})

test_that("formatting arguments match their TOML settings", {
  local_panache_project(c(
    '[format]',
    'line-width = 30',
    'line-ending = "crlf"',
    'wrap = "sentence"',
    'math-indent = 0',
    'math = "verbatim"',
    'math-delimiter-style = "dollars"',
    'table-indent = 0',
    'tab-stops = "preserve"',
    'tab-width = 8',
    'horizontal-rule-style = "compact"',
    'lang = "en"',
    'no-break-abbreviations = ["abbr."]',
    '[compat]',
    'pandoc = "3.7"'
  ))
  input <- paste0(
    "First sentence. Use abbr. here.\n\n---\n\n",
    "\\[ x+y \\]\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
  )
  expected <- format_text(input)
  args <- list(
    line_width = 30,
    line_ending = "crlf",
    wrap = "sentence",
    math_indent = 0,
    math = "verbatim",
    math_delimiter_style = "dollars",
    table_indent = 0,
    tab_stops = "preserve",
    tab_width = 8,
    horizontal_rule_style = "compact",
    lang = "en",
    no_break_abbreviations = "abbr.",
    compat = list(pandoc = "3.7")
  )
  expect_identical(
    do.call(format_text, c(list(text = input, isolated = TRUE), args)),
    expected
  )
  path <- withr::local_tempfile(fileext = ".md")
  writeBin(charToRaw(input), path)
  expect_true(do.call(
    format_file,
    c(list(path = path, isolated = TRUE), args)
  ))
  expect_identical(
    rawToChar(readBin(path, "raw", file.info(path)$size)),
    expected
  )
})
