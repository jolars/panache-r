# panache

The **panache** R package formats Markdown, Quarto, and R Markdown documents
with Panache's Rust formatting engine.

The package is in early development. It currently provides an in-process R
interface and RStudio addins for formatting a complete document or the selected
block range.

R code chunks and fenced R code blocks default to the
[arity R package](https://cran.r-project.org/package=arity), which is installed
automatically as a dependency. No separate arity executable is needed.

```r
panache::panache_format(
  "# Heading\n\nA paragraph that should be formatted.\n",
  flavor = "quarto"
)
```

Pass a named R list to configure document formatting and external code
formatters. Lists mirror Panache's TOML sections, with underscores or hyphens
in option names:

```r
panache::panache_format(
  document,
  config = list(
    format = list(line_width = 100, wrap = "sentence"),
    formatters = list(r = "air", python = "ruff")
  )
)
```

You can also use the same `panache.toml` configuration as the Panache CLI.
For example, use the arity CLI for R and Ruff for Python:

```toml
[formatters]
r = "arity"
python = "ruff"
```

Set `r = "air"` to use Air, or `r = []` (`r = character()` in an R list) to
preserve R code. Omitting the R
mapping keeps the default arity R interface, even when other languages have
configured formatters. The explicitly selected CLI programs must be installed
and available on `PATH`.

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
`panache_format_file()` does the same. `panache_format()` searches from the
working directory unless you supply a document `path`. Discovery, user
configuration, `PANACHE_CONFIG`, and `extend` follow the Panache CLI.

The `config` argument accepts:

- `NULL` (the default): discover configuration.
- `"path/to/panache.toml"`: load that file, including any `extend` chain.
- A named list: use the supplied options and defaults, without discovering
  or inheriting files. `list()` uses defaults.
- `FALSE`: use defaults without discovering configuration.

Explicit `flavor`, `line_width`, and `wrap` arguments override configuration
values. In lists, `line_width`, `line_ending`, and `wrap` can also appear at
the top level, for example `config = list(line_width = 100)`.

Both addins also accept `config` directly and default to the `panache.config`
R option. Set it in your R session or `.Rprofile` to configure the addin menu
commands:

```r
options(panache.config = list(
  format = list(line_width = 100),
  formatters = list(python = "ruff")
))
```

This example keeps the built-in arity R formatter. To select the arity CLI,
add `r = "arity"` to `formatters`.

Chunk options and ignore regions are preserved, and selection formatting
affects only the selected blocks. A missing or failing external formatter
leaves the chunk's code intact. Invalid R code handled by the default arity R
interface also produces an R warning. Inline code is not sent to formatters.

Installing from source requires Cargo and Rust 1.89 or newer. CRAN source
tarballs include vendored Rust dependencies and build without network access.
