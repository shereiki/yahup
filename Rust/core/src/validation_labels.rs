use serde_json::Value;

pub const OFFICIAL_WHOOP_LABEL_POLICY: &str =
    "official_whoop_values_are_validation_labels_not_inputs";

pub const OFFICIAL_LABEL_PROVENANCE_MISSING_ISSUE: &str = "official_label_provenance_missing";
pub const OFFICIAL_LABEL_POLICY_NOT_MARKED_ISSUE: &str = "official_label_policy_not_marked";

pub fn official_label_policy_issues(
    has_official_label: bool,
    label_provenance: Option<&Value>,
) -> Vec<String> {
    if !has_official_label {
        return Vec::new();
    }

    let Some(Value::Object(object)) = label_provenance else {
        return vec![OFFICIAL_LABEL_PROVENANCE_MISSING_ISSUE.to_string()];
    };
    if object.is_empty() {
        return vec![OFFICIAL_LABEL_PROVENANCE_MISSING_ISSUE.to_string()];
    }
    if object
        .get("official_labels_are_labels")
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        Vec::new()
    } else {
        vec![OFFICIAL_LABEL_POLICY_NOT_MARKED_ISSUE.to_string()]
    }
}

pub fn official_label_policy_issue_action(issue: &str) -> Option<&'static str> {
    match issue {
        OFFICIAL_LABEL_PROVENANCE_MISSING_ISSUE => Some(
            "Add non-empty label_provenance for the official WHOOP label and mark official_labels_are_labels=true.",
        ),
        OFFICIAL_LABEL_POLICY_NOT_MARKED_ISSUE => Some(
            "Set label_provenance.official_labels_are_labels=true so official WHOOP values remain validation labels, not metric inputs.",
        ),
        _ => None,
    }
}
