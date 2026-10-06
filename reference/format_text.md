# Format a document with Panache

`format_text()` formats a complete document held in a character scalar.
Use `range` to restrict formatting to a one-indexed, inclusive line
range; Panache formats blocks overlapping that range. External code
formatters use Panache's `[formatters]` configuration, including
presets, custom commands, and chains. When no R formatter is configured,
R code chunks and fenced R code blocks use
[`arity::format_text()`](https://rdrr.io/pkg/arity/man/format_text.html)
without a separate CLI installation. If arity cannot format a chunk, a
warning is issued and its code is preserved.

## Usage

``` r
format_text(
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
)
```

## Arguments

- text:

  A character scalar containing a valid UTF-8 document. Strings with a
  declared encoding are converted to UTF-8.

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

- path:

  Optional document path used to detect the flavor and discover
  configuration. If `NULL`, discovery starts in the working directory.
  The file is not read.

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
  loaded configuration. A definition can use `code_style_args` to append
  arguments from per-block `code-style` values, replacing `{value}` with
  the value. The default arity R interface uses the resolved line width,
  capped at 1000 columns.

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

A character scalar containing the formatted document.

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

## Examples

``` r
format_text("# Heading\n\nSome text.\n", flavor = "quarto")
#> [1] "# Heading\n\nSome text.\n"
format_text("A short paragraph.\n", line_width = 60, isolated = TRUE)
#> [1] "A short paragraph.\n"
```
