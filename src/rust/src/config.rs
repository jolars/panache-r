use extendr_api::prelude::*;
use std::collections::HashMap;

pub fn list_to_table(list: &List) -> std::result::Result<toml::Table, String> {
    list.iter()
        .map(|(name, value)| Ok((name.to_string(), r_to_toml(&value, name)?)))
        .collect()
}

fn r_to_toml(value: &Robj, field: &str) -> std::result::Result<toml::Value, String> {
    use toml::Value;
    if let Some(list) = value.as_list() {
        return if value.names().is_some() || list.is_empty() {
            list_to_table(&list).map(Value::Table)
        } else {
            list.values()
                .map(|item| r_to_toml(&item, ""))
                .collect::<std::result::Result<Vec<_>, _>>()
                .map(Value::Array)
        };
    }
    let mut values: Vec<Value> = if let Some(values) = value.as_str_vector() {
        values
            .into_iter()
            .map(|item| Value::String(item.to_string()))
            .collect()
    } else if let Some(values) = value.as_integer_slice() {
        values
            .iter()
            .map(|item| Value::Integer(i64::from(*item)))
            .collect()
    } else if let Some(values) = value.as_real_slice() {
        values
            .iter()
            .map(|item| {
                if item.fract() == 0.0 && *item >= i64::MIN as f64 && *item < i64::MAX as f64 {
                    Value::Integer(*item as i64)
                } else {
                    Value::Float(*item)
                }
            })
            .collect()
    } else if let Some(values) = value.as_logical_slice() {
        values
            .iter()
            .map(|item| Value::Boolean(item.is_true()))
            .collect()
    } else {
        return Err(format!("unsupported config value for `{field}`"));
    };
    Ok(if values.len() == 1 {
        values.remove(0)
    } else {
        Value::Array(values)
    })
}

// The host crate keeps this conversion private; keep it aligned with its formatter adapter.
pub fn formatter_config(config: &panache_engine::config::Config) -> panache_formatter::Config {
    let line_ending = config.line_ending.as_ref().map(|ending| match ending {
        panache_engine::config::LineEnding::Auto => panache_formatter::LineEnding::Auto,
        panache_engine::config::LineEnding::Lf => panache_formatter::LineEnding::Lf,
        panache_engine::config::LineEnding::Crlf => panache_formatter::LineEnding::Crlf,
    });
    let math_delimiter_style = match config.math_delimiter_style {
        panache_engine::config::MathDelimiterStyle::Preserve => {
            panache_formatter::MathDelimiterStyle::Preserve
        }
        panache_engine::config::MathDelimiterStyle::Dollars => {
            panache_formatter::MathDelimiterStyle::Dollars
        }
        panache_engine::config::MathDelimiterStyle::Backslash => {
            panache_formatter::MathDelimiterStyle::Backslash
        }
    };
    let tab_stops = match config.tab_stops {
        panache_engine::config::TabStopMode::Normalize => panache_formatter::TabStopMode::Normalize,
        panache_engine::config::TabStopMode::Preserve => panache_formatter::TabStopMode::Preserve,
    };
    let wrap = config.wrap.as_ref().map(|wrap| match wrap {
        panache_engine::config::WrapMode::Preserve => panache_formatter::WrapMode::Preserve,
        panache_engine::config::WrapMode::Reflow => panache_formatter::WrapMode::Reflow,
        panache_engine::config::WrapMode::Sentence => panache_formatter::WrapMode::Sentence,
        panache_engine::config::WrapMode::Semantic => panache_formatter::WrapMode::Semantic,
    });
    let blank_lines = match config.blank_lines {
        panache_engine::config::BlankLines::Preserve => panache_formatter::BlankLines::Preserve,
        panache_engine::config::BlankLines::Collapse => panache_formatter::BlankLines::Collapse,
    };
    let horizontal_rule_style = match config.horizontal_rule_style {
        panache_engine::config::HorizontalRuleStyle::LineWidth => {
            panache_formatter::HorizontalRuleStyle::LineWidth
        }
        panache_engine::config::HorizontalRuleStyle::Compact => {
            panache_formatter::HorizontalRuleStyle::Compact
        }
    };
    // Collapse the user-facing flat/per-language shapes into a single
    // language-keyed map; the formatter normalizes the entries at resolution
    // time. Keys are lowercased so they match the resolved language code.
    let no_break_abbreviations = match &config.no_break_abbreviations {
        None => std::collections::BTreeMap::new(),
        Some(panache_engine::config::NoBreakAbbreviations::Flat(list)) => {
            std::collections::BTreeMap::from([("default".to_string(), list.clone())])
        }
        Some(panache_engine::config::NoBreakAbbreviations::PerLanguage(by_lang)) => by_lang
            .iter()
            .map(|(key, list)| (key.to_lowercase(), list.clone()))
            .collect(),
    };
    let formatter_extensions = panache_formatter::config::FormatterExtensions {
        // Keep shared extension behavior aligned with parser-facing extensions.
        auto_identifiers: config.extensions.auto_identifiers,
        blank_before_header: config.extensions.blank_before_header,
        bookdown_references: config.extensions.bookdown_references,
        east_asian_line_breaks: config.extensions.east_asian_line_breaks,
        escaped_line_breaks: config.extensions.escaped_line_breaks,
        gfm_auto_identifiers: config.extensions.gfm_auto_identifiers,
        quarto_crossrefs: config.extensions.quarto_crossrefs,
        // Formatter-only smart toggles are owned separately.
        smart: config.formatter_extensions.smart,
        smart_quotes: config.formatter_extensions.smart_quotes,
    };

    let formatters: HashMap<String, Vec<panache_formatter::config::FormatterConfig>> = config
        .formatters
        .iter()
        .map(|(lang, entries)| {
            let mapped_entries = entries
                .iter()
                .map(|entry| panache_formatter::config::FormatterConfig {
                    cmd: entry.cmd.clone(),
                    args: entry.args.clone(),
                    stdin: entry.stdin,
                })
                .collect();
            (lang.clone(), mapped_entries)
        })
        .collect();

    panache_formatter::Config {
        flavor: config.flavor,
        parser_extensions: config.extensions.clone(),
        formatter_extensions,
        line_ending,
        line_width: config.line_width,
        math_indent: config.math_indent,
        math_signatures: config.math_signatures.clone(),
        // The formatter resolves the effective signature scope per document.
        math_signature_scope: Default::default(),
        math_delimiter_style,
        table_indent: config.table_indent,
        tab_stops,
        tab_width: config.tab_width,
        wrap,
        blank_lines,
        horizontal_rule_style,
        lang: config.lang.clone(),
        no_break_abbreviations,
        formatters,
        external_max_parallel: config.external_max_parallel,
        parser: config.parser,
        math: config.math,
    }
}
