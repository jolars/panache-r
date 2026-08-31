#' Format a document with Panache
#'
#' `panache_format()` formats a complete document held in a character scalar.
#' Use `range` to restrict formatting to a one-indexed, inclusive line range;
#' Panache formats blocks overlapping that range.
#'
#' @param text A character scalar containing a valid UTF-8 document. Strings
#'   with a declared encoding are converted to UTF-8.
#' @param flavor The Markdown flavor. One of `"pandoc"`, `"quarto"`,
#'   `"rmarkdown"`, `"gfm"`, `"commonmark"`, `"multimarkdown"`, `"mdsvex"`, or
#'   `"myst"`.
#' @param line_width A positive integer giving the target line width.
#' @param wrap The wrapping strategy. One of `"reflow"`, `"sentence"`,
#'   `"semantic"`, or `"preserve"`.
#' @param range `NULL`, or an integer vector containing the first and last lines
#'   to format.
#'
#' @return A character scalar containing the formatted document.
#' @export
#'
#' @examples
#' panache_format("# Heading\n\nSome text.\n", flavor = "quarto")
panache_format <- function(
  text,
  flavor = "pandoc",
  line_width = 80L,
  wrap = "reflow",
  range = NULL
) {
  text <- utf8_character(text, "text")
  flavor <- match.arg(
    flavor,
    c(
      "pandoc",
      "quarto",
      "rmarkdown",
      "gfm",
      "commonmark",
      "multimarkdown",
      "mdsvex",
      "myst"
    )
  )
  wrap <- match.arg(wrap, c("reflow", "sentence", "semantic", "preserve"))

  line_width <- positive_integer(line_width, "line_width")

  if (is.null(range)) {
    start_line <- NULL
    end_line <- NULL
  } else {
    valid_range <- is.numeric(range) &&
      length(range) == 2L &&
      !anyNA(range) &&
      all(is.finite(range)) &&
      all(range == trunc(range)) &&
      all(range >= 1) &&
      all(range <= .Machine$integer.max) &&
      range[[1L]] <= range[[2L]]
    if (!valid_range) {
      stop(
        "`range` must contain two positive, increasing line numbers.",
        call. = FALSE
      )
    }
    start_line <- as.integer(range[[1L]])
    end_line <- as.integer(range[[2L]])
  }

  unwrap_extendr_result(
    rust_format_document(text, flavor, line_width, wrap, start_line, end_line)
  )
}

#' Format a file with Panache
#'
#' The file is replaced only when formatting changes its contents.
#'
#' @param path Path to a UTF-8 Markdown, Quarto, or R Markdown document.
#' @inheritParams panache_format
#' @param flavor The Markdown flavor, or `NULL` to infer it from `path`.
#'
#' @return Invisibly, `TRUE` if the file changed and `FALSE` otherwise.
#' @export
panache_format_file <- function(
  path,
  flavor = NULL,
  line_width = 80L,
  wrap = "reflow",
  range = NULL
) {
  path <- scalar_character(path, "path")
  if (!file.exists(path)) {
    stop("File does not exist: ", path, call. = FALSE)
  }
  if (is.null(flavor)) {
    flavor <- flavor_from_path(path)
  }

  input <- rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
  input <- utf8_character(input, "file contents")
  output <- panache_format(input, flavor, line_width, wrap, range)
  changed <- !identical(input, output)

  if (changed) {
    writeBin(charToRaw(output), path)
  }

  invisible(changed)
}

#' Report the embedded Panache formatter version
#'
#' @return A character scalar containing the `panache-formatter` crate version.
#' @export
panache_engine_version <- function() rust_engine_version()

scalar_character <- function(x, arg) {
  if (length(x) != 1L || is.na(x) || !is.character(x)) {
    stop("`", arg, "` must be one non-missing character string.", call. = FALSE)
  }
  x
}

utf8_character <- function(x, arg) {
  x <- scalar_character(x, arg)
  if (identical(Encoding(x), "bytes")) {
    stop("`", arg, "` must contain valid UTF-8.", call. = FALSE)
  }

  x <- enc2utf8(x)
  if (!validUTF8(x)) {
    stop("`", arg, "` must contain valid UTF-8.", call. = FALSE)
  }
  x
}

positive_integer <- function(x, arg) {
  valid <- is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    is.finite(x) &&
    x == trunc(x) &&
    x >= 1 &&
    x <= .Machine$integer.max
  if (!valid) {
    stop("`", arg, "` must be one positive integer.", call. = FALSE)
  }
  as.integer(x)
}

unwrap_extendr_result <- function(value) {
  if (inherits(value, "extendr_error")) {
    stop(as.character(value$value)[[1L]], call. = FALSE)
  }
  value
}

flavor_from_path <- function(path) {
  extension <- tools::file_ext(path)
  switch(
    extension,
    qmd = "quarto",
    Rmd = ,
    rmd = ,
    Rmarkdown = ,
    rmarkdown = "rmarkdown",
    svx = "mdsvex",
    "pandoc"
  )
}
