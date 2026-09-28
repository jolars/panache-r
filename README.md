# panache

<!-- badges: start -->
[![CRAN
status](https://www.r-pkg.org/badges/version/panache)](https://CRAN.R-project.org/package=panach e)
<!-- badges: end -->

The **panache** R package formats Markdown, Quarto, and R Markdown documents
with Panache's Rust formatting engine.

The package is in early development. It currently provides an in-process R
interface and RStudio addins for formatting a complete document or the selected
block range.

See the [package website](https://jolars.github.io/panache-r/) for the function
reference.

## Installation

Install the development version from GitHub:

```r
remotes::install_github("jolars/panache-r")
```

Installing from source requires Cargo and Rust 1.89 or newer. CRAN source
tarballs include vendored Rust dependencies and build without network access.

## Usage

R code chunks and fenced R code blocks default to the [arity R
package](https://cran.r-project.org/package=arity), which is installed
automatically as a dependency. No separate arity executable is needed.

```r
panache::format_text(
  "# Heading\n\nA paragraph that should be formatted.\n",
  flavor = "quarto"
)
```

Use named arguments for formatting settings and named lists for related sections
such as external code formatters:

```r
panache::format_text(
  document,
  line_width = 100,
  wrap = "sentence",
  line_ending = "lf",
  formatters = list(r = "air", python = "ruff")
)
```

Formatting arguments correspond to settings under `[format]` in TOML.
`formatters`, `extensions`, `compat`, and `flavors` correspond to the respective
TOML sections. List option names accept underscores or hyphens.

## Configuration

You can also use the same `panache.toml` configuration as the Panache CLI. For
example, use the arity CLI for R and Ruff for Python:

```toml
[formatters]
r = "arity"
python = "ruff"
```

Set `r = "air"` to use Air, or `r = []` (`r = character()` in an R list) to
preserve R code. Omitting the R mapping keeps the default arity R interface,
even when other languages have configured formatters. The explicitly selected
CLI programs must be installed and available on `PATH`.

Panache's presets, formatter chains, language aliases, and custom commands all
work here. A custom formatter can read standard input or edit a temporary file:

```toml
[formatters]
r = "my-formatter"
python = ["isort", "black"]

[formatters.my-formatter]
cmd = "my-r-formatter"
args = ["format", "{}"]
stdin = false
```

Both RStudio addins discover configuration from the active document's directory.
`format_file()` does the same. `format_text()` searches from the working
directory unless you supply a document `path`. Discovery, user configuration,
`PANACHE_CONFIG`, and `extend` follow the Panache CLI.

The `config` argument selects a configuration file:

- `NULL` (the default): discover configuration.
- `"path/to/panache.toml"`: load that file, including any `extend` chain.

Set `isolated = TRUE` to ignore all configuration files, including an explicit
`config` path. Named arguments and path-based flavor detection still apply.

Named formatting arguments default to `NULL`, which inherits the configuration
value or engine default. Explicit values override configuration. Grouped
arguments merge supplied entries while preserving unspecified settings. Arrays
replace inherited arrays, including empty formatter chains. As in TOML
inheritance, `flavors` merges by path pattern, so assigning a pattern to another
flavor replaces its old mapping. Empty grouped lists make no changes.

```r
panache::format_text(
  document,
  config = "panache.toml",
  line_width = 100,
  extensions = list(smart = FALSE)
)
```

Earlier development versions accepted lists or `FALSE` as `config`. Move list
settings to their named arguments and replace `config = FALSE` with
`isolated = TRUE`. Named overrides retain project settings by default; use
isolation when a call should depend only on its arguments and engine defaults.

## RStudio addins

Choose **Format with Panache** or **Format Selection with Panache** from
RStudio's **Addins** menu to format the active document or selected blocks.

Both addins accept a `config` path and default to the `panache.config` R option.
Set it in your R session or `.Rprofile` to select a file for the addin menu
commands:

```r
options(panache.config = "~/config/panache.toml")
```

When called from R, addins also accept `isolated` and named formatting
overrides:

```r
panache::format_document_addin(line_width = 100, formatters = list(r = "air"))
```

## Formatting behavior

Chunk options and ignore regions are preserved, and selection formatting affects
only the selected blocks. A missing or failing external formatter leaves the
chunk's code intact. Invalid R code handled by the default arity R interface
also produces an R warning. Inline code is not sent to formatters. External
commands have a 30-second timeout per command. Timed-out processes are
terminated before formatting returns. Concurrency follows
`external-max-parallel` in the configuration. During CRAN checks, a nonempty
`_R_CHECK_LIMIT_CORES_` caps it at two processes. A positive `OMP_THREAD_LIMIT`
also limits concurrency.
