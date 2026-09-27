use extendr_api::prelude::*;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub fn load_config(
    config_path: Option<&str>,
    document_path: Option<&str>,
    flavor: Option<panache_engine::config::Flavor>,
    isolated: bool,
    overrides: toml::Table,
) -> std::result::Result<(panache_engine::config::Config, toml::Table), String> {
    use panache_engine::config;
    let document = document_path.map(Path::new);
    let start_dir = document.and_then(Path::parent).unwrap_or(Path::new("."));
    let (base, source, chain) = if isolated {
        (
            config::Config::default(),
            config::ConfigSource::None,
            vec![],
        )
    } else {
        config::load_with_chain(config_path.map(Path::new), start_dir, document, flavor)
            .map_err(|error| error.to_string())?
    };

    // The host loader keeps raw tables private. Retain declarations from its
    // validated chain so overrides can reuse formatter definitions and empty
    // chains before the host resolves presets and flavor-dependent defaults.
    let mut table = toml::Table::new();
    for path in chain.iter().rev() {
        let source = std::fs::read_to_string(path).map_err(|error| error.to_string())?;
        let inherited = toml::from_str(&source).map_err(|error| error.to_string())?;
        merge_tables(&mut table, inherited, true);
    }
    let extension_overrides = overrides.get("extensions").cloned();
    if let Some(extensions) = &extension_overrides {
        extension_flags(extensions, base.flavor)?;
    }
    let detect_flavor = isolated
        || overrides
            .get("flavors")
            .is_some_and(|value| value.as_table().is_some_and(|table| !table.is_empty()));
    merge_tables(&mut table, overrides, true);
    let mut config = deserialize_config(&table)?;
    let resolved_flavor = flavor.unwrap_or_else(|| {
        if !detect_flavor {
            return base.flavor;
        }
        document
            .and_then(|path| detect_overridden_flavor(path, &source, &config))
            .unwrap_or(config.flavor)
    });
    table.insert(
        "flavor".into(),
        toml::Value::try_from(resolved_flavor).map_err(|error| error.to_string())?,
    );
    config = deserialize_config(&table)?;
    if let Some(extensions) = extension_overrides {
        // Invocation flags override even a more specific extension setting in
        // a file, matching the CLI's final application of `--option` flags.
        let flags = extension_flags(&extensions, resolved_flavor)?;
        config.extensions.apply_overrides(flags.clone());
        config.formatter_extensions.apply_overrides(flags);
    }
    validate_formatters(&table, &config)?;
    Ok((config, table))
}

fn detect_overridden_flavor(
    document: &Path,
    source: &panache_engine::config::ConfigSource,
    config: &panache_engine::config::Config,
) -> Option<panache_engine::config::Flavor> {
    use panache_engine::config::{Config, detect_flavor_from_path};
    let absolute = std::path::absolute(document).ok()?;
    let anchor = source.project_anchor().and_then(|path| {
        if path.as_os_str().is_empty() {
            std::path::absolute(".").ok()
        } else {
            std::path::absolute(path).ok()
        }
    });
    // Symlinked paths can differ from the working directory's spelling. Resolve
    // both sides for a relative candidate while retaining original absolute paths.
    let canonical_relative = anchor.as_ref().and_then(|anchor| {
        let document = canonicalize_for_matching(&absolute)?;
        let anchor = anchor.canonicalize().ok()?;
        document.strip_prefix(anchor).ok().map(Path::to_path_buf)
    });
    let candidates: Vec<_> = [
        Some(document),
        Some(absolute.as_path()),
        anchor
            .as_ref()
            .and_then(|anchor| absolute.strip_prefix(anchor).ok()),
        canonical_relative.as_deref(),
        document.file_name().map(Path::new),
    ]
    .into_iter()
    .flatten()
    .map(|path| path.to_string_lossy().replace('\\', "/"))
    .collect();

    // The public detector lacks the config anchor. Match the host's relative,
    // absolute, and basename candidates and specificity before delegating its
    // special filename/extension rules (for example, .qmd still means Quarto).
    let mut best = None;
    for (pattern, flavor) in &config.flavor_overrides {
        let Ok(glob) = globset::GlobBuilder::new(pattern)
            .literal_separator(true)
            .backslash_escape(true)
            .build()
        else {
            continue;
        };
        let matcher = glob.compile_matcher();
        if !candidates.iter().any(|path| matcher.is_match(path)) {
            continue;
        }
        let wildcards = pattern
            .chars()
            .filter(|c| matches!(c, '*' | '?' | '[' | ']' | '{' | '}'))
            .count();
        let score = (
            pattern.chars().count() - wildcards,
            usize::MAX - wildcards,
            pattern.matches('/').count(),
        );
        if best.is_none_or(|(previous, _)| score > previous) {
            best = Some((score, *flavor));
        }
    }
    let detection = Config {
        flavor: best.map_or(config.flavor, |(_, flavor)| flavor),
        ..Config::default()
    };
    detect_flavor_from_path(document, &detection)
}

