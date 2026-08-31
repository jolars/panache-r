source("tools/msrv.R")

is_debug <- nzchar(Sys.getenv("DEBUG"))
is_not_cran <- nzchar(Sys.getenv("NOT_CRAN")) || is_debug
vendor_exists <- file.exists("src/rust/vendor.tar.xz")

if (is_debug) {
  message("Creating debug build.")
} else if (!is_not_cran) {
  message("Building for CRAN.")
}

.cran_flags <- if (!is_not_cran && vendor_exists) "-j 2 --offline --frozen" else ""
.profile <- if (is_debug) "" else "--release"
.clean_target <- if (is_debug) "" else "$(TARGET_DIR)"
.libdir <- if (is_debug) "debug" else "release"

is_windows <- identical(.Platform[["OS.type"]], "windows")
input <- if (is_windows) "src/Makevars.win.in" else "src/Makevars.in"
output <- if (is_windows) "src/Makevars.win" else "src/Makevars"

if (file.exists(output)) {
  invisible(file.remove(output))
}

contents <- readLines(input, warn = FALSE) |>
  gsub("@CRAN_FLAGS@", .cran_flags, x = _, fixed = TRUE) |>
  gsub("@PROFILE@", .profile, x = _, fixed = TRUE) |>
  gsub("@CLEAN_TARGET@", .clean_target, x = _, fixed = TRUE) |>
  gsub("@LIBDIR@", .libdir, x = _, fixed = TRUE)

writeLines(contents, output, useBytes = TRUE)
message("Wrote `", output, "`.")
