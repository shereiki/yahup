use goose_core::{
    capture_import::{CaptureSqliteImportOptions, ensure_database_parent, import_capture_sqlite},
    report::write_json_report,
    store::GooseStore,
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
    let source = path_value(&args, "--capture-sqlite")?
        .ok_or_else(|| goose_core::GooseError::message("missing required --capture-sqlite path"))?;
    let db = default_path(&args, "--db", "goose.sqlite")?;
    let output = path_value(&args, "--output")?;
    let session_id = value(&args, "--session-id")?
        .ok_or_else(|| goose_core::GooseError::message("missing required --session-id value"))?;
    let device_model =
        value(&args, "--device-model")?.unwrap_or_else(|| "WHOOP 5.0 Goose".to_string());
    let sensitivity =
        value(&args, "--sensitivity")?.unwrap_or_else(|| "user-owned-capture".to_string());
    let parser_version = value(&args, "--parser-version")?.unwrap_or_else(|| {
        format!(
            "goose-core/{}",
            option_env!("CARGO_PKG_VERSION").unwrap_or("unknown")
        )
    });

    ensure_database_parent(&db)?;
    let store = GooseStore::open(&db)?;
    let report = import_capture_sqlite(
        &store,
        CaptureSqliteImportOptions {
            source_database_path: &source,
            target_database_path: &db,
            session_id: &session_id,
            device_model: &device_model,
            sensitivity: &sensitivity,
            parser_version: &parser_version,
        },
    )?;
    write_json_report(&report, output.as_deref())?;
    if report.pass {
        Ok(())
    } else {
        std::process::exit(1);
    }
}
