// Forward registration to Rust so the linker retains the static library.

void R_init_panache_extendr(void *dll);

void R_init_panache(void *dll) {
    R_init_panache_extendr(dll);
}
