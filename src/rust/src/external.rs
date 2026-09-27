use std::path::Path;
use std::time::Duration;

use extendr_api::prelude::*;
use panache_engine::config;
use panache_formatter::{ExternalCodeBlock, FormattedCodeMap};

pub struct ExternalFormatters {
    config: config::Config,
    pub use_builtin_r: bool,
}

impl ExternalFormatters {
    pub fn load(
        input: &Robj,
        document_path: Option<&str>,
        flavor: Option<config::Flavor>,
    ) -> std::result::Result<Self, String> {
        let document = document_path.map(Path::new);
        if (!input.is_null() && input.is_list()) || input.as_bool() == Some(false) {
            let mut table = if input.is_list() {
                crate::config::list_to_table(&input.as_list().unwrap())?
            } else {
                toml::Table::new()
            };
            if let Some(flavor) = flavor {
                table.insert(
                    "flavor".into(),
                    toml::Value::try_from(flavor).map_err(|e| e.to_string())?,
                );
            }
            let mut config: config::Config = toml::Value::Table(table.clone())
                .try_into()
                .map_err(|e: toml::de::Error| format!("invalid config: {e}"))?;
            if !table.contains_key("flavor")
                && let Some(flavor) =
                    document.and_then(|path| config::detect_flavor_from_path(path, &config))
            {
                table.insert(
                    "flavor".into(),
                    toml::Value::try_from(flavor).map_err(|e| e.to_string())?,
                );
                config = toml::Value::Table(table.clone())
                    .try_into()
                    .map_err(|e: toml::de::Error| e.to_string())?;
            }
            if let Some(formatters) = table.get("formatters").and_then(toml::Value::as_table) {
                for (language, value) in formatters {
                    if (value.is_str() || value.as_array().is_some_and(|items| !items.is_empty()))
                        && !config.formatters.contains_key(language)
                    {
                        return Err(format!(
                            "invalid config: could not resolve formatters for `{language}`"
                        ));
                    }
                }
            }
            return Ok(Self {
                config,
                use_builtin_r: !declares_r_formatter(&table),
            });
        }
        let start_dir = document.and_then(Path::parent).unwrap_or(Path::new("."));
        let (config, _, chain) =
            config::load_with_chain(input.as_str().map(Path::new), start_dir, document, flavor)
                .map_err(|error| error.to_string())?;

        // Panache drops empty chains when resolving its configuration. Read the
        // declarations too, so `r = []` can disable our additional R default.
        let mut use_builtin_r = true;
        for path in chain {
            let source = std::fs::read_to_string(&path).map_err(|error| error.to_string())?;
            let table: toml::Table = toml::from_str(&source).map_err(|error| error.to_string())?;
            if declares_r_formatter(&table) {
                use_builtin_r = false;
                break;
            }
        }
        Ok(Self {
            config,
            use_builtin_r,
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
        panache_engine::external_formatters_sync::run_formatters_parallel(
            blocks,
            &self.config.formatters,
            Duration::from_secs(30),
            self.config.external_max_parallel,
        )
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
