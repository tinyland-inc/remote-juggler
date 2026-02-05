//! Integration tests for RemoteJuggler GTK GUI
//!
//! These tests verify:
//! - Configuration loading and parsing
//! - Identity data structures
//! - Security mode handling
//!
//! Note: Full UI tests require a display server (Xvfb in CI).
//! Run with: cargo test --test integration_test
//! Run with UI: xvfb-run -a cargo test --test integration_test -- --include-ignored

use std::fs;
use tempfile::TempDir;

// Import for ApplicationExt trait (provides application_id() method)
use gtk4::gio::prelude::ApplicationExt;

// Re-export config types for testing
// These would normally be in a lib.rs, but for integration tests we can use inline modules

/// Test configuration structure matching config.rs
mod test_config {
    use serde::{Deserialize, Serialize};
    use std::collections::HashMap;

    #[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
    #[serde(rename_all = "snake_case")]
    pub enum SecurityMode {
        MaximumSecurity,
        #[default]
        DeveloperWorkflow,
        TrustedWorkstation,
    }

    impl SecurityMode {
        pub fn display_name(&self) -> &'static str {
            match self {
                SecurityMode::MaximumSecurity => "Maximum Security",
                SecurityMode::DeveloperWorkflow => "Developer Workflow",
                SecurityMode::TrustedWorkstation => "Trusted Workstation",
            }
        }

        pub fn all() -> [SecurityMode; 3] {
            [
                SecurityMode::MaximumSecurity,
                SecurityMode::DeveloperWorkflow,
                SecurityMode::TrustedWorkstation,
            ]
        }

        pub fn index(&self) -> u32 {
            match self {
                SecurityMode::MaximumSecurity => 0,
                SecurityMode::DeveloperWorkflow => 1,
                SecurityMode::TrustedWorkstation => 2,
            }
        }

        pub fn from_index(index: u32) -> Self {
            match index {
                0 => SecurityMode::MaximumSecurity,
                1 => SecurityMode::DeveloperWorkflow,
                2 => SecurityMode::TrustedWorkstation,
                _ => SecurityMode::DeveloperWorkflow,
            }
        }
    }

    #[derive(Debug, Clone, Default, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct GpgConfig {
        #[serde(default)]
        pub key_id: String,
        #[serde(default)]
        pub sign_commits: bool,
        #[serde(default)]
        pub sign_tags: bool,
        #[serde(default)]
        pub auto_signoff: bool,
        #[serde(default)]
        pub security_mode: SecurityMode,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pub pin_storage_method: Option<String>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct Identity {
        pub provider: String,
        pub host: String,
        #[serde(default)]
        pub hostname: String,
        pub user: String,
        #[serde(default)]
        pub email: String,
        #[serde(default)]
        pub identity_file: String,
        #[serde(default)]
        pub gpg: Option<GpgConfig>,
    }

    #[derive(Debug, Clone, Default, Serialize, Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct Settings {
        #[serde(default)]
        pub default_provider: String,
        #[serde(default)]
        pub auto_detect: bool,
        #[serde(default)]
        pub use_keychain: bool,
        #[serde(default)]
        pub gpg_sign: bool,
        #[serde(default)]
        pub default_security_mode: SecurityMode,
    }

    #[derive(Debug, Clone, Default, Serialize, Deserialize)]
    pub struct Config {
        #[serde(default)]
        pub version: String,
        #[serde(default)]
        pub identities: HashMap<String, Identity>,
        #[serde(default)]
        pub settings: Settings,
    }

    impl Config {
        #[allow(dead_code)]
        pub fn load_from_str(json: &str) -> Result<Self, serde_json::Error> {
            serde_json::from_str(json)
        }
    }
}

use test_config::*;

// =============================================================================
// Configuration Tests
// =============================================================================

#[test]
fn test_parse_minimal_config() {
    let json = r#"{
        "version": "2.0.0",
        "identities": {},
        "settings": {}
    }"#;

    let config: Config = serde_json::from_str(json).expect("Failed to parse config");
    assert_eq!(config.version, "2.0.0");
    assert!(config.identities.is_empty());
}

