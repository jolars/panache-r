use std::collections::{BTreeMap, HashMap};
use std::time::Duration;

use panache_engine::config;
use panache_formatter::{ExternalCodeBlock, FormattedCodeMap};
use rayon::prelude::*;

use crate::process::format_code;

pub struct ExternalFormatters {
    config: config::Config,
    pub use_builtin_r: bool,
}

impl ExternalFormatters {
    pub fn load(
        config_path: Option<&str>,
        document_path: Option<&str>,
        flavor: Option<config::Flavor>,
        isolated: bool,
        overrides: toml::Table,
    ) -> Result<Self, String> {
        let (config, declarations) =
            crate::config::load_config(config_path, document_path, flavor, isolated, overrides)?;
        Ok(Self {
            config,
            use_builtin_r: !declares_r_formatter(&declarations),
        })
    }

    pub fn formatter_config(&self) -> panache_formatter::Config {
        crate::config::formatter_config(&self.config)
    }

    pub fn parser_options(&self) -> panache_parser::ParserOptions {
        self.config.parser_options()
    }

    pub fn format(&self, blocks: Vec<ExternalCodeBlock>) -> FormattedCodeMap {
        if self.config.formatters.is_empty() || blocks.is_empty() {
            return FormattedCodeMap::new();
        }
        let mut groups: HashMap<
            (String, String, BTreeMap<String, String>),
            Vec<ExternalCodeBlock>,
        > = HashMap::new();
        for block in blocks {
            groups
                .entry((
                    block.language.clone(),
                    block.formatter_input.clone(),
                    block.code_style.clone(),
                ))
                .or_default()
                .push(block);
        }
        let groups: Vec<_> = groups.into_iter().collect();
        let format_group = |((language, input, code_style), blocks): (
            (String, String, BTreeMap<String, String>),
            Vec<ExternalCodeBlock>,
        )| {
            let Some(chain) = resolve_formatters(&self.config.formatters, &language) else {
                return Vec::new();
            };
            if chain.is_empty() {
                return Vec::new();
            }
            let mut formatted = input;
            for formatter in chain {
                if formatter.cmd.trim().is_empty() {
                    continue;
                }
                let mut formatter = formatter.clone();
                for (key, value) in &code_style {
                    if let Some(args) = formatter.code_style_args.get(key) {
                        formatter
                            .args
                            .extend(args.iter().map(|arg| arg.replace("{value}", value)));
                    }
                }
                match format_code(&formatted, &language, &formatter, Duration::from_secs(30)) {
                    Ok(output) => formatted = output,
                    Err(_) => return Vec::new(),
                }
            }
            blocks
                .into_iter()
                .map(|block| {
                    let output = match block.hashpipe_prefix {
                        Some(prefix) => format!("{prefix}{formatted}"),
                        None => formatted.clone(),
                    };
                    (block.offset, output)
                })
                .collect()
        };

        let mut workers = self.config.external_max_parallel.max(1);
        // Rayon does not honor R's check limits or OpenMP's thread limit, so
        // apply these signals without restricting ordinary R sessions.
        if std::env::var_os("_R_CHECK_LIMIT_CORES_").is_some_and(|value| !value.is_empty()) {
            workers = workers.min(2);
        }
        if let Ok(value) = std::env::var("OMP_THREAD_LIMIT")
            && let Ok(limit) = value.trim().parse::<usize>()
            && limit > 0
        {
            workers = workers.min(limit);
        }
        let Ok(pool) = rayon::ThreadPoolBuilder::new()
            .num_threads(workers.min(groups.len()))
            .build()
        else {
            return groups.into_iter().flat_map(format_group).collect();
        };
        pool.install(|| groups.into_par_iter().flat_map(format_group).collect())
    }
}

fn resolve_formatters<'a>(
    formatters: &'a HashMap<String, Vec<config::FormatterConfig>>,
    language: &str,
) -> Option<&'a Vec<config::FormatterConfig>> {
    formatters.get(language).or_else(|| {
        let canonical = canonical_language(language);
        formatters
            .iter()
            .find(|(key, _)| canonical_language(key) == canonical)
            .map(|(_, chain)| chain)
    })
}

fn canonical_language(language: &str) -> String {
    match language_extension(language) {
        "txt" => normalize_language(language),
        extension => extension.to_string(),
    }
}

fn normalize_language(language: &str) -> String {
    language
        .trim()
        .trim_start_matches('.')
        .to_ascii_lowercase()
        .replace('_', "-")
}

pub(crate) fn language_extension(language: &str) -> &'static str {
    // Keep argument placeholders and alias matching aligned with Panache's
    // private external_formatters_common helpers.
    match normalize_language(language).as_str() {
        "javascript" | "js" | "ojs" => "js",
        "typescript" | "ts" => "ts",
        "jsx" => "jsx",
        "tsx" => "tsx",
        "json" => "json",
        "jsonc" => "jsonc",
        "yaml" | "yml" => "yaml",
        "markdown" | "md" | "qmd" | "rmd" => "md",
        "css" => "css",
        "scss" => "scss",
        "less" => "less",
        "html" => "html",
        "vue" => "vue",
        "svelte" => "svelte",
        "graphql" | "gql" => "graphql",
        "r" => "r",
        "python" | "py" => "py",
        "rust" | "rs" => "rs",
        "go" => "go",
        "bash" | "sh" | "zsh" => "sh",
        "c" => "c",
        "cpp" | "c++" | "cxx" => "cpp",
        "csharp" | "c-sharp" | "cs" => "cs",
        "java" => "java",
        "kotlin" | "kt" => "kt",
        "ruby" | "rb" => "rb",
        "swift" => "swift",
        "php" => "php",
        "lua" => "lua",
        "perl" | "pl" => "pl",
        "elixir" | "ex" => "exs",
        "haskell" | "hs" => "hs",
        "scala" => "scala",
        "julia" | "jl" => "jl",
        "ocaml" | "ml" => "ml",
        "clojure" | "clj" => "clj",
        "dart" => "dart",
        "zig" => "zig",
        "nix" => "nix",
        "toml" => "toml",
        "xml" => "xml",
        "sql" => "sql",
        "tex" | "latex" => "tex",
        "bibtex" | "bib" => "bib",
        "dockerfile" => "dockerfile",
        "makefile" => "makefile",
        _ => "txt",
    }
}

fn declares_r_formatter(table: &toml::Table) -> bool {
    table
        .get("formatters")
        .and_then(toml::Value::as_table)
        .is_some_and(|formatters| {
            formatters
                .iter()
                .any(|(language, value)| language.eq_ignore_ascii_case("r") && !value.is_table())
        })
}
