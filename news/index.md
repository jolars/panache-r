# Changelog

## panache 0.1.0

- Added the initial Rust-backed formatter API and RStudio addins.

### Breaking changes

- expose named formatting options
  ([`dd9c15d`](https://github.com/jolars/panache-r/commit/dd9c15db287a20e4f2661c708491042b88ed216f))

### Features

- rename to `format_file` and `format_text`
  ([`75ab8f4`](https://github.com/jolars/panache-r/commit/75ab8f45dea6b4e58e1ba7e0560a6b78fdb01ea2))
- expose named formatting options
  ([`dd9c15d`](https://github.com/jolars/panache-r/commit/dd9c15db287a20e4f2661c708491042b88ed216f))
- configure chunk formatters with arity by default
  ([`c6ee073`](https://github.com/jolars/panache-r/commit/c6ee07344b388d6cf3e1d5920a1ba2abfc75a018))
- setup package and tests
  ([`fa1b485`](https://github.com/jolars/panache-r/commit/fa1b48542a391fa13583bf71776b0709ea7da8ba))

### Bug fixes

- handle formatter limits and timeouts
  ([`d4d0eac`](https://github.com/jolars/panache-r/commit/d4d0eac50b4db13d96c6e85101f2dd840619356d))
- resolve symlinked paths for flavor matching
  ([`4ad4045`](https://github.com/jolars/panache-r/commit/4ad4045d708cdb2950a2dd79ba1fe88c06077c65))
