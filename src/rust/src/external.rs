use std::time::Duration;

use panache_engine::config;
use panache_formatter::{ExternalCodeBlock, FormattedCodeMap};

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
