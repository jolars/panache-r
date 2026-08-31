test_that("documents are formatted", {
  input <- "# Heading\n\n-   one\n-   two\n"
  output <- panache_format(input, flavor = "quarto")

  expect_type(output, "character")
  expect_length(output, 1L)
  expect_identical(panache_format(output, flavor = "quarto"), output)
})

test_that("text must be valid UTF-8", {
  invalid <- rawToChar(as.raw(c(0xff, 0xfe)))
  expect_error(panache_format(invalid), "valid UTF-8")

  latin1 <- iconv("caf\u00e9\n", from = "UTF-8", to = "latin1")
  output <- panache_format(latin1)
  expect_true(validUTF8(output))
  expect_identical(Encoding(output), "UTF-8")
})

test_that("numeric options require positive whole numbers", {
  expect_error(panache_format("text\n", line_width = 0), "line_width")
  expect_error(panache_format("text\n", line_width = 1.5), "line_width")
  expect_error(panache_format("text\n", line_width = Inf), "line_width")
})

test_that("invalid ranges are rejected", {
  expect_error(panache_format("text\n", range = c(3, 2)), "increasing")
  expect_error(panache_format("text\n", range = c(1.5, 2)), "range")
  expect_error(panache_format("text\n", range = c("1", "2")), "range")
  expect_error(panache_format("text\n", range = c(1, Inf)), "range")
  expect_error(panache_format("text\n", range = c(1, 3)), "outside")
})

test_that("range formatting preserves unselected blocks", {
  first <- paste(rep("first", 20), collapse = " ")
  second <- paste(rep("second", 20), collapse = " ")
  input <- paste("# Heading", first, second, sep = "\n\n")
  output <- panache_format(
    input,
    flavor = "quarto",
    line_width = 40L,
    range = c(5L, 5L)
  )

  expect_true(grepl(first, output, fixed = TRUE))
  expect_false(grepl(second, output, fixed = TRUE))
})

test_that("the engine version is reported", {
  expect_identical(panache_engine_version(), "0.22.0")
})

test_that("files are written only when formatting changes them", {
  path <- tempfile(fileext = ".qmd")
  on.exit(unlink(path))
  writeChar("# Heading\n", path, eos = NULL, useBytes = TRUE)

  stamp <- file.info(path)$mtime
  result <- withVisible(panache_format_file(path))

  expect_false(result$visible)
  expect_false(result$value)
  expect_identical(file.info(path)$mtime, stamp)
})

test_that("file errors are reported without modifying input", {
  missing <- tempfile(fileext = ".md")
  expect_error(panache_format_file(missing), "does not exist")

  path <- tempfile(fileext = ".md")
  on.exit(unlink(path), add = TRUE)
  bytes <- as.raw(c(0xff, 0xfe))
  writeBin(bytes, path)

  expect_error(panache_format_file(path), "valid UTF-8")
  expect_identical(readBin(path, "raw", n = 2), bytes)
})
