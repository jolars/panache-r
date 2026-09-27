use extendr_api::prelude::*;
use panache_formatter::config::Flavor;
use panache_formatter::directives::{DirectiveTracker, extract_directive_from_node};
use panache_formatter::syntax::{SyntaxKind, SyntaxNode};
use panache_formatter::{Config, FormattedCodeMap};

mod config;
mod external;

fn parse_flavor(value: &str) -> extendr_api::Result<Flavor> {
    match value {
        "pandoc" => Ok(Flavor::Pandoc),
        "quarto" => Ok(Flavor::Quarto),
        "rmarkdown" => Ok(Flavor::RMarkdown),
        "gfm" => Ok(Flavor::Gfm),
        "commonmark" => Ok(Flavor::CommonMark),
        "multimarkdown" => Ok(Flavor::MultiMarkdown),
        "mdsvex" => Ok(Flavor::Mdsvex),
        "myst" => Ok(Flavor::Myst),
        other => Err(format!("unknown Markdown flavor `{other}`").into()),
    }
}

#[extendr]
#[allow(clippy::too_many_arguments)]
fn rust_format_document(
    text: &str,
    flavor: Nullable<String>,
    start_line: Nullable<i32>,
    end_line: Nullable<i32>,
    r_formatter: Nullable<Function>,
    config_path: Nullable<String>,
    document_path: Nullable<String>,
    isolated: bool,
    overrides: List,
) -> extendr_api::Result<String> {
    let flavor = flavor
        .into_option()
        .map(|flavor| parse_flavor(&flavor))
        .transpose()?;
    let external = external::ExternalFormatters::load(
        config_path.into_option().as_deref(),
        document_path.into_option().as_deref(),
        flavor,
        isolated,
        crate::config::list_to_table(&overrides).map_err(extendr_api::Error::from)?,
    )
    .map_err(extendr_api::Error::from)?;
    let config = external.formatter_config();
    if config.line_width == 0 {
        return Err("line width must be positive".into());
    }

    let line_range = match (start_line, end_line) {
        (Nullable::NotNull(start), Nullable::NotNull(end)) => {
            let start = usize::try_from(start)
                .map_err(|_| extendr_api::Error::from("range start must be positive"))?;
            let end = usize::try_from(end)
                .map_err(|_| extendr_api::Error::from("range end must be positive"))?;
            if start == 0 || end == 0 || start > end {
                return Err("range must contain positive, increasing line numbers".into());
            }
            Some((start, end))
        }
        (Nullable::Null, Nullable::Null) => None,
        _ => return Err("range start and end must both be present or absent".into()),
    };

    let tree = panache_parser::parse(text, Some(external.parser_options()));
    let byte_range = line_range
        .map(|(start, end)| {
            panache_parser::range_utils::expand_line_range_to_blocks(&tree, text, start, end)
                .ok_or_else(|| extendr_api::Error::from("range lies outside the document"))
        })
        .transpose()?;
    let blocks = collect_formattable_blocks(&tree, text, &config, byte_range);
    let mut formatted_code = external.format(blocks.clone());
    if external.use_builtin_r
        && let Nullable::NotNull(formatter) = r_formatter
    {
        formatted_code.extend(format_r_code_blocks(blocks, |code| {
            let result = formatter.call(pairlist!(
                code,
                line_width = config.line_width.min(1000) as i32
            ))?;
            String::try_from(result)
        })?);
    }
    let replacement = panache_formatter::format_tree_with_formatted_code(
        &tree,
        &config,
        byte_range,
        formatted_code,
    );
    // The tree API emits LF; preserve the document's line endings as format() does.
    let replacement = replacement.replace("\r\n", "\n");
    let crlf = match config.line_ending {
        Some(panache_formatter::LineEnding::Crlf) => true,
        Some(panache_formatter::LineEnding::Lf) => false,
        _ => text
            .find('\n')
            .is_some_and(|i| i > 0 && text.as_bytes()[i - 1] == b'\r'),
    };
    let replacement = if crlf {
        replacement.replace('\n', "\r\n")
    } else {
        replacement
    };
    let Some((start_byte, end_byte)) = byte_range else {
        return Ok(replacement);
    };

    let mut output =
        String::with_capacity(text.len() - (end_byte - start_byte) + replacement.len());
    output.push_str(&text[..start_byte]);
    output.push_str(&replacement);
    output.push_str(&text[end_byte..]);
    Ok(output)
}

