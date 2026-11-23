test_that("format_file changes only Markdown cell sources in Jupyter notebooks", {
  path <- tempfile(fileext = ".IPYNB")
  on.exit(unlink(path))
  notebook <- paste0(
    '{"nbformat":4,"nbformat_minor":5,"metadata":{"name":"example"},"cells":[\n',
    '{"cell_type":"markdown","source":["#   Heading\\n"],"metadata":{}},\n',
    '{"cell_type":"markdown","source":"##   Second\\n","metadata":{}},\n',
    '{"cell_type":"code","source":["x=1"],"outputs":[],"execution_count":1}\n',
    ']}\n'
  )
  expected <- sub("#   Heading", "# Heading", notebook, fixed = TRUE)
  expected <- sub("##   Second", "## Second", expected, fixed = TRUE)
  writeBin(charToRaw(notebook), path)

  expect_true(format_file(path, isolated = TRUE))
  expect_identical(readBin(path, "raw", n = file.info(path)$size), charToRaw(expected))
  expect_false(format_file(path, isolated = TRUE))

  expect_error(
    format_file(path, range = c(1, 2), isolated = TRUE),
    "line ranges are not supported for Jupyter notebooks"
  )
  expect_identical(readBin(path, "raw", n = file.info(path)$size), charToRaw(expected))
})

test_that("format_file preserves invalid notebooks", {
  path <- tempfile(fileext = ".ipynb")
  on.exit(unlink(path))
  invalid <- charToRaw('{"nbformat":4')
  writeBin(invalid, path)

  expect_error(format_file(path, isolated = TRUE), "invalid notebook")
  expect_identical(readBin(path, "raw", n = file.info(path)$size), invalid)
})

test_that("format_text accepts Jupyter Markdown and notebook JSON", {
  expect_identical(
    format_text("#   Heading\n", flavor = "jupyter", isolated = TRUE),
    "# Heading\n"
  )

  notebook <- paste0(
    '{"nbformat":4,"nbformat_minor":5,"cells":[',
    '{"cell_type":"markdown","source":"#   Heading\\n"}]}'
  )
  expect_identical(
    format_text(notebook, path = "example.ipynb", isolated = TRUE),
    sub("#   Heading", "# Heading", notebook, fixed = TRUE)
  )
})
