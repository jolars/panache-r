# Repository Guidelines

## Project Structure & Module Organization

`panache` is an R package backed by a Rust formatting engine. Public R APIs and
RStudio addins live in `R/`; their generated help pages are in `man/`, and
exports are recorded in `NAMESPACE`. The extendr bridge is implemented in
`src/rust/src/lib.rs`, with its crate metadata in `src/rust/Cargo.toml` and C
registration code in `src/`. Package tests live in `tests/testthat/`. RStudio
addin metadata belongs in `inst/rstudio/`, while build helpers belong in
`tools/`. Do not commit build outputs such as `panache.Rcheck/`, Rust `target/`
directories, or generated `src/Makevars` files.

## Build, Test, and Development Commands

Enter the Nix/devenv shell before development so the required R and Rust tools
are available. Use the Task targets as the canonical workflows:

- `task install` installs a clean local build of the package.
- `task build` creates the R source tarball.
- `task check` builds and runs `R CMD check --no-manual`.
- `task test-rust` runs the Rust bridge's unit tests.
- `task test` runs the R tests during iteration.
- `task rust-fmt` and `task rust-clippy` enforce Rust formatting and lints.
- `task vendor` refreshes the compressed Rust dependencies used for offline CRAN
  builds; commit the resulting lockfile and archive together.

## Coding Style & Naming Conventions

Use two-space indentation in R, `<-` for assignment, `snake_case` identifiers,
and roxygen2 comments for exported functions. Keep generated `man/*.Rd`,
`NAMESPACE`, and `R/extendr-wrappers.R` synchronized through their generators
rather than hand-editing them. Follow `rustfmt` defaults in Rust, use
`snake_case` for functions, and keep the package compatible with Rust 1.89. Run
the Rust formatting and lint tasks before submitting Rust changes.

## Testing Guidelines

The R suite uses testthat edition 3. Add focused files named
`tests/testthat/test-<feature>.R`, with behavior-oriented `test_that()` labels.
Place Rust unit tests beside their implementation under `#[cfg(test)]`. Cover
happy paths, input validation, and R/Rust boundary behavior. No coverage
threshold is configured; every behavioral change should include a regression
test. Finish by running both `task test-rust` and `task check`.

## Commit & Pull Request Guidelines

History follows Conventional Commits, for example `chore: setup devenv`; use
short, imperative subjects such as `fix: reject empty input`. Pull requests
should explain the user-visible effect, summarize validation performed, and link
relevant issues. Include screenshots only for RStudio addin UI changes. CI must
pass `R CMD check` on Linux, macOS, and Windows.
