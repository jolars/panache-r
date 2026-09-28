# Format a file with Panache

The file is replaced only when formatting changes its contents.

## Usage

``` r
format_file(
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
)
```

## Arguments

- path:

  Path to a UTF-8 Markdown, Quarto, or R Markdown document.

- flavor:

  The Markdown flavor, or `NULL` to use configuration and path detection
  (falling back to `"pandoc"`). One of `"pandoc"`, `"quarto"`,
  `"rmarkdown"`, `"gfm"`, `"commonmark"`, `"multimarkdown"`, `"mdsvex"`,
  or `"myst"`.

- line_width:

  A positive integer giving the target line width, or `NULL` to use the
  configuration value (80 by default).

- wrap:

  The wrapping strategy. One of `"reflow"`, `"sentence"`, `"semantic"`,
  or `"preserve"`. `NULL` uses the configuration value (`"reflow"` by
  default).

- range:

  `NULL`, or an integer vector containing the first and last lines to
  format.

- config:

  A character scalar giving a TOML configuration path, or `NULL` to
  discover configuration. Discovery uses the nearest project file, then
  `PANACHE_CONFIG`, then the user configuration. Files can inherit
  settings through `extend`. Lists and logical values are not accepted.

- line_ending:

  Output line endings: `"auto"`, `"lf"`, or `"crlf"`. `"auto"` preserves
  the first source line ending's style.

- math:

  Math formatting: `"reflow"`, `"normalize"`, or `"verbatim"`.

- math_indent:

  Nonnegative indentation width for display math.

- math_delimiter_style:

  Math delimiters: `"preserve"`, `"dollars"`, or `"backslash"`.

- math_signatures:

  Named list of TeX command signatures, without leading backslashes in
  command names. Each signature is a list of argument definitions, for
  example `list(custom = list(list(kind = "brace", domain = "text")))`.

- table_indent:

  Table indentation from 0 through 3 spaces.

- tab_stops:

  Tab handling: `"normalize"` or `"preserve"`.

- tab_width:

  Positive tab width used when normalizing tabs.

- horizontal_rule_style:

  Horizontal rules: `"line-width"` or `"compact"`.

- lang:

  Fallback document language for sentence wrapping, such as `"en"`.

- no_break_abbreviations:

  Character vector of additional abbreviations for sentence wrapping, or
  a named list of vectors keyed by language, with an optional `default`
  entry.

- formatters:

  Named list of language mappings and formatter definitions,
  corresponding to `[formatters]` in TOML. Use `list(r = character())`
  to preserve R code. Definitions can refer to presets or names from the
  loaded configuration. The default arity R interface uses the resolved
  line width, capped at 1000 columns.

- extensions:

  Named list of extension flags, optionally grouped by flavor,
  corresponding to `[extensions]` in TOML.

- compat:

  Named list of compatibility targets, corresponding to `[compat]` in
  TOML, for example `list(pandoc = "3.7")`.

- flavors:

  Named list of filename-pattern vectors keyed by flavor, corresponding
  to `[flavors]` in TOML. Patterns merge by path pattern, as with
  `extend`; assigning a pattern to a new flavor replaces its old
  mapping.

- isolated:

  Whether to ignore all configuration files, including an explicit
  `config` path. Named overrides and path-based flavor detection still
  apply. Defaults to `FALSE`.

## Value

Invisibly, `TRUE` if the file changed and `FALSE` otherwise.

## Details

Use `formatters = list(r = "arity")` to select the arity CLI, replace
`"arity"` with `"air"` to select Air, or with
[`character()`](https://rdrr.io/r/base/character.html) to leave R code
alone. Custom commands and other languages use the same configuration as
the Panache CLI. External formatters must be installed separately. If a
command is unavailable or a formatter chain fails, the original code is
preserved. External commands have a 30-second timeout per command.
Timed-out processes are terminated before returning. Concurrency follows
the configuration, capped at two when `_R_CHECK_LIMIT_CORES_` is
nonempty, and also respects a positive `OMP_THREAD_LIMIT`.

Formatting options are named arguments corresponding to settings under
`[format]` in TOML. `NULL` inherits the configuration value or engine
default. Explicit arguments override configuration values. Grouped
arguments merge supplied entries, preserving unspecified settings;
arrays replace inherited arrays, except for the pattern-based `flavors`
merge. Empty grouped lists make no changes. List option names accept
underscores or hyphens.
