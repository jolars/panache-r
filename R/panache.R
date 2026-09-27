#' Format a document with Panache
#'
#' `panache_format()` formats a complete document held in a character scalar.
#' Use `range` to restrict formatting to a one-indexed, inclusive line range;
#' Panache formats blocks overlapping that range. External code formatters use
#' Panache's `[formatters]` configuration, including presets, custom commands,
#' and chains. When no R formatter is configured, R code chunks and fenced R
#' code blocks use [arity::format_text()] without a separate CLI installation.
#' If arity cannot format a chunk, a warning is issued and its code is
#' preserved.
#'
#' Use `config = list(formatters = list(r = "arity"))` to select the arity CLI,
#' replace `"arity"` with `"air"` to select Air, or with `character()` to leave
#' R code alone. Custom commands and other languages use the same configuration
#' as the Panache CLI. External formatters must be installed separately. If a
#' command is unavailable or a formatter chain fails, the original code is
#' preserved.
#'
#' @param text A character scalar containing a valid UTF-8 document. Strings
#'   with a declared encoding are converted to UTF-8.
#' @param flavor The Markdown flavor, or `NULL` to use configuration and path
#'   detection (falling back to `"pandoc"`). One of `"pandoc"`, `"quarto"`,
#'   `"rmarkdown"`, `"gfm"`, `"commonmark"`, `"multimarkdown"`, `"mdsvex"`, or
#'   `"myst"`.
#' @param line_width A positive integer giving the target line width, or `NULL`
#'   to use the configuration value (80 by default).
#' @param wrap The wrapping strategy. One of `"reflow"`, `"sentence"`,
#'   `"semantic"`, or `"preserve"`. `NULL` uses the configuration value
#'   (`"reflow"` by default).
#' @param range `NULL`, or an integer vector containing the first and last lines
#'   to format.
#' @param config A named list of Panache options, a character scalar giving a
#'   TOML configuration path, `NULL` to discover a file, or `FALSE` to use only
#'   defaults. Lists mirror the TOML sections, for example
#'   `list(format = list(line_width = 100), formatters = list(r = "air"))`.
#'   Option names accept underscores or hyphens. `line_width`, `line_ending`,
#'   and `wrap` can also appear directly in the list. Explicit `flavor`,
#'   `line_width`, and `wrap` arguments override configuration values. Lists do
#'   not discover or inherit files; `list()` uses defaults. TOML paths support
#'   `extend`. Discovery follows the Panache CLI: the nearest project file, then
#'   `PANACHE_CONFIG`, then the user configuration. The default arity R
#'   interface uses the resolved line width, capped at 1000 columns.
#' @param path Optional document path used to detect the flavor and discover
#'   configuration. If `NULL`, discovery starts in the working directory. The
#'   file is not read.
#'
#' @return A character scalar containing the formatted document.
#' @export
#'
#' @examples
#' panache_format("# Heading\n\nSome text.\n", flavor = "quarto")
#' panache_format("A short paragraph.\n", config = list(line_width = 60))
panache_format <- function(
  text,
  flavor = NULL,
  line_width = NULL,
  wrap = NULL,
  range = NULL,
  config = NULL,
  path = NULL
) {
  text <- utf8_character(text, "text")
  if (!is.null(flavor)) {
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
  }
  if (!is.null(wrap)) {
    wrap <- match.arg(wrap, c("reflow", "sentence", "semantic", "preserve"))
  }

  if (!is.null(line_width)) {
    line_width <- positive_integer(line_width, "line_width")
  }
  config <- normalize_config(config)
  if (!is.null(path)) {
    path <- path.expand(scalar_character(path, "path"))
  }

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

  problems <- character()
  r_formatter <- function(code, line_width) {
    tryCatch(
      arity::format_text(
        code,
        line_width = min(line_width, 1000L),
        line_ending = "lf"
      ),
      error = function(error) {
        problems <<- c(problems, conditionMessage(error))
        code
      }
    )
  }
  output <- unwrap_extendr_result(rust_format_document(
    text,
    flavor,
    line_width,
    wrap,
    start_line,
    end_line,
    r_formatter,
    config,
    path
  ))
  # Signal warnings here so callers can handle them outside the Rust callback.
  for (problem in problems) {
    warning("Could not format R code chunk: ", problem, call. = FALSE)
  }
  output
}

#' Format a file with Panache
#'
#' The file is replaced only when formatting changes its contents.
#'
#' @param path Path to a UTF-8 Markdown, Quarto, or R Markdown document.
#' @inheritParams panache_format
#'
#' @return Invisibly, `TRUE` if the file changed and `FALSE` otherwise.
#' @export
panache_format_file <- function(
  path,
  flavor = NULL,
  line_width = NULL,
  wrap = NULL,
  range = NULL,
  config = NULL
) {
  path <- scalar_character(path, "path")
  if (!file.exists(path)) {
    stop("File does not exist: ", path, call. = FALSE)
  }
  input <- rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
  input <- utf8_character(input, "file contents")
  output <- panache_format(input, flavor, line_width, wrap, range, config, path)
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
