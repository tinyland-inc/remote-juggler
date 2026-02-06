//! Property-based tests for RemoteJuggler configuration
//!
//! Uses proptest to verify invariants and roundtrip properties.

use proptest::prelude::*;
use proptest::strategy::ValueTree;
use std::collections::HashMap;

use crate::config::{Config, GpgConfig, Identity, Settings, State};

// =============================================================================
// Custom Strategies
// =============================================================================

/// Generates valid SSH host aliases
/// Format: [a-z][a-z0-9-]* with reasonable length
fn ssh_host_alias() -> impl Strategy<Value = String> {
    prop::string::string_regex("[a-z][a-z0-9-]{0,30}")
        .expect("valid regex")
        .prop_filter("non-empty alias", |s| !s.is_empty())
}

/// Generates valid email addresses
/// Format: local@domain.tld
fn email_address() -> impl Strategy<Value = String> {
    (
        prop::string::string_regex("[a-z][a-z0-9._-]{0,20}").expect("valid regex"),
        prop::string::string_regex("[a-z][a-z0-9-]{0,15}").expect("valid regex"),
        prop::sample::select(vec!["com", "org", "net", "dev", "io"]),
    )
        .prop_map(|(local, domain, tld)| {
            let local = if local.is_empty() {
                "user".to_string()
            } else {
                local
            };
            let domain = if domain.is_empty() {
                "example".to_string()
            } else {
                domain
            };
            format!("{}@{}.{}", local, domain, tld)
        })
}

/// Generates valid provider strings
fn provider_string() -> impl Strategy<Value = String> {
    prop::sample::select(vec![
        "gitlab".to_string(),
        "github".to_string(),
        "bitbucket".to_string(),
    ])
}

/// Generates valid GPG key IDs
/// Format: 16 or 40 hex characters (short or long key ID)
fn gpg_key_id() -> impl Strategy<Value = String> {
    prop::bool::ANY.prop_flat_map(|use_long| {
        if use_long {
            prop::string::string_regex("[0-9A-F]{40}").expect("valid regex")
        } else {
            prop::string::string_regex("[0-9A-F]{16}").expect("valid regex")
        }
    })
}

/// Generates arbitrary GpgConfig structs
fn arb_gpg_config() -> impl Strategy<Value = GpgConfig> {
    (
        prop::option::of(gpg_key_id()),
        prop::bool::ANY,
        prop::bool::ANY,
        prop::bool::ANY,
        // security_mode: 0=MaximumSecurity, 1=DeveloperWorkflow, 2=TrustedWorkstation
        prop::sample::select(vec![0u32, 1, 2]),
        // pin_storage_method: None, or one of "tpm", "secure_enclave", "keychain"
        prop::option::of(prop::sample::select(vec![
            "tpm".to_string(),
            "secure_enclave".to_string(),
            "keychain".to_string(),
        ])),
    )
        .prop_map(
            |(
                key_id,
                sign_commits,
                sign_tags,
                auto_signoff,
                security_mode_idx,
                pin_storage_method,
            )| {
                use crate::config::SecurityMode;
                GpgConfig {
                    key_id: key_id.unwrap_or_default(),
                    sign_commits,
                    sign_tags,
                    auto_signoff,
                    security_mode: SecurityMode::from_index(security_mode_idx),
                    pin_storage_method,
                }
            },
        )
}

/// Generates arbitrary Identity structs
fn arb_identity() -> impl Strategy<Value = Identity> {
    (
        provider_string(),
        ssh_host_alias(),
        ssh_host_alias(),
        prop::string::string_regex("[a-z][a-z0-9_-]{0,20}").expect("valid regex"),
        email_address(),
        prop::string::string_regex("~/.ssh/id_[a-z_]+").expect("valid regex"),
        prop::sample::select(vec!["keychain", "env", "none"]),
        prop::collection::vec(
            prop::string::string_regex("[a-z][a-z0-9-]{0,15}").expect("valid regex"),
            0..3,
        ),
        arb_gpg_config(),
    )
        .prop_map(
            |(
                provider,
                host,
                hostname,
                user,
                email,
                ssh_key_path,
                credential_source,
                organizations,
                gpg,
            )| {
                let user = if user.is_empty() {
                    "user".to_string()
                } else {
                    user
                };
                let ssh_key_path = if ssh_key_path.is_empty() {
                    "~/.ssh/id_ed25519".to_string()
                } else {
                    ssh_key_path
                };
                Identity {
                    provider,
                    host,
                    hostname,
                    user,
                    email,
                    ssh_key_path,
                    credential_source: credential_source.to_string(),
                    organizations,
                    gpg,
                    keepassxc_entry: None,
                }
            },
        )
}