#[test]
fn test_parse_full_config() {
    let json = r#"{
        "version": "2.0.0",
        "identities": {
            "personal": {
                "provider": "gitlab",
                "host": "gitlab-personal",
                "hostname": "gitlab.com",
                "user": "personaluser",
                "email": "personal@example.com",
                "identityFile": "~/.ssh/id_ed25519_personal"
            },
            "work": {
                "provider": "github",
                "host": "github.com",
                "hostname": "github.com",
                "user": "workuser",
                "email": "work@company.com",
                "identityFile": "~/.ssh/id_ed25519_work",
                "gpg": {
                    "keyId": "ABCD1234",
                    "signCommits": true,
                    "signTags": false,
                    "securityMode": "trusted_workstation",
                    "pinStorageMethod": "tpm"
                }
            }
        },
        "settings": {
            "defaultProvider": "gitlab",
            "autoDetect": true,
            "useKeychain": false,
            "gpgSign": true,
            "defaultSecurityMode": "developer_workflow"
        }
    }"#;

    let config: Config = serde_json::from_str(json).expect("Failed to parse config");

    assert_eq!(config.version, "2.0.0");
    assert_eq!(config.identities.len(), 2);

    // Check personal identity
    let personal = config
        .identities
        .get("personal")
        .expect("Missing personal identity");
    assert_eq!(personal.provider, "gitlab");
    assert_eq!(personal.email, "personal@example.com");
    assert!(personal.gpg.is_none());

    // Check work identity with GPG
    let work = config
        .identities
        .get("work")
        .expect("Missing work identity");
    assert_eq!(work.provider, "github");
    let gpg = work.gpg.as_ref().expect("Missing GPG config");
    assert_eq!(gpg.key_id, "ABCD1234");
    assert!(gpg.sign_commits);
    assert!(!gpg.sign_tags);
    assert_eq!(gpg.security_mode, SecurityMode::TrustedWorkstation);
    assert_eq!(gpg.pin_storage_method, Some("tpm".to_string()));

    // Check settings
    assert_eq!(config.settings.default_provider, "gitlab");
    assert!(config.settings.auto_detect);
    assert!(config.settings.gpg_sign);
}

#[test]
fn test_parse_config_with_missing_fields() {
    // Config with minimal required fields
    let json = r#"{
        "identities": {
            "test": {
                "provider": "github",
                "host": "github.com",
                "user": "testuser"
            }
        }
    }"#;

    let config: Config = serde_json::from_str(json).expect("Failed to parse minimal config");
    assert_eq!(config.identities.len(), 1);

    let identity = config.identities.get("test").unwrap();
    assert_eq!(identity.email, ""); // Default empty
    assert_eq!(identity.hostname, ""); // Default empty
}

#[test]
fn test_config_file_loading() {
    let temp_dir = TempDir::new().expect("Failed to create temp dir");
    let config_path = temp_dir.path().join("config.json");

    let config_json = r#"{
        "version": "2.0.0",
        "identities": {
            "file-test": {
                "provider": "gitlab",
                "host": "gitlab.com",
                "user": "fileuser",
                "email": "file@test.com"
            }
        }
    }"#;

    fs::write(&config_path, config_json).expect("Failed to write config file");

    let content = fs::read_to_string(&config_path).expect("Failed to read config");
    let config: Config = serde_json::from_str(&content).expect("Failed to parse config");

    assert!(config.identities.contains_key("file-test"));
}

// =============================================================================
// Security Mode Tests
// =============================================================================

#[test]
fn test_security_mode_display_names() {
    assert_eq!(
        SecurityMode::MaximumSecurity.display_name(),
        "Maximum Security"
    );
    assert_eq!(
        SecurityMode::DeveloperWorkflow.display_name(),
        "Developer Workflow"
    );
    assert_eq!(
        SecurityMode::TrustedWorkstation.display_name(),
        "Trusted Workstation"
    );
}

#[test]
fn test_security_mode_indexing() {
    assert_eq!(SecurityMode::MaximumSecurity.index(), 0);
    assert_eq!(SecurityMode::DeveloperWorkflow.index(), 1);
    assert_eq!(SecurityMode::TrustedWorkstation.index(), 2);

    assert_eq!(SecurityMode::from_index(0), SecurityMode::MaximumSecurity);
    assert_eq!(SecurityMode::from_index(1), SecurityMode::DeveloperWorkflow);
    assert_eq!(
        SecurityMode::from_index(2),
        SecurityMode::TrustedWorkstation
    );
    assert_eq!(
        SecurityMode::from_index(999),
        SecurityMode::DeveloperWorkflow
    ); // Default
}

