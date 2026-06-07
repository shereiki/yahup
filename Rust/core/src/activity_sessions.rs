use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const ACTIVITY_SESSION_CORRECTION_SCOPE: &str = "activity_session_correction";
pub const ACTIVITY_SESSION_CORRECTION_HISTORY_KEY: &str = "correction_history";
pub const ACTIVITY_SESSION_MANUALLY_CORRECTED_KEY: &str = "manually_corrected";

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "snake_case")]
pub enum ActivitySessionCorrectionKind {
    ChangeActivityType,
    TrimStart,
    TrimEnd,
    Split,
    Merge,
    FalsePositive,
}

impl ActivitySessionCorrectionKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ChangeActivityType => "change_activity_type",
            Self::TrimStart => "trim_start",
            Self::TrimEnd => "trim_end",
            Self::Split => "split",
            Self::Merge => "merge",
            Self::FalsePositive => "false_positive",
        }
    }

    pub const fn label(self) -> &'static str {
        match self {
            Self::ChangeActivityType => "Change activity type",
            Self::TrimStart => "Trim start",
            Self::TrimEnd => "Trim end",
            Self::Split => "Split",
            Self::Merge => "Merge",
            Self::FalsePositive => "Mark false positive",
        }
    }

    pub const fn action(self) -> &'static str {
        match self {
            Self::ChangeActivityType => "Retag the session before storing it.",
            Self::TrimStart => "Move the opening edge of the activity window.",
            Self::TrimEnd => "Move the closing edge of the activity window.",
            Self::Split => "Separate a mixed session into adjacent corrected sessions.",
            Self::Merge => "Combine adjacent sessions into one corrected session.",
            Self::FalsePositive => "Discard the session before it is stored.",
        }
    }

    pub const fn detection_method(self) -> &'static str {
        match self {
            Self::Split => "manual_split",
            Self::Merge => "manual_merge",
            _ => "manual_annotation",
        }
    }

    pub const fn sync_status(self) -> &'static str {
        match self {
            Self::FalsePositive => "discarded",
            _ => "user_confirmed",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ActivitySessionCorrectionPlan {
    pub kind: ActivitySessionCorrectionKind,
    pub label: String,
    pub action: String,
    pub detection_method: String,
    pub sync_status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ActivitySessionCorrectionHistoryEntry {
    pub kind: ActivitySessionCorrectionKind,
    pub label: String,
    pub details: Value,
}

pub fn activity_session_correction_plans() -> Vec<ActivitySessionCorrectionPlan> {
    [
        ActivitySessionCorrectionKind::ChangeActivityType,
        ActivitySessionCorrectionKind::TrimStart,
        ActivitySessionCorrectionKind::TrimEnd,
        ActivitySessionCorrectionKind::Split,
        ActivitySessionCorrectionKind::Merge,
        ActivitySessionCorrectionKind::FalsePositive,
    ]
    .into_iter()
    .map(activity_session_correction_plan)
    .collect()
}

pub fn activity_session_correction_plan(
    kind: ActivitySessionCorrectionKind,
) -> ActivitySessionCorrectionPlan {
    ActivitySessionCorrectionPlan {
        kind,
        label: kind.label().to_string(),
        action: kind.action().to_string(),
        detection_method: kind.detection_method().to_string(),
        sync_status: kind.sync_status().to_string(),
    }
}

pub fn append_activity_session_correction_history(
    provenance: &Value,
    kind: ActivitySessionCorrectionKind,
    details: Value,
) -> Value {
    let mut object = provenance.as_object().cloned().unwrap_or_default();

    object.insert(
        ACTIVITY_SESSION_MANUALLY_CORRECTED_KEY.to_string(),
        Value::Bool(true),
    );
    object.insert(
        "correction_kind".to_string(),
        Value::String(kind.as_str().to_string()),
    );
    object.insert("correction_details".to_string(), details.clone());

    let history_entry = json!(ActivitySessionCorrectionHistoryEntry {
        kind,
        label: kind.label().to_string(),
        details,
    });
    let mut history = match object.remove(ACTIVITY_SESSION_CORRECTION_HISTORY_KEY) {
        Some(Value::Array(entries)) => entries,
        Some(other) => vec![other],
        None => Vec::new(),
    };
    history.push(history_entry);
    object.insert(
        ACTIVITY_SESSION_CORRECTION_HISTORY_KEY.to_string(),
        Value::Array(history),
    );

    Value::Object(object)
}