fn collect_formattable_blocks(
    tree: &SyntaxNode,
    text: &str,
    config: &Config,
    range: Option<(usize, usize)>,
) -> Vec<panache_formatter::ExternalCodeBlock> {
    let mut blocks = Vec::new();
    let mut directives = DirectiveTracker::new();
    for node in tree.descendants() {
        if let Some(directive) = extract_directive_from_node(&node) {
            directives.process_directive(&directive);
        }
        if directives.is_formatting_ignored()
            || !matches!(
                node.kind(),
                SyntaxKind::CODE_BLOCK | SyntaxKind::MYST_DIRECTIVE
            )
        {
            continue;
        }
        let start: usize = node.text_range().start().into();
        let end: usize = node.text_range().end().into();
        if range.is_some_and(|(range_start, range_end)| start >= range_end || end <= range_start) {
            continue;
        }
        if node
            .children()
            .any(|child| child.kind() == SyntaxKind::CODE_FENCE_OPEN)
            && !node
                .children()
                .any(|child| child.kind() == SyntaxKind::CODE_FENCE_CLOSE)
        {
            continue;
        }
        // Collect each block separately so chunk options belong to this occurrence.
        blocks.extend(panache_formatter::collect_code_blocks(&node, text, config));
    }
    blocks
}

fn format_r_code_blocks(
    blocks: Vec<panache_formatter::ExternalCodeBlock>,
    mut format_code: impl FnMut(&str) -> extendr_api::Result<String>,
) -> extendr_api::Result<FormattedCodeMap> {
    let mut formatted = FormattedCodeMap::new();
    for block in blocks {
        if !block.language.eq_ignore_ascii_case("r") || block.formatter_input.trim().is_empty() {
            continue;
        }
        let code = format_code(&block.formatter_input)?;
        let code = match block.hashpipe_prefix {
            Some(prefix) => format!("{prefix}{code}"),
            None => code,
        };
        formatted.insert((block.language, block.original), code);
    }
    Ok(formatted)
}

#[cfg(test)]
mod tests {
    use super::{collect_formattable_blocks, format_r_code_blocks};
    use panache_formatter::config::{Flavor, FormatterExtensions, ParserExtensions};
    use panache_formatter::{Config, WrapMode};

    #[test]
    fn r_formatter_receives_code_without_chunk_options() {
        let text = "```{r}\n#| echo: false\nx<-1\n```\n\n```python\nx=1\n```\n";
        let config = Config {
            flavor: Flavor::Quarto,
            parser_extensions: ParserExtensions::for_flavor(Flavor::Quarto),
            formatter_extensions: FormatterExtensions::for_flavor(Flavor::Quarto),
            ..Config::default()
        };
        let tree = panache_parser::parse(text, Some(config.parser_options()));
        let mut inputs = Vec::new();
        let blocks = collect_formattable_blocks(&tree, text, &config, None);
        let formatted = format_r_code_blocks(blocks, |code| {
            inputs.push(code.to_string());
            Ok("x <- 1\n".to_string())
        })
        .unwrap();

        assert_eq!(inputs, ["x<-1\n"]);
        assert_eq!(formatted.len(), 1);
        assert_eq!(
            formatted[&("r".to_string(), "#| echo: false\nx<-1\n".to_string())],
            "#| echo: false\nx <- 1\n"
        );
    }

    #[test]
    fn r_formatter_skips_ignored_unselected_and_unclosed_chunks() {
        let text = concat!(
            "```r\nunselected<-1\n```\n\n",
            "<!-- panache-ignore-start -->\n\n",
            "```r\nignored<-1\n```\n\n",
            "<!-- panache-ignore-end -->\n\n",
            "```r\nselected<-1\n```\n\n",
            "```r\nunclosed<-1\n"
        );
        let config = Config::default();
        let tree = panache_parser::parse(text, Some(config.parser_options()));
        let mut inputs = Vec::new();
        let range = Some((text.find("<!--").unwrap(), text.len()));
        let blocks = collect_formattable_blocks(&tree, text, &config, range);
        format_r_code_blocks(blocks, |code| {
            inputs.push(code.to_string());
            Ok(code.to_string())
        })
        .unwrap();

        assert_eq!(inputs, ["selected<-1\n"]);
    }

    #[test]
    fn formatter_range_replacement_preserves_unselected_blocks() {
        let text = "first first first first first\n\nsecond second second second second\n";
        let config = Config {
            line_width: 20,
            wrap: Some(WrapMode::Reflow),
            ..Config::default()
        };
        let tree = panache_parser::parse(text, Some(config.parser_options()));
        let (start, end) =
            panache_parser::range_utils::expand_line_range_to_blocks(&tree, text, 3, 3).unwrap();
        let replacement = panache_formatter::format(text, Some(config), Some((start, end)));
        let output = format!("{}{}{}", &text[..start], replacement, &text[end..]);

        assert!(output.starts_with("first first first first first\n\n"));
        assert!(output.contains("second second\n"));
    }
}

#[extendr]
fn rust_engine_version() -> &'static str {
    "0.25.0"
}

extendr_module! {
    mod panache;
    fn rust_format_document;
    fn rust_engine_version;
}
