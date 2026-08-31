description <- read.dcf("DESCRIPTION")
requirements <- description[, "SystemRequirements"]

if (!grepl("Cargo", requirements, fixed = TRUE)) {
  stop("`SystemRequirements` must declare Cargo.")
}
if (!grepl("rustc", requirements, fixed = TRUE)) {
  stop("`SystemRequirements` must declare rustc.")
}

path <- paste(Sys.getenv("PATH"), file.path(Sys.getenv("HOME"), ".cargo", "bin"), sep = .Platform$path.sep)
Sys.setenv(PATH = path)

command_version <- function(command) {
  output <- tryCatch(
    system2(command, "--version", stdout = TRUE, stderr = TRUE),
    error = function(error) character()
  )
  if (!length(output)) {
    stop("The `", command, "` command was not found. Install Rust from https://rustup.rs.")
  }
  output[[1L]]
}

rustc_version <- command_version("rustc")
cargo_version <- command_version("cargo")
extract_version <- function(x) sub(".*?(\\d+\\.\\d+(?:\\.\\d+)?).*", "\\1", x)
required <- extract_version(requirements)
installed <- extract_version(rustc_version)

if (utils::compareVersion(required, installed) > 0L) {
  stop("Rust ", required, " or newer is required; found ", installed, ".")
}

message("Using ", cargo_version)
message("Using ", rustc_version)