#[test]
fn test_security_mode_all() {
    let modes = SecurityMode::all();
    assert_eq!(modes.len(), 3);
    assert_eq!(modes[0], SecurityMode::MaximumSecurity);
    assert_eq!(modes[1], SecurityMode::DeveloperWorkflow);
    assert_eq!(modes[2], SecurityMode::TrustedWorkstation);
}

#[test]
fn test_security_mode_serialization() {
    let mode = SecurityMode::TrustedWorkstation;
    let json = serde_json::to_string(&mode).expect("Failed to serialize");
    assert_eq!(json, "\"trusted_workstation\"");

    let parsed: SecurityMode = serde_json::from_str(&json).expect("Failed to parse");
    assert_eq!(parsed, SecurityMode::TrustedWorkstation);
}

// =============================================================================
// GPG Config Tests
// =============================================================================

#[test]
fn test_gpg_config_defaults() {
    let json = "{}";
    let gpg: GpgConfig = serde_json::from_str(json).expect("Failed to parse");

    assert_eq!(gpg.key_id, "");
    assert!(!gpg.sign_commits);
    assert!(!gpg.sign_tags);
    assert!(!gpg.auto_signoff);
    assert_eq!(gpg.security_mode, SecurityMode::DeveloperWorkflow);
    assert!(gpg.pin_storage_method.is_none());
}

#[test]
fn test_gpg_config_full() {
    let json = r#"{
        "keyId": "ABC123",
        "signCommits": true,
        "signTags": true,
        "autoSignoff": true,
        "securityMode": "maximum_security",
        "pinStorageMethod": "secure_enclave"
    }"#;

    let gpg: GpgConfig = serde_json::from_str(json).expect("Failed to parse");

    assert_eq!(gpg.key_id, "ABC123");
    assert!(gpg.sign_commits);
    assert!(gpg.sign_tags);
    assert!(gpg.auto_signoff);
    assert_eq!(gpg.security_mode, SecurityMode::MaximumSecurity);
    assert_eq!(gpg.pin_storage_method, Some("secure_enclave".to_string()));
}

// =============================================================================
// Identity Tests
// =============================================================================

#[test]
fn test_identity_provider_types() {
    let providers = ["gitlab", "github", "bitbucket"];

    for provider in providers {
        let json = format!(
            r#"{{
                "provider": "{}",
                "host": "test.com",
                "user": "testuser"
            }}"#,
            provider
        );

        let identity: Identity = serde_json::from_str(&json).expect("Failed to parse");
        assert_eq!(identity.provider, provider);
    }
}

// =============================================================================
// UI Tests (require display server)
// =============================================================================

#[test]
#[ignore = "Requires display server (Xvfb)"]
fn test_gtk_application_creation() {
    // This test requires GTK initialization which needs a display
    // Run with: xvfb-run -a cargo test test_gtk_application_creation -- --ignored

    gtk4::init().expect("Failed to init GTK");

    // Basic GTK test - just verify initialization works
    assert!(gtk4::is_initialized());
}

#[test]
#[ignore = "Requires display server (Xvfb)"]
fn test_adwaita_application_builder() {
    gtk4::init().expect("Failed to init GTK");

    let app = libadwaita::Application::builder()
        .application_id("dev.tinyland.RemoteJuggler.Test")
        .build();

    assert!(!app.application_id().unwrap().is_empty());
}

// =============================================================================
// Property-based Tests (using proptest crate, already in dev-dependencies)
// =============================================================================

#[cfg(test)]
mod proptest_tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn test_security_mode_roundtrip(idx in 0u32..=2) {
            let mode = SecurityMode::from_index(idx);
            let back_idx = mode.index();
            prop_assert_eq!(idx, back_idx);
        }

        #[test]
        fn test_security_mode_serialization_roundtrip(idx in 0u32..=2) {
            let mode = SecurityMode::from_index(idx);
            let json = serde_json::to_string(&mode).unwrap();
            let parsed: SecurityMode = serde_json::from_str(&json).unwrap();
            prop_assert_eq!(mode, parsed);
        }

        #[test]
        fn test_identity_email_preserves_value(email in "[a-z]{1,10}@[a-z]{1,10}\\.[a-z]{2,4}") {
            let json = format!(r#"{{
                "provider": "github",
                "host": "github.com",
                "user": "test",
                "email": "{}"
            }}"#, email);

            let identity: Identity = serde_json::from_str(&json).unwrap();
            prop_assert_eq!(identity.email, email);
        }
    }
}
