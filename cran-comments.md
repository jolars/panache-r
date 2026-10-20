## Resubmission

This is a resubmission addressing the request to avoid writing to the user's
home filespace by default or in examples and tests.

- `format_file()` requires an explicit path and has no default output location.
- External formatter input, output, and scratch files are created under R's
  session `tempdir()` and removed after success or failure. Child processes
  receive temporary-directory environment variables pointing to that location.
- File-writing examples and tests use temporary paths and clean up afterward.
  Tests now use explicit paths within temporary projects for configuration files
  and directories.
- The RStudio addins update editor buffers without saving files to disk.

## R CMD check results

0 errors, 0 warnings, 1 note

- This is a new release.
