use std::path::PathBuf;

use goose_core::{
    debug_ws_server::{DebugWsServerOptions, serve_debug_ws_once},
    report::write_json_report,
    tool_args::{args, default_path, path_value, value},
};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(2);
    }
}

fn run() -> goose_core::GooseResult<()> {
    let args = args();
    let database_path = default_path(&args, "--db", "goose.sqlite")?;
    let session_id = value(&args, "--session-id")?
        .ok_or_else(|| goose_core::GooseError::message("--session-id is required"))?;
    let token = value(&args, "--token")?
        .ok_or_else(|| goose_core::GooseError::message("--token is required"))?;
    let bind_host = value(&args, "--bind-host")?.unwrap_or_else(|| "127.0.0.1".to_string());
    let port = parse_u16(
        value(&args, "--port")?.as_deref().unwrap_or("49152"),
        "--port",
    )?;
    let poll_interval_ms = parse_u64(
        value(&args, "--poll-interval-ms")?
            .as_deref()
            .unwrap_or("100"),
        "--poll-interval-ms",
    )?;
    let idle_timeout_ms = parse_u64(
        value(&args, "--idle-timeout-ms")?
            .as_deref()
            .unwrap_or("30000"),
        "--idle-timeout-ms",
    )?;
    let max_events = value(&args, "--max-events")?
        .as_deref()
        .map(|value| parse_usize(value, "--max-events"))
        .transpose()?;
    let output: Option<PathBuf> = path_value(&args, "--output")?;

    let report = serve_debug_ws_once(DebugWsServerOptions {
        database_path,
        session_id,
        bind_host,
        port,
        token,
        poll_interval_ms,
        idle_timeout_ms,
        max_events,
    })?;
    write_json_report(&report, output.as_deref())?;
    if report.pass {
        Ok(())
    } else {
        std::process::exit(1);
    }
}

fn parse_u16(value: &str, name: &str) -> goose_core::GooseResult<u16> {
    value
        .parse::<u16>()
        .map_err(|error| goose_core::GooseError::message(format!("{name} must be a u16: {error}")))
}

fn parse_u64(value: &str, name: &str) -> goose_core::GooseResult<u64> {
    value
        .parse::<u64>()
        .map_err(|error| goose_core::GooseError::message(format!("{name} must be a u64: {error}")))
}

fn parse_usize(value: &str, name: &str) -> goose_core::GooseResult<usize> {
    value.parse::<usize>().map_err(|error| {
        goose_core::GooseError::message(format!("{name} must be a usize: {error}"))
    })
}
