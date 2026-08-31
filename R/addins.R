#' Format the active document with Panache
#'
#' These functions back the RStudio addins registered by the package. They must
#' be called from an active RStudio source editor.
#'
#' @return `NULL`, invisibly.
#' @export
format_document_addin <- function() {
  context <- active_document_context()
  flavor <- flavor_from_path(context$path)
  input <- paste(context$contents, collapse = "\n")
  output <- panache_format(input, flavor = flavor)

  if (!identical(input, output)) {
    rstudioapi::setDocumentContents(output, id = context$id)
  }

  invisible(NULL)
}

#' @rdname format_document_addin
#' @export
format_selection_addin <- function() {
  context <- active_document_context()
  selections <- context$selection
  if (length(selections) != 1L) {
    stop("Panache can format only one selection at a time.", call. = FALSE)
  }

  selection <- selections[[1L]]$range
  range <- c(selection$start$row, selection$end$row)
  input <- paste(context$contents, collapse = "\n")
  output <- panache_format(
    input,
    flavor = flavor_from_path(context$path),
    range = range
  )

  if (!identical(input, output)) {
    rstudioapi::setDocumentContents(output, id = context$id)
  }

  invisible(NULL)
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
