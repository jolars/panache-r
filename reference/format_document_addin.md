# Format the active document with Panache

These functions back the RStudio addins registered by the package. They
must be called from an active RStudio source editor. External formatters
are configured through the active document's Panache configuration. R
code defaults to the arity R package when no R formatter is configured.

## Usage

``` r
format_document_addin(
  config = getOption("panache.config", NULL),
  isolated = FALSE,
  ...
)

format_selection_addin(
  config = getOption("panache.config", NULL),
  isolated = FALSE,
  ...
)
```

## Arguments

- config:

  A TOML path or `NULL` for discovery, as in
  [`format_text()`](https://jolars.github.io/panache-r/reference/format_text.md).
  Defaults to the `panache.config` R option, allowing a configuration
  path to be set from `.Rprofile`.

- isolated:

  Whether to ignore configuration files.

- ...:

  Named formatting overrides passed to
  [`format_text()`](https://jolars.github.io/panache-r/reference/format_text.md).

## Value

`NULL`, invisibly.
