use std::fs::{self, File};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::time::{Duration, Instant};

use panache_engine::config::FormatterConfig;
use panache_engine::external_formatters_sync::FormatterError;

pub fn format_code(
    code: &str,
    language: &str,
    config: &FormatterConfig,
    timeout: Duration,
) -> Result<String, FormatterError> {
    let dir = tempfile::Builder::new().prefix("panache-").tempdir()?;
    let extension = crate::external::language_extension(language);
    let filename = format!("stdin.{extension}");
    let input = dir.path().join(&filename);
    let stdout = dir.path().join("stdout");
    let stderr = dir.path().join("stderr");
    fs::write(&input, code)?;

    let placeholder = if config.stdin {
        filename
    } else {
        input.to_string_lossy().into_owned()
    };
    let mut args: Vec<_> = config
        .args
        .iter()
        .map(|arg| {
            arg.replace("{lang}", language)
                .replace("{ext}", extension)
                .replace("{}", &placeholder)
        })
        .collect();
    if !config.stdin && !config.args.iter().any(|arg| arg.contains("{}")) {
        args.push(placeholder);
    }

    // File-backed streams cannot deadlock when a formatter writes output before
    // reading its input, and leave no pipe-handling threads behind on timeout.
    let mut command = Command::new(&config.cmd);
    command
        .args(args)
        .stdin(if config.stdin {
            Stdio::from(File::open(&input)?)
        } else {
            Stdio::null()
        })
        .stdout(File::create(&stdout)?)
        .stderr(File::create(&stderr)?);
    let mut child = RunningChild(
        command
            .spawn()
            .map_err(|error| FormatterError::SpawnFailed(format!("{}: {error}", config.cmd)))?,
    );
    let status = child.wait(timeout)?;
    if !status.success() {
        return Err(FormatterError::NonZeroExit {
            code: status.code().unwrap_or(-1),
            stderr: String::from_utf8_lossy(&fs::read(stderr)?).into_owned(),
        });
    }
    if config.stdin {
        Ok(String::from_utf8_lossy(&fs::read(stdout)?).into_owned())
    } else {
        Ok(fs::read_to_string(input)?)
    }
}

struct RunningChild(Child);

impl RunningChild {
    fn wait(&mut self, timeout: Duration) -> Result<ExitStatus, FormatterError> {
        let started = Instant::now();
        loop {
            if let Some(status) = self.0.try_wait()? {
                return Ok(status);
            }
            let remaining = timeout.saturating_sub(started.elapsed());
            if remaining.is_zero() {
                return Err(FormatterError::Timeout);
            }
            std::thread::sleep(remaining.min(Duration::from_millis(10)));
        }
    }
}

impl Drop for RunningChild {
    fn drop(&mut self) {
        // Keep ownership until the child is reaped on every path, including
        // timeouts and I/O errors, before its temporary files are removed.
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    use std::time::Instant;

    fn r_formatter(script: &str, paths: &[&Path], stdin: bool) -> FormatterConfig {
        let mut args = vec!["--vanilla".into(), "-e".into(), script.into()];
        args.extend(paths.iter().map(|path| path.to_string_lossy().into_owned()));
        FormatterConfig {
            cmd: "Rscript".into(),
            args,
            stdin,
        }
    }

    #[test]
    fn timeouts_terminate_stdin_and_file_formatters() {
        for stdin in [true, false] {
            let dir = tempfile::tempdir().unwrap();
            let started = dir.path().join("started");
            let finished = dir.path().join("finished");
            let config = r_formatter(
                "args <- commandArgs(TRUE); \
                 writeLines(if (length(args) > 2) args[[3]] else 'started', args[[1]]); \
                 Sys.sleep(2); writeLines('finished', args[[2]])",
                &[&started, &finished],
                stdin,
            );
            let result = format_code("x=1\n", "r", &config, Duration::from_secs(1));
            // The child would leave this marker if it survived the timeout.
            std::thread::sleep(Duration::from_millis(2500));
            assert!(started.exists(), "the test formatter never started");
            assert!(matches!(result, Err(FormatterError::Timeout)));
            assert!(!finished.exists(), "the timed-out formatter kept running");
            if !stdin {
                let input = fs::read_to_string(&started).unwrap();
                assert!(
                    !Path::new(input.trim()).exists(),
                    "temporary input was left behind"
                );
            }
        }
    }

    #[test]
    fn timeout_includes_a_formatter_that_does_not_read_stdin() {
        let config = r_formatter("Sys.sleep(2); readLines(file('stdin'))", &[], true);
        let start = Instant::now();
        let result = format_code(
            &"x\n".repeat(1_000_000),
            "r",
            &config,
            Duration::from_millis(500),
        );
        assert!(matches!(result, Err(FormatterError::Timeout)));
        assert!(start.elapsed() < Duration::from_millis(1500));
    }

    #[test]
    fn stdin_and_output_larger_than_pipe_buffers_do_not_deadlock() {
        let code = "x\n".repeat(100_000);
        let config = r_formatter(
            "cat(strrep('y', 100000)); cat(paste(readLines(file('stdin')), collapse = '\\n'))",
            &[],
            true,
        );
        let result = format_code(&code, "r", &config, Duration::from_secs(5)).unwrap();
        assert_eq!(
            result,
            format!("{}{}", "y".repeat(100_000), code.trim_end())
        );
    }
}
