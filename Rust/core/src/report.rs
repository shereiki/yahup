use std::{fs, path::Path};

use serde::Serialize;

use crate::{GooseError, GooseResult};

pub fn write_json_report<T: Serialize>(report: &T, output: Option<&Path>) -> GooseResult<()> {
    let json = serde_json::to_string_pretty(report)
        .map_err(|source| GooseError::message(format!("cannot serialize report: {source}")))?;

    if let Some(path) = output {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|source| GooseError::io(parent, source))?;
        }
        fs::write(path, json.as_bytes()).map_err(|source| GooseError::io(path, source))?;
    }

    println!("{json}");
    Ok(())
}