fn canonicalize_for_matching(path: &Path) -> Option<PathBuf> {
    // Unsaved documents and their parent directories may not exist yet.
    path.ancestors().find_map(|ancestor| {
        let canonical = ancestor.canonicalize().ok()?;
        Some(canonical.join(path.strip_prefix(ancestor).ok()?))
    })
}

fn deserialize_config(
    table: &toml::Table,
) -> std::result::Result<panache_engine::config::Config, String> {
    toml::Value::Table(table.clone())
        .try_into()
        .map_err(|error| format!("invalid configuration: {error}"))
}

fn extension_flags(
    value: &toml::Value,
    flavor: panache_engine::config::Flavor,
) -> std::result::Result<HashMap<String, bool>, String> {
    use panache_engine::config::{Extensions, Flavor, FormatterExtensions};
    fn flag(name: &str, value: &toml::Value) -> std::result::Result<bool, String> {
        if !Extensions::is_known_name(name) && !FormatterExtensions::is_known_name(name) {
            return Err(format!("unknown extension `{name}`"));
        }
        value
            .as_bool()
            .ok_or_else(|| format!("extension `{name}` must be TRUE or FALSE"))
    }
    let table = value
        .as_table()
        .ok_or("`extensions` must be a named list")?;
    let mut flags = HashMap::new();
    let mut specific = HashMap::new();
    for (name, value) in table {
        if let Some(nested) = value.as_table() {
            let selected: Flavor = toml::Value::String(name.clone())
                .try_into()
                .map_err(|_| format!("unknown extension flavor `{name}`"))?;
            for (key, value) in nested {
                let enabled = flag(key, value)?;
                if selected == flavor {
                    specific.insert(key.clone(), enabled);
                }
            }
        } else {
            flags.insert(name.clone(), flag(name, value)?);
        }
    }
    flags.extend(specific);
    Ok(flags)
}

fn validate_formatters(
    table: &toml::Table,
    config: &panache_engine::config::Config,
) -> std::result::Result<(), String> {
    if let Some(formatters) = table.get("formatters").and_then(toml::Value::as_table) {
        for (name, value) in formatters {
            if value.is_table() {
                value
                    .clone()
                    .try_into::<panache_engine::config::FormatterDefinition>()
                    .map_err(|error| format!("invalid formatter `{name}`: {error}"))?;
            } else if (value.is_str() || value.as_array().is_some_and(|items| !items.is_empty()))
                && !config.formatters.contains_key(name)
            {
                return Err(format!("could not resolve formatters for `{name}`"));
            }
        }
    }
    Ok(())
}

