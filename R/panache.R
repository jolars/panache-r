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
#' Use `formatters = list(r = "arity")` to select the arity CLI, replace
#' `"arity"` with `"air"` to select Air, or with `character()` to leave R code
#' alone. Custom commands and other languages use the same configuration as the
#' Panache CLI. External formatters must be installed separately. If a command
#' is unavailable or a formatter chain fails, the original code is preserved.
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
#' @param config A character scalar giving a TOML configuration path, or `NULL`
#'   to discover configuration. Discovery uses the nearest project file, then
#'   `PANACHE_CONFIG`, then the user configuration. Files can inherit settings
#'   through `extend`. Lists and logical values are not accepted.
#' @param isolated Whether to ignore all configuration files, including an
#'   explicit `config` path. Named overrides and path-based flavor detection
#'   still apply. Defaults to `FALSE`.
#' @param line_ending Output line endings: `"auto"`, `"lf"`, or `"crlf"`.
#'   `"auto"` preserves the first source line ending's style.
#' @param math Math formatting: `"reflow"`, `"normalize"`, or `"verbatim"`.
#' @param math_indent Nonnegative indentation width for display math.
#' @param math_delimiter_style Math delimiters: `"preserve"`, `"dollars"`, or
#'   `"backslash"`.
#' @param math_signatures Named list of TeX command signatures, without leading
#'   backslashes in command names. Each signature is a list of argument
#'   definitions, for example `list(custom = list(list(kind = "brace", domain =
#'   "text")))`.
#' @param table_indent Table indentation from 0 through 3 spaces.
#' @param tab_stops Tab handling: `"normalize"` or `"preserve"`.
#' @param tab_width Positive tab width used when normalizing tabs.
#' @param horizontal_rule_style Horizontal rules: `"line-width"` or `"compact"`.
#' @param lang Fallback document language for sentence wrapping, such as `"en"`.
#' @param no_break_abbreviations Character vector of additional abbreviations
#'   for sentence wrapping, or a named list of vectors keyed by language, with
#'   an optional `default` entry.
#' @param formatters Named list of language mappings and formatter definitions,
#'   corresponding to `[formatters]` in TOML. Use `list(r = character())` to
#'   preserve R code. Definitions can refer to presets or names from the loaded
#'   configuration. The default arity R interface uses the resolved line width,
#'   capped at 1000 columns.
#' @param extensions Named list of extension flags, optionally grouped by
#'   flavor, corresponding to `[extensions]` in TOML.
#' @param compat Named list of compatibility targets, corresponding to
#'   `[compat]` in TOML, for example `list(pandoc = "3.7")`.
#' @param flavors Named list of filename-pattern vectors keyed by flavor,
#'   corresponding to `[flavors]` in TOML. Patterns merge by path pattern, as
#'   with `extend`; assigning a pattern to a new flavor replaces its old
#'   mapping.
#'
#' @details
#' Formatting options are named arguments corresponding to settings under
#' `[format]` in TOML. `NULL` inherits the configuration value or engine
#' default. Explicit arguments override configuration values. Grouped arguments
#' merge supplied entries, preserving unspecified settings; arrays replace
#' inherited arrays, except for the pattern-based `flavors` merge. Empty grouped
#' lists make no changes. List option names accept underscores or hyphens.
#'
#' @param path Optional document path used to detect the flavor and discover
#'   configuration. If `NULL`, discovery starts in the working directory. The
#'   file is not read.
#'
#' @return A character scalar containing the formatted document.
#' @export
#'
#' @examples
#' panache_format("# Heading\n\nSome text.\n", flavor = "quarto")
#' panache_format("A short paragraph.\n", line_width = 60, isolated = TRUE)
panache_format <- function(
  text,
  flavor = NULL,
  line_width = NULL,
  wrap = NULL,
  range = NULL,
  config = NULL,
  path = NULL,
  line_ending = NULL,
  math = NULL,
  math_indent = NULL,
  math_delimiter_style = NULL,
  math_signatures = NULL,
  table_indent = NULL,
  tab_stops = NULL,
  tab_width = NULL,
  horizontal_rule_style = NULL,
  lang = NULL,
  no_break_abbreviations = NULL,
  formatters = NULL,
  extensions = NULL,
  compat = NULL,
  flavors = NULL,
  isolated = FALSE
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
  config <- normalize_config_path(config)
  isolated <- scalar_flag(isolated, "isolated")
  overrides <- list(
    format = normalize_format_options(list(
      line_width = line_width,
      wrap = wrap,
      line_ending = line_ending,
      math = math,
      math_indent = math_indent,
      math_delimiter_style = math_delimiter_style,
      math_signatures = math_signatures,
      table_indent = table_indent,
      tab_stops = tab_stops,
      tab_width = tab_width,
      horizontal_rule_style = horizontal_rule_style,
      lang = lang,
      no_break_abbreviations = no_break_abbreviations
    )),
    formatters = normalize_section(formatters, "formatters"),
    extensions = normalize_section(extensions, "extensions"),
    compat = normalize_section(compat, "compat"),
    flavors = normalize_section(flavors, "flavors")
  )
  overrides <- Filter(Negate(is.null), overrides)
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
    start_line,
    end_line,
    r_formatter,
    config,
    path,
    isolated,
    overrides
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
#' @inherit panache_format details
#'
#' @return Invisibly, `TRUE` if the file changed and `FALSE` otherwise.
#' @export
panache_format_file <- function(
  path,
  flavor = NULL,
  line_width = NULL,
  wrap = NULL,
  range = NULL,
  config = NULL,
  line_ending = NULL,
  math = NULL,
  math_indent = NULL,
  math_delimiter_style = NULL,
  math_signatures = NULL,
  table_indent = NULL,
  tab_stops = NULL,
  tab_width = NULL,
  horizontal_rule_style = NULL,
  lang = NULL,
  no_break_abbreviations = NULL,
  formatters = NULL,
  extensions = NULL,
  compat = NULL,
  flavors = NULL,
  isolated = FALSE
) {
  path <- path.expand(scalar_character(path, "path"))
  if (!file.exists(path)) {
    stop("File does not exist: ", path, call. = FALSE)
  }
  input <- rawToChar(readBin(path, what = "raw", n = file.info(path)$size))
  input <- utf8_character(input, "file contents")
  output <- panache_format(
    text = input,
    flavor = flavor,
    line_width = line_width,
    wrap = wrap,
    range = range,
    config = config,
    path = path,
    line_ending = line_ending,
    math = math,
    math_indent = math_indent,
    math_delimiter_style = math_delimiter_style,
    math_signatures = math_signatures,
    table_indent = table_indent,
    tab_stops = tab_stops,
    tab_width = tab_width,
    horizontal_rule_style = horizontal_rule_style,
    lang = lang,
    no_break_abbreviations = no_break_abbreviations,
    formatters = formatters,
    extensions = extensions,
    compat = compat,
    flavors = flavors,
    isolated = isolated
  )
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