/// Generates arbitrary Settings structs
fn arb_settings() -> impl Strategy<Value = Settings> {
    (
        provider_string(),
        prop::bool::ANY,
        prop::bool::ANY,
        prop::bool::ANY,
        prop::bool::ANY,
        prop::bool::ANY,
        prop::bool::ANY,
    )
        .prop_map(
            |(
                default_provider,
                auto_detect,
                use_keychain,
                gpg_sign,
                gpg_verify_with_provider,
                fallback_to_ssh,
                verbose_logging,
            )| {
                Settings {
                    default_provider,
                    auto_detect,
                    use_keychain,
                    gpg_sign,
                    gpg_verify_with_provider,
                    fallback_to_ssh,
                    verbose_logging,
                }
            },
        )
}

/// Generates arbitrary State structs
fn arb_state(identity_names: Vec<String>) -> impl Strategy<Value = State> {
    (
        prop::option::of(prop::sample::select(identity_names)),
        prop::string::string_regex("2024-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
            .expect("valid regex"),
    )
        .prop_map(|(current_identity, last_switch)| State {
            current_identity: current_identity.unwrap_or_default(),
            last_switch,
        })
}

/// Generates identity pairs (base + security key variant)
fn arb_identity_pair() -> impl Strategy<Value = (String, Identity, Identity)> {
    (ssh_host_alias(), arb_identity()).prop_map(|(base_name, mut base_identity)| {
        // Ensure base identity doesn't have -sk suffix
        let base_name = base_name.trim_end_matches("-sk").to_string();
        base_identity.host = base_name.clone();
        base_identity.ssh_key_path = format!("~/.ssh/{}", base_name);

        // Create the security key variant
        let mut sk_identity = base_identity.clone();
        sk_identity.host = format!("{}-sk", base_name);
        sk_identity.ssh_key_path = format!("~/.ssh/{}-sk", base_name);

        (base_name, base_identity, sk_identity)
    })
}

/// Generates arbitrary Config structs
fn arb_config() -> impl Strategy<Value = Config> {
    // First generate identities
    prop::collection::hash_map(
        prop::string::string_regex("[a-z][a-z0-9-]{0,20}").expect("valid regex"),
        arb_identity(),
        1..5,
    )
    .prop_flat_map(|identities| {
        let identity_names: Vec<String> = identities.keys().cloned().collect();
        (
            Just(identities),
            arb_settings(),
            arb_state(if identity_names.is_empty() {
                vec!["default".to_string()]
            } else {
                identity_names
            }),
        )
    })
    .prop_map(|(identities, settings, state)| Config {
        schema: Some("https://remote-juggler.dev/schema/config.json".to_string()),
        version: "1.0".to_string(),
        generated: "2024-01-01T00:00:00Z".to_string(),
        identities,
        settings,
        state,
        extra: HashMap::new(),
    })
}

// =============================================================================
// Property Tests
// =============================================================================

proptest! {
    /// Property: Config roundtrip through JSON preserves all data
    #[test]
    fn prop_config_roundtrip(config in arb_config()) {
        // Serialize to JSON
        let json = serde_json::to_string_pretty(&config)
            .expect("serialization should succeed");

        // Deserialize back
        let roundtripped: Config = serde_json::from_str(&json)
            .expect("deserialization should succeed");

        // Verify key fields are preserved
        prop_assert_eq!(config.version, roundtripped.version);
        prop_assert_eq!(config.identities.len(), roundtripped.identities.len());
        prop_assert_eq!(config.settings.default_provider, roundtripped.settings.default_provider);
        prop_assert_eq!(config.state.current_identity, roundtripped.state.current_identity);

        // Verify all identity keys are preserved
        for key in config.identities.keys() {
            prop_assert!(roundtripped.identities.contains_key(key),
                "Identity '{}' should be preserved", key);
        }
    }

    /// Property: identity_names() returns a sorted, unique list
    #[test]
    fn prop_identity_names_sorted(config in arb_config()) {
        let names = config.identity_names();

        // Verify sorted
        let mut sorted_names = names.clone();
        sorted_names.sort();
        prop_assert_eq!(names.clone(), sorted_names, "identity_names() should return sorted list");

        // Verify unique (HashMap guarantees this, but let's verify)
        let unique_count = names.iter().collect::<std::collections::HashSet<_>>().len();
        prop_assert_eq!(names.len(), unique_count, "identity_names() should have unique entries");
    }

    /// Property: display_name() is never empty
    #[test]
    fn prop_display_name_non_empty(identity in arb_identity()) {
        let display_name = identity.display_name();
        prop_assert!(!display_name.is_empty(),
            "display_name() should never be empty, got empty for {:?}", identity);
    }

    /// Property: has_gpg_signing() is true iff key_id is non-empty AND sign_commits is true
    #[test]
    fn prop_gpg_signing_consistency(identity in arb_identity()) {
        let has_signing = identity.has_gpg_signing();
        let expected = !identity.gpg.key_id.is_empty() && identity.gpg.sign_commits;

        prop_assert_eq!(has_signing, expected,
            "has_gpg_signing() should match (key_id non-empty AND sign_commits)");
    }

    /// Property: Unknown JSON fields don't break parsing (via serde flatten)
    #[test]
    fn prop_extra_fields_preserved(
        config in arb_config(),
        extra_key in prop::string::string_regex("[a-z_]+").expect("valid regex"),
        extra_value in prop::string::string_regex("[a-zA-Z0-9 ]+").expect("valid regex"),
    ) {
        // Skip if extra_key collides with known fields
        let reserved = ["$schema", "version", "generated", "identities", "settings", "state"];
        prop_assume!(!reserved.contains(&extra_key.as_str()));
        prop_assume!(!extra_key.is_empty());

        // Serialize to JSON, then add an extra field
        let mut json_value: serde_json::Value = serde_json::to_value(&config)
            .expect("serialization should succeed");

        if let serde_json::Value::Object(ref mut map) = json_value {
            map.insert(extra_key.clone(), serde_json::Value::String(extra_value.clone()));
        }

        // Deserialize back - should not fail
        let json_str = serde_json::to_string(&json_value).expect("re-serialization should succeed");
        let parsed: Result<Config, _> = serde_json::from_str(&json_str);

        prop_assert!(parsed.is_ok(),
            "Parsing with extra field '{}' should succeed, got {:?}", extra_key, parsed.err());

        // Extra field should be captured in the extra HashMap
        let parsed_config = parsed.unwrap();
        prop_assert!(parsed_config.extra.contains_key(&extra_key),
            "Extra field '{}' should be captured in extra HashMap", extra_key);
    }

    /// Property: profiles() groups identities by provider+user
    #[test]
    fn prop_profiles_fewer_than_identities(config in arb_config()) {
        let profiles = config.profiles();
        let identity_count = config.identities.len();

        // Profiles should be <= identities (grouping reduces count or keeps same)
        prop_assert!(profiles.len() <= identity_count,
            "Profiles ({}) should not exceed identities ({})",
            profiles.len(), identity_count);

        // Total variants across all profiles should equal identity count
        let total_variants: usize = profiles.iter().map(|p| p.variants.len()).sum();
        prop_assert_eq!(total_variants, identity_count,
            "Total variants should equal identity count");
    }

    /// Property: Each profile has at least one variant
    #[test]
    fn prop_profiles_have_variants(config in arb_config()) {
        let profiles = config.profiles();

        for profile in profiles {
            prop_assert!(!profile.variants.is_empty(),
                "Profile '{}' should have at least one variant", profile.name);
        }
    }

    /// Property: is_security_key() correctly identifies -sk suffix
    #[test]
    fn prop_identity_sk_detection((base_name, base_identity, sk_identity) in arb_identity_pair()) {
        prop_assert!(!base_identity.is_security_key(),
            "Base identity '{}' should not be detected as security key", base_name);
        prop_assert!(sk_identity.is_security_key(),
            "SK identity '{}-sk' should be detected as security key", base_name);
    }
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn test_ssh_host_alias_strategy() {
        // Run a few samples to verify the strategy produces valid values
        let mut runner = proptest::test_runner::TestRunner::default();
        let strategy = ssh_host_alias();

        for _ in 0..10 {
            let value = strategy.new_tree(&mut runner).unwrap().current();
            assert!(!value.is_empty(), "SSH host alias should not be empty");
            assert!(
                value.chars().next().unwrap().is_ascii_lowercase(),
                "SSH host alias should start with lowercase letter"
            );
        }
    }

    #[test]
    fn test_email_address_strategy() {
        let mut runner = proptest::test_runner::TestRunner::default();
        let strategy = email_address();

        for _ in 0..10 {
            let value = strategy.new_tree(&mut runner).unwrap().current();
            assert!(value.contains('@'), "Email should contain @");
            assert!(value.contains('.'), "Email should contain .");
        }
    }

    #[test]
    fn test_gpg_key_id_strategy() {
        let mut runner = proptest::test_runner::TestRunner::default();
        let strategy = gpg_key_id();

        for _ in 0..10 {
            let value = strategy.new_tree(&mut runner).unwrap().current();
            assert!(
                value.len() == 16 || value.len() == 40,
                "GPG key ID should be 16 or 40 chars, got {}",
                value.len()
            );
            // GPG key IDs are uppercase hex digits (0-9, A-F)
            assert!(
                value
                    .chars()
                    .all(|c: char| c.is_ascii_digit() || ('A'..='F').contains(&c)),
                "GPG key ID should be uppercase hex, got: {}",
                value
            );
        }
    }
}
