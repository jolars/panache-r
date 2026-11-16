test_that("punctuation is preserved by default across Markdown flavors", {
  local_panache_project()
  input <- "\u201cHello\u201d -- wait\u2026\n"
  for (flavor in c(
    "pandoc", "quarto", "rmarkdown", "gfm", "commonmark",
    "multimarkdown", "mdsvex", "myst"
  )) {
    expect_identical(format_text(input, flavor = flavor), input)
  }
})

test_that("punctuation modes control source spelling and respect extensions", {
  local_panache_project()
  unicode <- "\u201cHello\u201d \u2013 wait\u2026\n"
  ascii <- '"Hello" -- wait...\n'
  expect_identical(
    format_text(unicode, smart_punctuation = "ascii"),
    ascii
  )
  expect_identical(
    format_text(ascii, smart_punctuation = "unicode"),
    unicode
  )
  expect_identical(
    format_text(
      unicode,
      smart_punctuation = "ascii",
      extensions = list(smart = FALSE, smart_quotes = FALSE)
    ),
    unicode
  )
})

test_that("punctuation arguments override TOML for text and files", {
  local_panache_project(c('[format]', 'smart-punctuation = "ascii"'))
  unicode <- "\u201cHello\u201d \u2013 wait\u2026\n"
  ascii <- '"Hello" -- wait...\n'
  expect_identical(format_text(unicode), ascii)
  expect_identical(
    format_text(unicode, smart_punctuation = "preserve"),
    unicode
  )
  expect_identical(format_text(unicode, isolated = TRUE), unicode)

  path <- withr::local_tempfile(fileext = ".md")
  writeBin(charToRaw(unicode), path)
  expect_false(format_file(path, smart_punctuation = "preserve"))
  expect_true(format_file(path, smart_punctuation = "ascii"))
  expect_identical(rawToChar(readBin(path, "raw", file.info(path)$size)), ascii)
  expect_true(format_file(path, smart_punctuation = "unicode"))
  expect_identical(
    enc2utf8(rawToChar(readBin(path, "raw", file.info(path)$size))),
    unicode
  )
})

test_that("invalid punctuation modes leave files unchanged", {
  local_panache_project()
  path <- withr::local_tempfile(fileext = ".md")
  writeLines("text", path)
  for (value in list("auto", NA_character_, TRUE, c("ascii", "unicode"))) {
    expect_error(format_file(path, smart_punctuation = value))
    expect_identical(readLines(path), "text")
  }
})
