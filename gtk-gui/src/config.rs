//! Configuration loading and management for RemoteJuggler GUI
//!
//! Reads the remote-juggler config.json and provides typed access to identities.
//!
//! Identities are grouped into Profiles based on provider+user combination.
//! Each profile can have multiple SSH key variants (regular vs FIDO2/YubiKey).

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// GPG signing configuration for an identity
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GpgConfig {
    pub key_id: String,
    pub sign_commits: bool,
    pub sign_tags: bool,
    pub auto_signoff: bool,
}

impl Default for GpgConfig {
    fn default() -> Self {
        Self {
            key_id: String::new(),
            sign_commits: false,
            sign_tags: false,
            auto_signoff: false,
        }
    }
}

/// A single git identity configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Identity {
    pub provider: String,
    pub host: String,
    pub hostname: String,
    pub user: String,
    pub email: String,
    pub ssh_key_path: String,
    pub credential_source: String,
    #[serde(default)]
    pub organizations: Vec<String>,
    #[serde(default)]
    pub gpg: GpgConfig,
}

impl Identity {
    /// Returns a display name for this identity
    pub fn display_name(&self) -> String {
        if self.user.is_empty() {
            self.host.clone()
        } else {
            format!("{} ({})", self.user, self.provider)
        }
    }

    /// Returns whether this identity has GPG signing enabled
    pub fn has_gpg_signing(&self) -> bool {
        !self.gpg.key_id.is_empty() && self.gpg.sign_commits
    }

    /// Returns whether this identity uses a FIDO2/YubiKey security key
    pub fn is_security_key(&self) -> bool {
        self.host.ends_with("-sk") || self.ssh_key_path.ends_with("-sk")
    }
}

/// SSH key variant type
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SshKeyType {
    /// Regular SSH key (ed25519, RSA, etc.)
    Regular,
    /// FIDO2/YubiKey security key (sk-ed25519, sk-ecdsa)
    Fido2,
}

impl SshKeyType {
    pub fn display_name(&self) -> &'static str {
        match self {
            SshKeyType::Regular => "SSH Key",
            SshKeyType::Fido2 => "Security Key (FIDO2)",
        }
    }

    pub fn short_name(&self) -> &'static str {
        match self {
            SshKeyType::Regular => "SSH",
            SshKeyType::Fido2 => "SK",
        }
    }
}

/// An SSH key variant within a profile
#[derive(Debug, Clone)]
pub struct SshVariant {
    /// The original identity name in the config
    pub identity_name: String,
    /// Type of SSH key
    pub key_type: SshKeyType,
    /// Reference to the identity
    pub identity: Identity,
}

impl SshVariant {
    pub fn display_name(&self) -> String {
        self.key_type.display_name().to_string()
    }
}

/// A profile groups identities by provider and user
///
/// Multiple SSH key variants (regular vs FIDO2) are grouped under a single profile.
#[derive(Debug, Clone)]
pub struct Profile {
    /// Profile name (e.g., "gitlab-personal", "github-personal")
    pub name: String,
    /// Git provider (gitlab, github, bitbucket)
    pub provider: String,
    /// Username on the provider
    pub user: String,
    /// Email address
    pub email: String,
    /// GPG configuration (shared across variants)
    pub gpg: GpgConfig,
    /// Available SSH key variants
    pub variants: Vec<SshVariant>,
}

impl Profile {
    /// Returns a display name for this profile
    pub fn display_name(&self) -> String {
        if self.user.is_empty() {
            self.name.clone()
        } else {
            format!("{} ({})", self.user, self.provider)
        }
    }

    /// Returns whether this profile has GPG signing enabled
    pub fn has_gpg_signing(&self) -> bool {
        !self.gpg.key_id.is_empty() && self.gpg.sign_commits
    }

    /// Get the default (preferred) variant - prefers FIDO2 if available
    pub fn default_variant(&self) -> Option<&SshVariant> {
        // Prefer FIDO2/security key if available
        self.variants.iter()
            .find(|v| v.key_type == SshKeyType::Fido2)
            .or_else(|| self.variants.first())
    }

    /// Get variant by key type
    pub fn get_variant(&self, key_type: &SshKeyType) -> Option<&SshVariant> {
        self.variants.iter().find(|v| &v.key_type == key_type)
    }

    /// Get the regular SSH key variant
    pub fn regular_variant(&self) -> Option<&SshVariant> {
        self.get_variant(&SshKeyType::Regular)
    }

    /// Get the FIDO2/security key variant
    pub fn fido2_variant(&self) -> Option<&SshVariant> {
        self.get_variant(&SshKeyType::Fido2)
    }

    /// Returns true if this profile has multiple SSH key variants
    pub fn has_multiple_variants(&self) -> bool {
        self.variants.len() > 1
    }
}

