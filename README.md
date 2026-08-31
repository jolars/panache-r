# panache

The **panache** R package formats Markdown, Quarto, and R Markdown documents
with Panache's Rust formatting engine.

The package is in early development. It currently provides an in-process R
interface and RStudio addins for formatting a complete document or the selected
block range.

```r
panache::panache_format(
  "# Heading\n\nA paragraph that should be formatted.\n",
  flavor = "quarto"
)
```

Installing from source requires Cargo and Rust 1.89 or newer. CRAN source
tarballs include vendored Rust dependencies and build without network access.
