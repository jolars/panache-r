#' Format the active document with Panache
#'
#' These functions back the RStudio addins registered by the package. They must
#' be called from an active RStudio source editor. External formatters are
#' configured through the active document's Panache configuration. R code
#' defaults to the arity R package when no R formatter is configured.
#'
#' @param config A TOML path or `NULL` for discovery, as in [format_text()].
#'   Defaults to the `panache.config` R option, allowing a configuration path to
#'   be set from `.Rprofile`.
#' @param isolated Whether to ignore configuration files.
#' @param ... Named formatting overrides passed to [format_text()].
#'
#' @return `NULL`, invisibly.
#' @export
format_document_addin <- function(
  config = getOption("panache.config", NULL),
  isolated = FALSE,
  ...
) {
  context <- active_document_context()
  input <- paste(context$contents, collapse = "\n")
  output <- format_text(
    input,
    config = config,
    isolated = isolated,
    ...,
    path = document_path(context)
  )

  if (!identical(input, output)) {
    rstudioapi::setDocumentContents(output, id = context$id)
  }

  invisible(NULL)
}

#' @rdname format_document_addin
#' @export
format_selection_addin <- function(
  config = getOption("panache.config", NULL),
  isolated = FALSE,
  ...
) {
  context <- active_document_context()
  selections <- context$selection
  if (length(selections) != 1L) {
    stop("Panache can format only one selection at a time.", call. = FALSE)
  }

  selection <- selections[[1L]]$range
  range <- c(selection$start$row, selection$end$row)
  input <- paste(context$contents, collapse = "\n")
  output <- format_text(
    input,
    config = config,
    isolated = isolated,
    ...,
    range = range,
    path = document_path(context)
  )

  if (!identical(input, output)) {
    rstudioapi::setDocumentContents(output, id = context$id)
  }

  invisible(NULL)
}

document_path <- function(context) {
  if (nzchar(context$path)) context$path else NULL
}

active_document_context <- function() {
  if (!requireNamespace("rstudioapi", quietly = TRUE)) {
    stop(
      "The `rstudioapi` package is required to run this addin.",
      call. = FALSE
    )
  }
  if (!rstudioapi::isAvailable()) {
    stop("This function must be run inside RStudio.", call. = FALSE)
  }

  context <- rstudioapi::getSourceEditorContext()
  if (!nzchar(context$id)) {
    stop("No source document is active.", call. = FALSE)
  }
  context
}
