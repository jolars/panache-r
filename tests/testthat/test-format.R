test_that("documents are formatted", {
  input <- "# Heading\n\n-   one\n-   two\n"
  output <- panache_format(input, flavor = "quarto")

  expect_type(output, "character")
  expect_length(output, 1L)
  expect_identical(panache_format(output, flavor = "quarto"), output)
})

test_that("invalid ranges are rejected", {
  expect_error(panache_format("text\n", range = c(3, 2)), "increasing")
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
