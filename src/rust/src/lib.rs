use extendr_api::prelude::*;
use panache_formatter::config::{Flavor, FormatterExtensions};
use panache_formatter::{Config, WrapMode};

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

fn parse_wrap(value: &str) -> extendr_api::Result<WrapMode> {
    match value {
        "preserve" => Ok(WrapMode::Preserve),
        "reflow" => Ok(WrapMode::Reflow),
        "sentence" => Ok(WrapMode::Sentence),
        "semantic" => Ok(WrapMode::Semantic),
        other => Err(format!("unknown wrapping strategy `{other}`").into()),
    }
}

#[extendr]
fn rust_format_document(
    text: &str,
    flavor: &str,
    line_width: i32,
    wrap: &str,
    start_line: Nullable<i32>,
    end_line: Nullable<i32>,
) -> extendr_api::Result<String> {
    let flavor = parse_flavor(flavor)?;
    let mut config = Config::default();
    config.flavor = flavor;
    config.parser_extensions = panache_formatter::config::ParserExtensions::for_flavor(flavor);
    config.formatter_extensions = FormatterExtensions::for_flavor(flavor);
    config.line_width = usize::try_from(line_width)
        .map_err(|_| extendr_api::Error::from("line width must be positive"))?;
    config.wrap = Some(parse_wrap(wrap)?);

    let line_range = match (start_line, end_line) {
        (Nullable::NotNull(start), Nullable::NotNull(end)) => {
            let start = usize::try_from(start)
                .map_err(|_| extendr_api::Error::from("range start must be positive"))?;
            let end = usize::try_from(end)
                .map_err(|_| extendr_api::Error::from("range end must be positive"))?;
            Some((start, end))
        }
        (Nullable::Null, Nullable::Null) => None,
        _ => return Err("range start and end must both be present or absent".into()),
    };

    let Some((start_line, end_line)) = line_range else {
        return Ok(panache_formatter::format(text, Some(config), None));
    };

    let tree = panache_parser::parse(text, Some(config.parser_options()));
    let (start_byte, end_byte) =
        panache_parser::range_utils::expand_line_range_to_blocks(&tree, text, start_line, end_line)
            .ok_or_else(|| extendr_api::Error::from("range lies outside the document"))?;
    let replacement = panache_formatter::format(text, Some(config), Some((start_byte, end_byte)));

    let mut output =
        String::with_capacity(text.len() - (end_byte - start_byte) + replacement.len());
    output.push_str(&text[..start_byte]);
    output.push_str(&replacement);
    output.push_str(&text[end_byte..]);
    Ok(output)
}

#[cfg(test)]
mod tests {
    use panache_formatter::{Config, WrapMode};

    #[test]
    fn formatter_range_replacement_preserves_unselected_blocks() {
        let text = "first first first first first\n\nsecond second second second second\n";
        let mut config = Config::default();
        config.line_width = 20;
        config.wrap = Some(WrapMode::Reflow);
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
    "0.22.0"
}

extendr_module! {
    mod panache;
    fn rust_format_document;
    fn rust_engine_version;
}
