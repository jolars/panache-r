normalize_config <- function(config) {
  if (is.null(config) || identical(config, FALSE)) {
    return(config)
  }
  if (!is.list(config)) {
    return(path.expand(scalar_character(config, "config")))
  }
  config <- normalize_config_value(config, "config")
  if ("extend" %in% names(config)) {
    stop(
      "`config$extend` requires a TOML file; pass its path as `config`.",
      call. = FALSE
    )
  }
  for (name in intersect(
    c("line-width", "line-ending", "wrap"),
    names(config)
  )) {
    if (name %in% names(config[["format"]])) {
      stop("`config` specifies `", name, "` more than once.", call. = FALSE)
    }
    config[["format"]][[name]] <- config[[name]]
    config[[name]] <- NULL
  }
  if ("formatters" %in% names(config)) {
    if (!is.list(config$formatters)) {
      stop("`config$formatters` must be a named list.", call. = FALSE)
    }
    for (name in names(config$formatters)) {
      value <- config$formatters[[name]]
      if (!is.character(value) && !is.list(value)) {
        stop(
          "`config$formatters$",
          name,
          "` must be a preset, chain, or named definition.",
          call. = FALSE
        )
      }
      if (is.list(value)) {
        fields <- c("cmd", "args", "stdin", "prepend-args", "append-args")
        unknown <- setdiff(names(value), fields)
        if (length(unknown)) {
          stop(
            "Unknown `config$formatters$",
            name,
            "` option: ",
            unknown[[1L]],
            call. = FALSE
          )
        }
      }
    }
  }
  config
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
        (is.null(keys) || anyNA(keys) || (!dynamic && any(!nzchar(keys))))
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