/// Application settings
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub default_provider: String,
    pub auto_detect: bool,
    pub use_keychain: bool,
    pub gpg_sign: bool,
    pub gpg_verify_with_provider: bool,
    #[serde(rename = "fallbackToSSH")]
    pub fallback_to_ssh: bool,
    pub verbose_logging: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            default_provider: "gitlab".to_string(),
            auto_detect: true,
            use_keychain: true,
            gpg_sign: true,
            gpg_verify_with_provider: true,
            fallback_to_ssh: true,
            verbose_logging: false,
        }
    }
}

/// Current state
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct State {
    pub current_identity: String,
    pub last_switch: String,
}

/// The complete RemoteJuggler configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(rename = "$schema")]
    pub schema: Option<String>,
    pub version: String,
    pub generated: String,
    pub identities: HashMap<String, Identity>,
    #[serde(default)]
    pub settings: Settings,
    #[serde(default)]
    pub state: State,
    // Capture any extra fields (managed blocks, etc.) without failing
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

impl Config {
    /// Load configuration from the default path
    pub fn load() -> Result<Self> {
        let config_path = Self::config_path()?;
        Self::load_from(&config_path)
    }

    /// Load configuration from a specific path
    pub fn load_from(path: &PathBuf) -> Result<Self> {
        let content = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read config file: {}", path.display()))?;

        let config: Config = serde_json::from_str(&content)
            .with_context(|| {
                // Try to get more detailed error
                match serde_json::from_str::<serde_json::Value>(&content) {
                    Ok(_) => "JSON valid but struct mismatch".to_string(),
                    Err(e) => format!("JSON parse error: {}", e),
                }
            })?;

        Ok(config)
    }

    /// Get the default config file path
    pub fn config_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .context("Could not determine config directory")?;

