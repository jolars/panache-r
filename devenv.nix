{
  pkgs,
  ...
}:

{
  packages = [
    pkgs.bashInteractive
    pkgs.checkbashisms
    pkgs.cargo-audit
    pkgs.cargo-deny
    pkgs.cargo-msrv
    pkgs.go-task
    pkgs.llvmPackages.bintools
  ];

  languages = {
    rust = {
      enable = true;
      toolchainFile = ./src/rust/rust-toolchain.toml;
    };

    r = {
      enable = true;

      package = (
        pkgs.rWrapper.override {
          packages = with pkgs.rPackages; [
            covr
            devtools
            knitr
            rextendr
            rmarkdown
            spelling
            testthat
            urlchecker
            remotes
            rstudioapi
            testthat
          ];
        }
      );
    };
  };
}
