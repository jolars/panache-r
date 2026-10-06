normalize_config_path <- function(config) {
  if (is.null(config)) {
    return(NULL)
  }
  if (is.list(config) || identical(config, FALSE)) {
    stop(
      "`config` must be a TOML path or NULL. Use named arguments for overrides ",
      "and `isolated = TRUE` to ignore configuration files.",
      call. = FALSE
    )
  }
  config <- scalar_character(config, "config")
  if (!nzchar(config)) {
    stop("`config` must not be empty.", call. = FALSE)
  }
  path.expand(config)
}

scalar_flag <- function(value, name) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    stop("`", name, "` must be TRUE or FALSE.", call. = FALSE)
  }
  value
}

normalize_format_options <- function(options) {
  options <- Filter(Negate(is.null), options)
  choices <- list(
    line_ending = c("auto", "lf", "crlf"),
    wrap = c("reflow", "sentence", "semantic", "preserve"),
    math = c("reflow", "normalize", "verbatim"),
    math_delimiter_style = c("preserve", "dollars", "backslash"),
    tab_stops = c("normalize", "preserve"),
    horizontal_rule_style = c("line-width", "compact")
  )
  for (name in intersect(names(options), names(choices))) {
    value <- scalar_character(options[[name]], name)
    options[[name]] <- match.arg(value, choices[[name]])
  }
  for (name in intersect(names(options), c("line_width", "tab_width"))) {
    options[[name]] <- positive_integer(options[[name]], name)
  }
  for (name in intersect(names(options), c("math_indent", "table_indent"))) {
    value <- options[[name]]
    maximum <- if (name == "table_indent") 3 else .Machine$integer.max
    if (
      !is.numeric(value) ||
        length(value) != 1L ||
        is.na(value) ||
        !is.finite(value) ||
        value != trunc(value) ||
        value < 0 ||
        value > maximum
    ) {
      stop(
        "`",
        name,
        "` must be a whole number from 0 through ",
        maximum,
        ".",
        call. = FALSE
      )
    }
    options[[name]] <- as.integer(value)
  }
  if (!is.null(options$lang)) {
    options$lang <- scalar_character(options$lang, "lang")
  }
  normalize_config_value(options, "format")
}

normalize_section <- function(value, name) {
  if (is.null(value)) {
    return(NULL)
  }
  if (!is.list(value)) {
    stop("`", name, "` must be a named list.", call. = FALSE)
  }
  value <- normalize_config_value(value, name, field = name)
  if (name == "formatters") {
    for (key in names(value)) {
      entry <- value[[key]]
      if (!is.character(entry) && !is.list(entry)) {
        stop(
          "`formatters$",
          key,
          "` must be a preset, chain, or named definition.",
          call. = FALSE
        )
      }
      if (is.list(entry)) {
        fields <- c(
          "preset",
          "cmd",
          "args",
          "stdin",
          "prepend-args",
          "append-args"
        )
        unknown <- setdiff(names(entry), fields)
        if (length(unknown)) {
          stop(
            "Unknown `formatters$",
            key,
            "` option: ",
            unknown[[1L]],
            call. = FALSE
          )
        }
      }
    }
  }
  value
}

normalize_config_value <- function(value, context, field = "", parent = "") {
  if (is.null(value) || is.object(value) || !is.null(dim(value))) {
    stop(
      "`",
      context,
      "` must contain plain lists or non-missing atomic values.",
      call. = FALSE
    )
  }
  array <- field %in%
    c(
      "args",
      "prepend-args",
      "append-args",
      "exclude",
      "include",
      "extend-exclude",
      "extend-include",
      "crossref-prefixes"
    ) ||
    parent %in% c("math-signatures", "flavors", "no-break-abbreviations") ||
    (field == "no-break-abbreviations" && is.null(names(value)))
  if (array) {
    # Preserve array shape even when it contains zero or one element.
    if (!length(value)) {
      return(character())
    }
    return(lapply(
      seq_along(value),
      function(i) {
        normalize_config_value(value[[i]], paste0(context, "[[", i, "]]"))
      }
    ))
  }
  if (is.list(value)) {
    dynamic <- field %in%
      c(
        "formatters",
        "math-signatures",
        "no-break-abbreviations",
        "flavors",
        "flavor-overrides",
        "linters"
      )
    keys <- names(value)
    if (
      length(value) &&
        (is.null(keys) || anyNA(keys) || (!dynamic && !all(nzchar(keys))))
    ) {
      stop("`", context, "` must be a named list.", call. = FALSE)
    }
    if (!dynamic) {
      keys <- gsub("_", "-", keys, fixed = TRUE)
    }
    if (anyDuplicated(keys)) {
      stop("`", context, "` contains duplicate option names.", call. = FALSE)
    }
    names(value) <- keys
    for (i in seq_along(value)) {
      value[[i]] <- normalize_config_value(
        value[[i]],
        paste0(context, "$", keys[[i]]),
        keys[[i]],
        parent = field
      )
    }
    return(value)
  }
  if (!is.character(value) && !is.logical(value) && !is.numeric(value)) {
    stop("Unsupported value in `", context, "`.", call. = FALSE)
  }
  if (anyNA(value) || (is.numeric(value) && any(!is.finite(value)))) {
    stop(
      "`",
      context,
      "` must not contain missing or non-finite values.",
      call. = FALSE
    )
  }
  value
}