        Ok(config_dir.join("remote-juggler").join("config.json"))
    }

    /// Get a sorted list of identity names
    pub fn identity_names(&self) -> Vec<String> {
        let mut names: Vec<_> = self.identities.keys().cloned().collect();
        names.sort();
        names
    }

    /// Get an identity by name
    pub fn get_identity(&self, name: &str) -> Option<&Identity> {
        self.identities.get(name)
    }

    /// Get the current identity if set
    pub fn current_identity(&self) -> Option<&Identity> {
        if self.state.current_identity.is_empty() {
            None
        } else {
            self.get_identity(&self.state.current_identity)
        }
    }

    /// Group identities into profiles by provider+user
    ///
    /// Identities with `-sk` suffix are grouped with their non-sk counterpart
    /// as FIDO2/security key variants.
    pub fn profiles(&self) -> Vec<Profile> {
        // Group identities by (provider, user) tuple
        let mut profile_map: HashMap<(String, String), Vec<(String, Identity)>> = HashMap::new();

        for (name, identity) in &self.identities {
            let key = (identity.provider.clone(), identity.user.clone());
            profile_map.entry(key).or_default().push((name.clone(), identity.clone()));
        }

        // Convert to Profile structs
        let mut profiles: Vec<Profile> = profile_map
            .into_iter()
            .map(|((provider, user), identities)| {
                // Determine the base profile name (without -sk suffix)
                let base_name = identities.iter()
                    .map(|(name, _)| {
                        name.strip_suffix("-sk").unwrap_or(name).to_string()
                    })
                    .min_by_key(|n| n.len())
                    .unwrap_or_else(|| format!("{}-{}", provider, user));

                // Get email and GPG from the first identity (they should be the same)
                let first_identity = &identities[0].1;
                let email = first_identity.email.clone();
                let gpg = first_identity.gpg.clone();

                // Create variants
                let variants: Vec<SshVariant> = identities
                    .into_iter()
                    .map(|(name, identity)| {
                        let key_type = if identity.is_security_key() {
                            SshKeyType::Fido2
                        } else {
                            SshKeyType::Regular
                        };
                        SshVariant {
                            identity_name: name,
                            key_type,
                            identity,
                        }
                    })
                    .collect();

                Profile {
                    name: base_name,
                    provider,
                    user,
                    email,
                    gpg,
                    variants,
                }
            })
            .collect();

        // Sort profiles by name
        profiles.sort_by(|a, b| a.name.cmp(&b.name));

        // Sort variants within each profile (Regular before Fido2)
        for profile in &mut profiles {
            profile.variants.sort_by(|a, b| {
                match (&a.key_type, &b.key_type) {
                    (SshKeyType::Regular, SshKeyType::Fido2) => std::cmp::Ordering::Less,
                    (SshKeyType::Fido2, SshKeyType::Regular) => std::cmp::Ordering::Greater,
                    _ => a.identity_name.cmp(&b.identity_name),
                }
            });
        }

        profiles
    }

    /// Get a sorted list of profile names
    pub fn profile_names(&self) -> Vec<String> {
        self.profiles().into_iter().map(|p| p.name).collect()
    }

    /// Get a profile by name
    pub fn get_profile(&self, name: &str) -> Option<Profile> {
        self.profiles().into_iter().find(|p| p.name == name)
    }

    /// Get the current profile based on current identity
    pub fn current_profile(&self) -> Option<Profile> {
        if self.state.current_identity.is_empty() {
            return None;
        }

        let current = self.get_identity(&self.state.current_identity)?;
        self.profiles()
            .into_iter()
            .find(|p| p.provider == current.provider && p.user == current.user)
    }

    /// Get the current SSH variant being used
    pub fn current_variant(&self) -> Option<SshVariant> {
        if self.state.current_identity.is_empty() {
            return None;
        }

        let current_name = &self.state.current_identity;
        for profile in self.profiles() {
            for variant in profile.variants {
                if &variant.identity_name == current_name {
                    return Some(variant);
                }
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identity_display_name() {
        let identity = Identity {
            provider: "github".to_string(),
            host: "github.com".to_string(),
            hostname: "github.com".to_string(),
            user: "testuser".to_string(),
            email: "test@example.com".to_string(),
            ssh_key_path: String::new(),
            credential_source: "none".to_string(),
            organizations: vec![],
            gpg: GpgConfig::default(),
        };

        assert_eq!(identity.display_name(), "testuser (github)");
    }

    #[test]
    fn test_identity_is_security_key() {
        let regular = Identity {
            provider: "gitlab".to_string(),
            host: "gitlab-personal".to_string(),
            hostname: "gitlab.com".to_string(),
            user: "testuser".to_string(),
            email: "test@example.com".to_string(),
            ssh_key_path: "/home/user/.ssh/gitlab-personal".to_string(),
            credential_source: "none".to_string(),
            organizations: vec![],
            gpg: GpgConfig::default(),
        };

        let security_key = Identity {
            provider: "gitlab".to_string(),
            host: "gitlab-personal-sk".to_string(),
            hostname: "gitlab.com".to_string(),
            user: "testuser".to_string(),
            email: "test@example.com".to_string(),
            ssh_key_path: "/home/user/.ssh/gitlab-personal-sk".to_string(),
            credential_source: "none".to_string(),
            organizations: vec![],
            gpg: GpgConfig::default(),
        };

        assert!(!regular.is_security_key());
        assert!(security_key.is_security_key());
    }

    #[test]
    fn test_load_real_config() {
        let result = Config::load();
        match &result {
            Ok(c) => println!("Loaded {} identities", c.identities.len()),
            Err(e) => println!("Error loading config: {:?}", e),
        }
        assert!(result.is_ok(), "Failed to load config: {:?}", result.err());
    }

    #[test]
    fn test_profiles_grouping() {
        let result = Config::load();
        if let Ok(config) = result {
            let profiles = config.profiles();

            // Should have fewer profiles than identities due to grouping
            println!("Identities: {}, Profiles: {}", config.identities.len(), profiles.len());

            for profile in &profiles {
                println!("Profile: {} ({}) - {} variants",
                    profile.name, profile.provider, profile.variants.len());
                for variant in &profile.variants {
                    println!("  - {} ({})", variant.identity_name, variant.key_type.short_name());
                }
            }

            // Each profile should have at least one variant
            for profile in &profiles {
                assert!(!profile.variants.is_empty(),
                    "Profile {} has no variants", profile.name);
            }
        }
    }

    #[test]
    fn test_ssh_key_type_display() {
        assert_eq!(SshKeyType::Regular.display_name(), "SSH Key");
        assert_eq!(SshKeyType::Fido2.display_name(), "Security Key (FIDO2)");
        assert_eq!(SshKeyType::Regular.short_name(), "SSH");
        assert_eq!(SshKeyType::Fido2.short_name(), "SK");
    }

    #[test]
    fn test_profile_variant_methods() {
        let result = Config::load();
        if let Ok(config) = result {
            let profiles = config.profiles();

            for profile in &profiles {
                // Test default_variant returns something
                assert!(profile.default_variant().is_some(),
                    "Profile {} should have a default variant", profile.name);

                // If has multiple variants, should have both types
                if profile.has_multiple_variants() {
                    assert!(profile.regular_variant().is_some(),
                        "Profile {} with multiple variants should have regular", profile.name);
                    assert!(profile.fido2_variant().is_some(),
                        "Profile {} with multiple variants should have fido2", profile.name);
                }
            }
        }
    }
}