// Keep inheritance aligned with the host loader's private merge: tables merge,
// ordinary arrays replace, extend-* arrays accumulate, and flavors merge by
// path pattern rather than by flavor name.
fn merge_tables(base: &mut toml::Table, overrides: toml::Table, root: bool) {
    for (key, value) in overrides {
        match (base.get_mut(&key), value) {
            (Some(toml::Value::Table(base)), toml::Value::Table(overrides)) => {
                if root && key == "flavors" {
                    merge_flavors(base, overrides);
                } else {
                    merge_tables(base, overrides, false);
                }
            }
            (Some(toml::Value::Array(base)), toml::Value::Array(overrides))
                if root && matches!(key.as_str(), "extend-include" | "extend-exclude") =>
            {
                base.extend(overrides);
            }
            (_, value) => {
                base.insert(key, value);
            }
        }
    }
}

fn merge_flavors(base: &mut toml::Table, overrides: toml::Table) {
    let reassigned: std::collections::HashSet<_> = overrides
        .values()
        .filter_map(toml::Value::as_array)
        .flatten()
        .filter_map(toml::Value::as_str)
        .collect();
    for patterns in base
        .iter_mut()
        .filter_map(|(_, value)| value.as_array_mut())
    {
        patterns.retain(|pattern| pattern.as_str().is_none_or(|p| !reassigned.contains(p)));
    }
    for (key, value) in overrides {
        match (base.get_mut(&key), value) {
            (Some(toml::Value::Array(base)), toml::Value::Array(overrides)) => {
                base.extend(overrides)
            }
            (_, value) => {
                base.insert(key, value);
            }
        }
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overrides_preserve_siblings_and_replace_arrays_including_empty_chains() {
        let mut base: toml::Table = toml::from_str(
            "[format]\nline-width = 20\nwrap = 'sentence'\n\
             [formatters]\nr = ['first', 'second']\npython = 'first'\n\
             [formatters.first]\ncmd = 'tool'\nargs = ['old']",
        )
        .unwrap();
        let overrides = toml::from_str(
            "[format]\nline-width = 100\n[formatters]\nr = []\n\
             [formatters.first]\nargs = ['new']",
        )
        .unwrap();
        merge_tables(&mut base, overrides, true);
        assert_eq!(base["format"]["line-width"].as_integer(), Some(100));
        assert_eq!(base["format"]["wrap"].as_str(), Some("sentence"));
        assert!(base["formatters"]["r"].as_array().unwrap().is_empty());
        assert_eq!(base["formatters"]["python"].as_str(), Some("first"));
        assert_eq!(base["formatters"]["first"]["cmd"].as_str(), Some("tool"));
        assert_eq!(base["formatters"]["first"]["args"][0].as_str(), Some("new"));
    }

    #[test]
    fn flavor_patterns_accumulate_and_can_be_reassigned() {
        let mut base = toml::from_str("[flavors]\ngfm = ['docs/*.md', 'README.md']").unwrap();
        let overrides =
            toml::from_str("[flavors]\ncommonmark = ['README.md']\ngfm = ['notes/*.md']").unwrap();
        merge_tables(&mut base, overrides, true);
        let config = deserialize_config(&base).unwrap();
        assert_eq!(
            config.flavor_overrides["README.md"],
            panache_engine::config::Flavor::CommonMark
        );
        assert_eq!(
            config.flavor_overrides["docs/*.md"],
            panache_engine::config::Flavor::Gfm
        );
        assert_eq!(
            config.flavor_overrides["notes/*.md"],
            panache_engine::config::Flavor::Gfm
        );
    }

    #[test]
    fn isolated_overrides_resolve_flavor_and_validate_extensions() {
        let overrides =
            toml::from_str("[format]\nline-width = 42\n[extensions]\nsmart = false").unwrap();
        let (config, _) = load_config(
            Some("missing.toml"),
            Some("document.qmd"),
            None,
            true,
            overrides,
        )
        .unwrap();
        assert_eq!(config.flavor, panache_engine::config::Flavor::Quarto);
        assert_eq!(config.line_width, 42);
        assert!(!config.formatter_extensions.smart);
        for source in [
            "[extensions]\ntypo = true",
            "[extensions]\nsmart = 'false'",
            "[extensions.quarto]\ntypo = true",
        ] {
            assert!(load_config(None, None, None, true, toml::from_str(source).unwrap()).is_err());
        }
    }
}
